# Spend bounds: money that cannot move.
#
# Much of a real plan's spend is not free to edit. An upfront commitment is
# fixed; a partner minimum is a floor; a capped line cannot take more. Each row
# may carry two optional columns that say so:
#
#     min_spend   the least this row may plan    (NA: no floor)
#     max_spend   the most this row may plan     (NA: no cap)
#
# Bounds are per row -- one line item for one period -- and they are the only
# thing stored. Whether a row is "committed" or merely has a floor is derived
# from them by .commitment(), so the label cannot disagree with the numbers.
#
# Every edit respects them. Ops that spread a change across a group (delta,
# total, transfer) route around a bound through .distribute(); ops that set
# each row (set, scale, delta_each, and allocation edits) are refused when a
# row would land outside its bounds. Bounds themselves change only through the
# `rebound` op, never as a side effect of moving money.

#' The columns that record a row's spend bounds
#'
#' Reserved column names carried on `@data` when some of a plan's spend cannot
#' move: an upfront commitment, a partner minimum, a cap. Like the flighting
#' and unit columns they ride along: the validator checks them, and they never
#' form part of `@grain`.
#'
#' - `min_spend` -- the least the row may plan. `NA` means no floor.
#' - `max_spend` -- the most the row may plan. `NA` means no cap.
#'
#' A row whose `min_spend` and `max_spend` both equal its `planned_spend` is
#' **committed**: no edit can move it. Every edit respects the bounds, and
#' they change only through an explicit `rebound` op; see [op_rebound()].
#'
#' @return A character vector of the reserved column names.
#' @examples
#' bound_cols()
#'
#' plan <- media_plan_from_df(
#'   data.frame(month = as.Date("2026-10-01"),
#'              channel = c("Streaming", "Search"),
#'              planned_spend = c(60000, 20000),
#'              min_spend = c(60000, NA), max_spend = c(60000, NA)),
#'   grain = "channel", time = "month", name = "Q4"
#' )
#' # Streaming is committed, so a cut comes entirely out of Search
#' build_scenario(plan, edits = op_delta(-5000), name = "trim")@data
#' @export
bound_cols <- function() {
  c("min_spend", "max_spend")
}

# Half a cent. Bounds are money, and money is split to the cent through flights
# and calendars, so a bound is met when it is met to the cent.
.cent_tol <- 0.005

# The floor and cap on every row of `d`, with "no bound" spelled as a number:
# 0 for no floor (a plan cannot hold negative spend anyway), Inf for no cap.
.lower_bounds <- function(d) {
  if (!"min_spend" %in% names(d)) return(rep(0, nrow(d)))
  ifelse(is.na(d[["min_spend"]]), 0, d[["min_spend"]])
}

.upper_bounds <- function(d) {
  if (!"max_spend" %in% names(d)) return(rep(Inf, nrow(d)))
  ifelse(is.na(d[["max_spend"]]), Inf, d[["max_spend"]])
}

# What kind of commitment each row of `d` carries, derived from its bounds:
#
#   "committed"  min and max both equal the spend: it cannot move at all
#   "floor"      a min above zero: it can grow, and shrink only to the floor
#   "capped"     a max: it can shrink, and grow only to the cap
#   "flexible"   no bounds
#
# A row with both a floor and a cap that is not committed reads "floor": the
# floor is the one that protects money already promised.
.commitment <- function(d) {
  lower <- .lower_bounds(d)
  upper <- .upper_bounds(d)
  spend <- d[["planned_spend"]]

  out <- rep("flexible", nrow(d))
  out[is.finite(upper)] <- "capped"
  out[lower > 0] <- "floor"
  committed <- is.finite(upper) &
    abs(upper - lower) < .cent_tol & abs(spend - lower) < .cent_tol
  out[committed] <- "committed"
  out
}

# A row key with its commitment, for error messages:
# "Streaming | Stream A | 2026-10-01 (committed)".
.bound_labels <- function(d, grain, rows) {
  paste0(line_item(d, grain)[rows], " (", .commitment(d)[rows], ")")
}

