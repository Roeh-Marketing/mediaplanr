# What a line item buys, besides money.
#
# Spend is the common currency -- the one quantity every channel shares and the
# only one scenarios compare on -- so it stays mandatory. Alongside it a line
# item may record what it is buying (`unit_type`), how much of it
# (`planned_units`), and at what price (`planned_rate`).
#
# Those three are bound by one identity:
#
#     planned_spend = planned_units * planned_rate / rate_per(unit_type)
#
# `rate_per` is 1000 for impressions, because the trade quotes a CPM rather
# than a price per impression, and 1 for everything else.
#
# All three are STORED, so an export or a glance at @data has them, and the
# validator enforces the identity so they cannot drift apart. What differs is
# which one gives way when spend changes: the RATE holds. A negotiated CPM does
# not improve because the budget was cut, so units follow spend and the rate
# survives. That is the whole editing rule, and it lives in one function.

#' The columns that record what a line item buys
#'
#' Reserved column names carried on `@data` when a plan records more than money.
#' Like the flighting columns they ride along: the validator checks them, but
#' they never form part of `@grain`.
#'
#' @return A character vector of the reserved column names.
#' @examples
#' unit_cols()
#' @export
unit_cols <- function() {
  c("unit_type", "planned_units", "planned_rate")
}

#' Unit types with a conventional rate basis
#'
#' The unit types this package knows a trade convention for. `unit_type` is
#' **not** restricted to these — media invents units faster than any package can
#' track them, and an unknown type is accepted and priced per single unit. These
#' are the ones where that would be wrong:
#'
#' * `"impression"` — quoted as a **CPM**, a cost per thousand, so `rate_per` is
#'   1000.
#'
#' Everything else is quoted per single unit: a CPC per click, a CPP per GRP, a
#' unit cost per spot.
#'
#' @return A character vector of the known unit types.
#' @examples
#' unit_type_levels()
#' @export
unit_type_levels <- function() {
  c("impression", "click", "grp", "trp", "spot", "view", "install",
    "engagement", "completed_view")
}

# How many units the quoted rate covers. 1000 for impressions (a CPM), 1
# otherwise. Vectorised; NA in, 1 out, so arithmetic never silently poisons.
.rate_per <- function(unit_type) {
  u <- tolower(trimws(as.character(unit_type)))
  ifelse(!is.na(u) & u %in% c("impression", "impressions"), 1000, 1)
}

# Solve the identity for whichever of the three is missing.
#
# Exactly one may be NULL. Returns a list of all three, so the caller stores a
# complete, self-consistent set whichever way the planner chose to author it.
.solve_trio <- function(spend, units, rate, rate_per, where = "") {
  have <- c(spend = !is.null(spend), units = !is.null(units),
            rate = !is.null(rate))
  if (sum(have) < 2L) {
    stop(where, "supply at least two of planned_spend / planned_units / ",
         "planned_rate; the third is computed. Got: ",
         if (!any(have)) "none" else paste(names(have)[have], collapse = ", "),
         ".", call. = FALSE)
  }
  if (!is.null(rate) && any(!is.na(rate) & rate < 0)) {
    stop(where, "`planned_rate` must not be negative.", call. = FALSE)
  }
  if (!is.null(units) && any(!is.na(units) & units < 0)) {
    stop(where, "`planned_units` must not be negative.", call. = FALSE)
  }

  if (is.null(spend)) {
    spend <- units * rate / rate_per
  } else if (is.null(units)) {
    units <- ifelse(rate > 0, spend * rate_per / rate, NA_real_)
  } else if (is.null(rate)) {
    rate <- ifelse(units > 0, spend * rate_per / units, NA_real_)
  }
  list(planned_spend = as.numeric(spend),
       planned_units = as.numeric(units),
       planned_rate  = as.numeric(rate))
}

# Re-derive units from spend at the held rate. THE editing rule: called
# wherever spend changes, so units always reflect the money at the negotiated
# price. A row with no rate, or a zero rate, keeps whatever units it has --
# there is no price to divide by, and guessing would be worse than leaving it.
.reunit <- function(d) {
  if (!all(c("planned_units", "planned_rate") %in% names(d)) || !nrow(d)) {
    return(d)
  }
  rp   <- .rate_per(if ("unit_type" %in% names(d)) d[["unit_type"]] else NA)
  rate <- d[["planned_rate"]]
  ok   <- !is.na(rate) & rate > 0 & !is.na(d[["planned_spend"]])
  d[["planned_units"]][ok] <- d[["planned_spend"]][ok] * rp[ok] / rate[ok]
  d
}