# Money for a message: no scientific notation, thousands separated.
.money <- function(x) {
  format(round(x, 2), big.mark = ",", scientific = FALSE, trim = TRUE)
}

# The first few of `x`, and how many more.
.first_few <- function(x, n = 3L) {
  more <- length(x) - n
  paste0(paste(utils::head(x, n), collapse = "; "),
         if (more > 0) paste0("; and ", more, " more") else "")
}

# ---- Spreading a change within bounds ----------------------------------------

# Spread `change` across a group of rows in proportion to `weights`, staying
# inside each row's bounds, and return the group's new planned_spend.
#
# THE ONE PLACE money is spread across rows: delta, total and transfer all come
# through here, so a rule about how a group absorbs a change is written once.
#
# It water-fills. Each round spreads what is left of the change over the rows
# that still have room, in proportion to their weights; a row that would cross
# its bound stops at it, and what it could not take goes round again to the
# rest. Each round either places everything or closes at least one row, so it
# ends within one round per row. With no bounds it is one round of plain
# proportional spreading.
#
# `keys`, `what` and `where` only word the error when the group cannot absorb
# the change: `keys` labels the rows, `what` names the op asking.
.distribute <- function(ps, change, weights, lower = 0, upper = Inf,
                        keys = NULL, what = "the change", where = "") {
  lower <- rep_len(lower, length(ps))
  upper <- rep_len(upper, length(ps))
  .stop_if_unabsorbable(ps, change, lower, upper, keys, what, where)

  growing <- change > 0
  has_room <- function(x) if (growing) x < upper else x > lower

  new  <- ps
  left <- change
  open <- has_room(new) & weights > 0
  while (abs(left) > 1e-9 && any(open)) {
    share <- ifelse(open, weights, 0)
    tried <- new + left * share / sum(share)
    moved <- pmin(pmax(tried, lower), upper)
    left  <- left - sum(moved - new)
    new   <- moved
    open  <- open & has_room(new)
  }

  # Every row with room had weight 0: nothing plans anything to spread by.
  if (abs(left) >= .cent_tol) {
    stop(where, what, " cannot be spread: the rows with room left plan ",
         "nothing, so there is no mix to spread it by.", call. = FALSE)
  }
  new
}

# Can the group absorb `change` at all? Each row can give down to its floor, or
# take up to its cap, and no more. Says how much it can absorb, and which
# bounds are in the way, when it cannot.
.stop_if_unabsorbable <- function(ps, change, lower, upper, keys, what,
                                  where) {
  if (change < 0) {
    room <- sum(ps - lower)
    if (-change <= room + .cent_tol) return(invisible(NULL))
    bound_by <- keys[lower > 0]
    stop(where, what, " cannot take ", .money(-change), " out of these rows: ",
         "their floors leave ", .money(room), " to give.",
         if (length(bound_by)) paste0(" Floors: ", .first_few(bound_by), "."),
         " Ask for less, or lower the floors first with `rebound`.",
         call. = FALSE)
  }
  room <- sum(upper - ps)
  if (change <= room + .cent_tol) return(invisible(NULL))
  bound_by <- keys[is.finite(upper)]
  stop(where, what, " cannot put ", .money(change), " into these rows: ",
       "their caps leave room for ", .money(room), ".",
       if (length(bound_by)) paste0(" Caps: ", .first_few(bound_by), "."),
       " Ask for less, or raise the caps first with `rebound`.",
       call. = FALSE)
}

# For the ops that set each row rather than spread a change -- set, scale,
# delta_each, allocation edits -- refuse when any row would land outside its
# bounds, naming the rows and what is in the way.
#
# Only real bounds are reported here. A value below zero on a row with no floor
# is left to the validator, whose "non-negative" is the truer message.
#
# `fix` is the advice that ends the message; `rebound` itself, which moves the
# bounds rather than the spend, words it the other way round.
.stop_if_outside_bounds <- function(values, lower, upper, keys, what,
                                    where = "",
                                    fix = paste("Leave these rows out, or",
                                                "change the bounds first with",
                                                "`rebound`.")) {
  low  <- values < lower - .cent_tol & lower > 0
  high <- values > upper + .cent_tol
  if (!any(low | high)) return(invisible(NULL))

  why <- ifelse(low, paste0("min ", .money(lower)), paste0("max ", .money(upper)))
  bad <- paste0(keys, " at ", .money(values), " (", why, ")")[low | high]
  stop(where, what, " would leave ", sum(low | high), " row(s) outside their ",
       "bounds: ", .first_few(bad), ". ", fix, call. = FALSE)
}

# ---- Bounds at a coarser grain -----------------------------------------------
#
# Where a row is cut into periods -- calendarize(), a flight expanding onto
# weeks -- each bound is spread exactly as a spend of the same size would be,
# so a committed row splits into committed periods to the cent. Those call
# sites do it inline; this is the other direction.

# Sum bounds to a coarser key, the way .aggregate_to() sums spend. A floor of
# "none" counts as 0, so a group's floor is the sum of the floors it has. A cap
# of "none" means the group has no cap: one uncapped row can take any amount.
.aggregate_bounds <- function(d, k, keys) {
  out <- list()
  if ("min_spend" %in% names(d)) {
    out$min_spend <- vapply(split(d[["min_spend"]], k)[keys], function(v) {
      if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)
    }, numeric(1), USE.NAMES = FALSE)
  }
  if ("max_spend" %in% names(d)) {
    out$max_spend <- vapply(split(d[["max_spend"]], k)[keys], function(v) {
      if (anyNA(v)) NA_real_ else sum(v)
    }, numeric(1), USE.NAMES = FALSE)
  }
  out
}

# Give `d` the bound columns if it lacks them, NA (no bound) throughout -- for
# an edit that introduces the first bound into a plan that had none.
.ensure_bound_cols <- function(d) {
  for (nm in setdiff(bound_cols(), names(d))) d[[nm]] <- rep(NA_real_, nrow(d))
  d
}

# ---- Validator support -------------------------------------------------------

# A bound column read from a file or a data frame that is NA throughout comes
# back logical; it means "no bounds", so make it the numeric column it is.
.normalise_bound_cols <- function(df) {
  for (nm in intersect(bound_cols(), names(df))) {
    if (is.logical(df[[nm]]) && all(is.na(df[[nm]]))) {
      df[[nm]] <- as.numeric(df[[nm]])
    }
  }
  df
}

# The bound columns are optional, but when present they must hold:
#   0 <= min_spend <= planned_spend <= max_spend   (to the cent)
# Returns a character vector of problems, naming the rows by `keys`.
.validate_bound_cols <- function(d, keys) {
  present <- intersect(bound_cols(), names(d))
  if (!length(present) || !nrow(d)) return(character(0))

  errs <- character(0)
  for (nm in present) {
    v <- d[[nm]]
    if (!is.numeric(v)) {
      errs <- c(errs, paste0("'", nm, "' must be numeric (NA for no bound)."))
    } else if (any(!is.na(v) & v < 0)) {
      errs <- c(errs, paste0("'", nm, "' must not be negative."))
    }
  }
  if (length(errs)) return(errs)

  lower <- .lower_bounds(d)
  upper <- .upper_bounds(d)
  spend <- d[["planned_spend"]]

  rows_where <- function(bad) .first_few(keys[bad])
  inverted <- lower > upper + .cent_tol
  if (any(inverted)) {
    errs <- c(errs, paste0("min_spend is above max_spend on: ",
                           rows_where(inverted), "."))
  }
  below <- spend < lower - .cent_tol
  if (any(below)) {
    errs <- c(errs, paste0("planned_spend is below min_spend on: ",
                           rows_where(below), "."))
  }
  above <- spend > upper + .cent_tol
  if (any(above)) {
    errs <- c(errs, paste0("planned_spend is above max_spend on: ",
                           rows_where(above), "."))
  }
  errs
}