# Validator support: the unit columns are optional, but when present the
# identity must hold. Comparison is relative, because spend is split to the cent
# through flights and calendars and an exact test would fail on rounding.
.validate_unit_cols <- function(d, tol = 1e-6) {
  errs <- character(0)
  present <- intersect(unit_cols(), names(d))
  if (!length(present) || !nrow(d)) return(errs)

  for (nm in intersect(c("planned_units", "planned_rate"), present)) {
    v <- d[[nm]]
    if (!is.numeric(v)) {
      errs <- c(errs, paste0("'", nm, "' must be numeric."))
    } else if (any(!is.na(v) & v < 0)) {
      errs <- c(errs, paste0("'", nm, "' must not be negative."))
    }
  }
  if ("unit_type" %in% present && !is.character(d[["unit_type"]]) &&
      !is.factor(d[["unit_type"]])) {
    errs <- c(errs, "'unit_type' must be a character column.")
  }
  if (length(errs)) return(errs)

  if (all(c("planned_units", "planned_rate") %in% present)) {
    rp <- .rate_per(if ("unit_type" %in% present) d[["unit_type"]] else NA)
    implied <- d[["planned_units"]] * d[["planned_rate"]] / rp
    check <- !is.na(implied) & !is.na(d[["planned_spend"]]) & implied > 0
    if (any(check)) {
      off <- abs(implied[check] - d[["planned_spend"]][check]) /
        pmax(implied[check], 1)
      if (any(off > tol)) {
        i <- which(check)[which(off > tol)]
        errs <- c(errs, paste0(
          "planned_units x planned_rate does not equal planned_spend on row(s): ",
          paste(utils::head(i, 5), collapse = ", "),
          ". The three are bound by spend = units * rate / rate_per(unit_type); ",
          "supply any two and let the constructor compute the third."))
      }
    }
  }
  errs
}

# Rename a caller's column to the canonical name, when they named one.
.rename_col <- function(df, from, to) {
  if (is.null(from)) return(df)
  if (!from %in% names(df)) {
    stop("column '", from, "' not found in `df`.", call. = FALSE)
  }
  if (identical(from, to)) return(df)
  if (to %in% names(df)) df[[to]] <- NULL
  names(df)[names(df) == from] <- to
  df
}

# Fill in whichever of spend / units / rate the caller left out, so @data always
# holds a complete, self-consistent set however the plan was authored.
.complete_trio <- function(df) {
  have <- intersect(c("planned_spend", "planned_units", "planned_rate"),
                    names(df))
  if (length(have) < 2L) return(df)          # nothing to solve; spend only
  if (length(have) == 3L) return(df)         # all given; the validator checks it

  rp  <- .rate_per(if ("unit_type" %in% names(df)) df[["unit_type"]] else NA)
  got <- .solve_trio(
    spend = if ("planned_spend" %in% have) df[["planned_spend"]] else NULL,
    units = if ("planned_units" %in% have) df[["planned_units"]] else NULL,
    rate  = if ("planned_rate"  %in% have) df[["planned_rate"]]  else NULL,
    rate_per = rp)
  for (nm in names(got)) df[[nm]] <- got[[nm]]
  df
}

# Aggregate units for a group of rows, for roll_up() and calendarize().
#
# Units only add up within one unit_type: summing GRPs and clicks would produce
# a number that means nothing. A group that mixes them keeps its spend -- the
# common currency always survives -- and reports no units, rather than a total
# no one should act on.
#
# `k` is the group key, `keys` the groups in output order.
.aggregate_units <- function(d, k, keys) {
  if (!"planned_units" %in% names(d)) return(NULL)

  ut <- if ("unit_type" %in% names(d)) as.character(d[["unit_type"]]) else
    rep(NA_character_, nrow(d))
  one_type <- vapply(split(ut, k)[keys], function(v) {
    v <- unique(v[!is.na(v)])
    if (length(v) == 1L) v else NA_character_
  }, character(1))

  units <- vapply(split(d[["planned_units"]], k)[keys], function(v) {
    if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)
  }, numeric(1))
  units[is.na(one_type)] <- NA_real_

  list(unit_type = unname(one_type), planned_units = unname(units))
}

# Attach aggregated units to an output frame and derive the blended rate.
.attach_units <- function(out, agg) {
  if (is.null(agg)) return(out)
  out[["unit_type"]]     <- agg[["unit_type"]]
  out[["planned_units"]] <- agg[["planned_units"]]
  rp <- .rate_per(agg[["unit_type"]])
  u  <- agg[["planned_units"]]
  out[["planned_rate"]] <- ifelse(!is.na(u) & u > 0,
                                  out[["planned_spend"]] * rp / u, NA_real_)
  out
}

#' The cost of one unit, and the cost per thousand
#'
#' Derived from `planned_spend` and `planned_units`, never stored separately, so
#' neither can disagree with the plan's money.
#'
#' `cost_per_unit()` is always the price of a single unit. `cpm()` is the trade's
#' cost per thousand — the figure actually quoted for impressions — and is
#' simply `cost_per_unit() * 1000`, reported for any unit type on the assumption
#' that you asked for a reason.
#'
#' @param plan A [MediaPlan].
#' @return A numeric vector, one per row of `@data`. `NA` where a row records no
#'   units.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("Social", "Search"),
#'              unit_type = c("impression", "click"),
#'              planned_spend = c(140000, 95000),
#'              planned_units = c(28000000, 118750)),
#'   grain = "channel", name = "Q3 plan"
#' )
#'
#' cost_per_unit(p)
#' cpm(p)
#' p@data$planned_rate      # the CPM for Social, the CPC for Search
#' @export
cost_per_unit <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  d <- plan@data
  if (!"planned_units" %in% names(d)) return(rep(NA_real_, nrow(d)))
  u <- d[["planned_units"]]
  ifelse(!is.na(u) & u > 0, d[["planned_spend"]] / u, NA_real_)
}

#' @rdname cost_per_unit
#' @export
cpm <- function(plan) cost_per_unit(plan) * 1000
