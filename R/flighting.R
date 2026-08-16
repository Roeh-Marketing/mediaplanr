# Flighting: how a buy is authored, and how it maps onto the weekly plan.
#
# A planner states a buy as a FLIGHT -- "OOH, Apr 6 to May 3, 120k". The plan
# holds WEEKS. These two are different things and the package keeps them
# separate: @data stays long, one row per line item per week, and a flight is an
# authoring format plus an exact view back over those rows.
#
# "Exact" is only possible because flight identity is stored. Weekly rows alone
# cannot be inverted -- four 30k weeks are equally consistent with one 28-day
# flight, four weekly buys, or two fortnightly ones -- so flights() reports
# nothing rather than guessing when there is no @flight_id to group on.

#' The columns that record flighting
#'
#' Reserved column names carried on `@data` when a plan was authored as flights.
#' They ride along: the validator type-checks them, but they never form part of
#' `@grain` and never key a row.
#'
#' @return A character vector of the reserved column names.
#' @examples
#' flight_cols()
#' @export
flight_cols <- function() {
  c("flight_id", "flight_start", "flight_end", "period_basis", "pacing")
}

#' The allowed buying cadences
#'
#' What kind of period a flight represents. `"day"` is a single dated
#' insertion, `"week"` a standard weekly buy, `"flight"` any other continuous
#' in-market period.
#'
#' @return A character vector of the valid, canonical values.
#' @examples
#' period_basis_levels()
#' @export
period_basis_levels <- function() {
  c("day", "week", "month", "flight")
}

#' The allowed pacing patterns
#'
#' How a flight's spend is shaped across its weeks. `"even"` means the weekly
#' figures are exactly what spreading the flight's total across its days gives.
#' `"custom"` means a planner has shaped it by hand and it no longer follows
#' that rule.
#'
#' Pacing is **re-derived after every edit**, so it describes the shape the rows
#' actually have rather than remembering whether anyone touched them. Two
#' consequences worth knowing:
#'
#' * Scaling a whole flight, or setting its total, leaves it `"even"` — every
#'   week moves in proportion, so only the amount changed, not the shape.
#' * Editing one week, or adding a flat amount to weeks of unequal length,
#'   makes it `"custom"`.
#'
#' Either way the flight survives: its `flight_id` is never dropped, so a
#' hand-shaped buy is still one buy and [flights()] still reports it whole.
#'
#' @return A character vector of the valid, canonical values.
#' @examples
#' pacing_levels()
#' @export
pacing_levels <- function() {
  c("even", "custom")
}

# Monday = 1 ... Sunday = 7, from a name or a number.
.weekday_num <- function(x) {
  if (is.numeric(x)) {
    n <- as.integer(x[1])
    if (is.na(n) || n < 1L || n > 7L) {
      stop("`week_start` must be 1 (Monday) through 7 (Sunday).", call. = FALSE)
    }
    return(n)
  }
  nms <- c("monday", "tuesday", "wednesday", "thursday", "friday",
           "saturday", "sunday")
  i <- pmatch(tolower(trimws(as.character(x)[1])), nms)
  if (is.na(i)) {
    stop("`week_start` must name a weekday (", paste(nms, collapse = ", "),
         ") or be 1-7 with Monday = 1.", call. = FALSE)
  }
  i
}

# seq.Date() and Date arithmetic can hand back an integer-backed Date, while
# as.Date() always gives a double-backed one. The difference is invisible until
# a caller compares a plan's weeks with identical(), so dates the package
# creates are normalised to match as.Date().
.as_date <- function(x) {
  structure(as.numeric(unclass(x)), class = "Date")
}

# Roll each date back to the start of the week it falls in.
.week_floor <- function(d, week_start = 1L) {
  dow <- as.integer(format(d, "%u"))          # ISO: Monday = 1 ... Sunday = 7
  .as_date(d - ((dow - week_start) %% 7L))
}

#' The weekday a plan's weeks begin on
#'
#' Derived from the week column rather than stored, so it cannot disagree with
#' the data. US broadcast weeks begin on a Monday; some advertisers plan
#' Sunday-start, and a plan read from a workbook may be either.
#'
#' @param plan A [MediaPlan].
#' @return The weekday name, or `NA_character_` when the plan has no time
#'   dimension, no rows, or weeks that do not all fall on the same weekday.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week = as.Date(c("2026-04-06", "2026-04-13")),
#'              channel = c("TV", "TV"), planned_spend = c(1, 2)),
#'   grain = c("channel", "week"), week = "week", name = "Q2 plan"
#' )
#' week_start(p)
#' @export
week_start <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!length(plan@week_col) || !nrow(plan@data)) return(NA_character_)
  w <- plan@data[[plan@week_col]]
  w <- w[!is.na(w)]
  if (!length(w)) return(NA_character_)

  dow <- unique(as.integer(format(w, "%u")))
  if (length(dow) != 1L) return(NA_character_)
  c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
    "Saturday", "Sunday")[dow]
}

# Split `total` across `weights` so that the shares are whole minor units (cents
# by default) that sum EXACTLY to the total's minor units.
#
# Naive proportional splitting does not do this: spreading 33,333 over 23 days
# and re-summing the weeks gives 33332.999999999996. Money must not evaporate in
# a unit conversion, so the split is done in integer minor units and the
# rounding residual is handed to the largest remainders (ties to the earliest
# period, so the result does not depend on sort stability).
.allocate_minor <- function(total, weights, digits = 2L) {
  units <- round(total * 10^digits)
  raw   <- units * weights / sum(weights)
  base  <- floor(raw)
  rem   <- as.integer(round(units - sum(base)))
  if (rem > 0L) {
    ord <- order(raw - base, seq_along(raw), decreasing = c(TRUE, FALSE),
                 method = "radix")[seq_len(rem)]
    base[ord] <- base[ord] + 1
  }
  base / 10^digits
}

# One flight -> the weekly rows it occupies, with its spend spread evenly across
# its days and then gathered into those weeks.
.spread_flight <- function(start, end, spend, week_start = 1L) {
  days  <- seq(start, end, by = "day")
  wk    <- .week_floor(days, week_start)
  weeks <- sort(unique(wk))
  n_day <- as.integer(table(factor(as.character(wk),
                                   levels = as.character(weeks))))
  data.frame(week = weeks, planned_spend = .allocate_minor(spend, n_day))
}

# What kind of period is this, when the caller did not say?
.infer_basis <- function(start, end, week_start = 1L) {
  n <- as.integer(end - start) + 1L
  if (n == 1L) return("day")
  if (n == 7L && identical(.week_floor(start, week_start), start)) return("week")
  "flight"
}

#' Build a plan from flights rather than weeks
#'
#' The other door into a [MediaPlan]. Where [media_plan_from_df()] takes the
#' plan already laid out by week, this takes it as a planner states it — one row
#' per **flight**, with in-market dates and a total — and expands it onto the
#' weekly rows `@data` holds. Everything downstream (the grid, `roll_up()`,
#' `build_scenario()`, `compare_scenarios()`) sees the ordinary weekly shape.
#'
#' Spend is spread evenly across the flight's days and then gathered into the
#' weeks those days fall in, so a flight that starts mid-week contributes a part
#' week at each ragged end. The split is exact to the cent: the weekly figures
#' always re-sum to the flight total.
#'
#' Each input row is given a `flight_id`, which is what makes [flights()] an
#' exact inverse. Without it the expansion could not be undone — four equal
#' weeks are indistinguishable from four weekly buys.
#'
#' @param df A data frame with one row per flight: the line item columns, a
#'   start date, an end date, and a spend.
#' @param grain Character vector naming the **line item** columns (channel,
#'   partner, tactic). The week column is created and appended, so do not
#'   include it.
#' @param start,end Names of the flight start and end date columns. `end` is
#'   inclusive. Coerced to `Date`.
#' @param planned_spend Name of the flight's total spend column.
#' @param week Name for the week column to create. Default `"week"`.
#' @param week_start Weekday the plan's weeks begin on — a name or 1-7 with
#'   Monday as 1. Default `"Monday"`, the US broadcast convention.
#' @param period_basis Optional column naming each flight's cadence, validated
#'   against [period_basis_levels()]. Inferred per flight when absent.
#' @param name Formal plan name. **Required**.
#' @param ... Further arguments passed to [media_plan_from_df()] — `nickname`,
#'   `advertiser`, `planner`, `status`, `objective`, `id`, `parent_id`.
#' @return A validated [MediaPlan] at grain `c(grain, week)`, carrying the
#'   [flight_cols()].
#' @examples
#' buys <- data.frame(
#'   channel      = c("OOH", "Search"),
#'   partner      = c("JCDecaux", "Google"),
#'   flight_start = as.Date(c("2026-04-06", "2026-04-08")),
#'   flight_end   = as.Date(c("2026-05-03", "2026-04-08")),
#'   planned_spend = c(120000, 3100)
#' )
#'
#' p <- media_plan_from_flights(buys, grain = c("channel", "partner"),
#'                              name = "Q2 flights")
#' p@data
#' flights(p)
#' @export
media_plan_from_flights <- function(df, grain,
                                    start = "flight_start",
                                    end = "flight_end",
                                    planned_spend = "planned_spend",
                                    week = "week",
                                    week_start = "Monday",
                                    period_basis = NULL,
                                    name, ...) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  ws <- .weekday_num(week_start)

  need <- c(grain, start, end, planned_spend)
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    stop("column(s) not found in `df`: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  if (week %in% names(df)) {
    stop("`week` ('", week, "') already exists in `df`. This constructor ",
         "creates the week column from the flight dates; use ",
         "media_plan_from_df() for a plan that is already laid out by week.",
         call. = FALSE)
  }

  fs <- .as_flight_date(df[[start]], start)
  fe <- .as_flight_date(df[[end]], end)
  if (anyNA(fs) || anyNA(fe)) {
    stop("flight dates must not be missing: every flight needs a start and an ",
         "end.", call. = FALSE)
  }
  if (any(fe < fs)) {
    bad <- which(fe < fs)[1]
    stop("flight ", bad, " ends (", format(fe[bad]), ") before it starts (",
         format(fs[bad]), ").", call. = FALSE)
  }

  spend <- df[[planned_spend]]
  if (!is.numeric(spend) || anyNA(spend) || any(spend < 0)) {
    stop("'", planned_spend, "' must be numeric, non-missing and non-negative.",
         call. = FALSE)
  }

  basis <- if (is.null(period_basis)) {
    vapply(seq_len(nrow(df)), function(i) .infer_basis(fs[i], fe[i], ws),
           character(1))
  } else {
    if (!period_basis %in% names(df)) {
      stop("`period_basis` column '", period_basis, "' not found in `df`.",
           call. = FALSE)
    }
    .check_levels(as.character(df[[period_basis]]), period_basis_levels(),
                  "period_basis")
  }

  # Expand each flight onto its weeks, remembering which flight each row is
  # part of so the operation can be undone exactly.
  pieces <- lapply(seq_len(nrow(df)), function(i) {
    sp <- .spread_flight(fs[i], fe[i], spend[i], ws)
    sp[[".src"]] <- i
    sp
  })
  alloc <- do.call(rbind, pieces)

  carry <- setdiff(names(df), c(start, end, planned_spend, period_basis))
  out <- df[alloc[[".src"]], carry, drop = FALSE]
  out[[week]]            <- alloc[["week"]]
  out[["planned_spend"]] <- alloc[["planned_spend"]]
  out[["flight_id"]]     <- .flight_ids(nrow(df))[alloc[[".src"]]]
  out[["flight_start"]]  <- fs[alloc[[".src"]]]
  out[["flight_end"]]    <- fe[alloc[[".src"]]]
  out[["period_basis"]]  <- basis[alloc[[".src"]]]
  out[["pacing"]]        <- rep("even", nrow(alloc))
  rownames(out) <- NULL

  .stop_on_flight_collision(out, grain, week)

  media_plan_from_df(out, grain = c(grain, week), week = week,
                     planned_spend = "planned_spend", name = name, ...)
}

# as.Date() errors on unparseable strings instead of returning NA, so the same
# guard media_plan_from_df() uses applies here.
.as_flight_date <- function(x, what) {
  if (inherits(x, "Date")) return(x)
  converted <- suppressWarnings(
    tryCatch(as.Date(x), error = function(e) rep(NA, length(x)))
  )
  if (all(is.na(converted)) && length(x)) {
    stop("column '", what, "' could not be coerced to Date. Supply Date ",
         "values or ISO-8601 strings.", call. = FALSE)
  }
  converted
}

.check_levels <- function(x, levels, what) {
  x <- trimws(tolower(x))
  bad <- setdiff(unique(x), levels)
  if (length(bad)) {
    stop("`", what, "` must be one of: ", paste(levels, collapse = ", "),
         "; got: ", paste(utils::head(bad, 5), collapse = ", "), ".",
         call. = FALSE)
  }
  x
}

.flight_ids <- function(n) {
  stamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  sprintf("fl_%s_%s", stamp, sprintf("%04x", sample.int(65535L, n)))
}

# Two flights of the same line item that overlap the same week would produce two
# rows at one grain cell. Rather than silently summing them -- which would merge
# two distinct buys and make flights() ambiguous -- say so, and name the fix.
.stop_on_flight_collision <- function(d, grain, week) {
  k <- line_item(d, c(grain, week))
  if (!anyDuplicated(k)) return(invisible(NULL))
  dups <- unique(k[duplicated(k)])
  stop("two flights of the same line item overlap the same week: ",
       paste(utils::head(dups, 3), collapse = "; "),
       ". A plan holds one period per line item per week, so add a column that ",
       "tells the buys apart (campaign, daypart, placement) and include it in ",
       "`grain`.", call. = FALSE)
}

# Re-derive each flight's pacing from the rows as they now stand.
#
# Called after every edit. A flight is "even" when its weekly figures are still
# exactly what spreading its current total across its days would give, and
# "custom" when they are not. Note what this means for the common cases:
#
#   * scaling a whole flight, or setting its total, keeps it even -- every row
#     moves in proportion, so the shape is unchanged. Only the amount changed.
#   * editing one week of a flight, or adding a flat delta to weeks of unequal
#     length, makes it custom -- the planner has shaped it by hand.
#
# The flight itself always survives: `flight_id` is never dropped, so a
# hand-shaped buy is still one buy and flights() still reports it whole. Pacing
# records the shape, not whether anyone touched it, so the answer is derived
# fresh every time and cannot go stale in either direction.
.repace <- function(d, week_col, tol = 1e-6) {
  if (!all(c("flight_id", "pacing") %in% names(d)) || !nrow(d)) return(d)
  span <- .span_of(d, week_col)
  if (is.null(span)) return(d)

  ndays <- as.integer(span$end - span$start) + 1L
  k  <- d[["flight_id"]]
  sp  <- d[["planned_spend"]]

  for (id in unique(k[!is.na(k)])) {
    i     <- which(k == id)
    total <- sum(sp[i])
    days  <- ndays[i]

    # Compare SHARES, not amounts. Amounts drift by fractions of a cent every
    # time a flight is scaled -- doubling values already rounded to the cent
    # does not land on the cent-exact allocation of the doubled total -- and an
    # exact comparison would call that drift "custom", which is wrong: scaling a
    # flight changes its size, not its shape. Shares are scale-free, so the
    # comparison means the same thing at any budget.
    even <- isTRUE(total > 0) &&
      max(abs(sp[i] / total - days / sum(days))) <= tol

    if (even) {
      # Snap back to the canonical allocation. Same total, at most a cent moved
      # between weeks, and it stops rounding drift accumulating across a chain
      # of scenarios -- an even flight always holds exactly the figures a fresh
      # import would give it.
      ord <- order(span$start[i])
      snapped <- numeric(length(i))
      snapped[ord] <- .allocate_minor(total, days[ord])
      d[["planned_spend"]][i] <- snapped
    }
    d[["pacing"]][i] <- if (even) "even" else "custom"
  }
  d
}

# Validator support: the reserved columns are optional, but when present they
# must be usable. Returns a character vector of problems (empty when fine).
#
# The consistency rule is the one that matters: rows sharing a flight_id are
# claiming to be one buy, so they must agree on that buy's dates and cadence.
# Without it flights() could report a flight whose dates depend on which row
# happened to come first.
.validate_flight_cols <- function(d) {
  errs <- character(0)
  present <- intersect(flight_cols(), names(d))
  if (!length(present) || !nrow(d)) return(errs)

  for (nm in intersect(c("flight_start", "flight_end"), present)) {
    if (!inherits(d[[nm]], "Date")) {
      errs <- c(errs, paste0("'", nm, "' must hold Date values."))
    }
  }
  if (all(c("flight_start", "flight_end") %in% present) &&
      inherits(d[["flight_start"]], "Date") &&
      inherits(d[["flight_end"]], "Date")) {
    bad <- which(!is.na(d[["flight_start"]]) & !is.na(d[["flight_end"]]) &
                   d[["flight_end"]] < d[["flight_start"]])
    if (length(bad)) {
      errs <- c(errs, paste0(
        "flight_end is before flight_start on row(s): ",
        paste(utils::head(bad, 5), collapse = ", "), "."))
    }
  }

  for (spec in list(c("period_basis", "period_basis"), c("pacing", "pacing"))) {
    nm <- spec[1]
    if (!nm %in% present) next
    vals <- unique(stats::na.omit(as.character(d[[nm]])))
    lv <- if (nm == "pacing") pacing_levels() else period_basis_levels()
    bad <- setdiff(vals, lv)
    if (length(bad)) {
      errs <- c(errs, paste0("'", nm, "' must be one of: ",
                             paste(lv, collapse = ", "), "; got: ",
                             paste(utils::head(bad, 5), collapse = ", "), "."))
    }
  }

  if ("flight_id" %in% present) {
    if (!is.character(d[["flight_id"]])) {
      errs <- c(errs, "'flight_id' must be a character column.")
    } else {
      k <- d[["flight_id"]]
      on <- !is.na(k)
      agree <- intersect(c("flight_start", "flight_end", "period_basis",
                           "pacing"), present)
      for (nm in agree) {
        n_distinct <- tapply(as.character(d[[nm]][on]), k[on],
                             function(v) length(unique(v)))
        if (any(n_distinct > 1L)) {
          ids <- names(n_distinct)[n_distinct > 1L]
          errs <- c(errs, paste0(
            "rows sharing a flight_id disagree on '", nm, "': ",
            paste(utils::head(ids, 3), collapse = ", "),
            ". Rows of one flight describe one buy."))
        }
      }
    }
  }
  errs
}

#' The flights a plan was authored from
#'
#' The inverse of [media_plan_from_flights()]: one row per flight, recovered by
#' grouping the weekly rows on `flight_id`.
#'
#' This is **exact, never inferred**. A plan built by [media_plan_from_df()]
#' has no flight identity recorded, and this returns no rows rather than
#' guessing — four consecutive equal weeks are equally consistent with one long
#' flight, four weekly buys, or two fortnightly ones, and nothing in the data
#' distinguishes them.
#'
#' @param plan A [MediaPlan].
#' @return A data frame: the [line_item_grain()] columns (excluding the week),
#'   `flight_id`, `flight_start`, `flight_end`, `period_basis`, `pacing`,
#'   `planned_spend` (the flight total) and `n_weeks`. Zero rows when the plan
#'   records no flights.
#' @examples
#' buys <- data.frame(
#'   channel = "OOH",
#'   flight_start = as.Date("2026-04-06"),
#'   flight_end   = as.Date("2026-05-03"),
#'   planned_spend = 120000
#' )
#' p <- media_plan_from_flights(buys, grain = "channel", name = "Q2 flights")
#'
#' flights(p)
#' sum(flights(p)$planned_spend) == sum(p@data$planned_spend)
#' @export
flights <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  d  <- plan@data
  lg <- setdiff(line_item_grain(plan), flight_cols())
  keep <- c(lg, "flight_id", "flight_start", "flight_end", "period_basis",
            "pacing")

  if (!"flight_id" %in% names(d) || !nrow(d)) {
    out <- d[0, intersect(keep, names(d)), drop = FALSE]
    out[["planned_spend"]] <- numeric(0)
    out[["n_weeks"]] <- integer(0)
    rownames(out) <- NULL
    return(out)
  }

  d <- d[!is.na(d[["flight_id"]]), , drop = FALSE]
  if (!nrow(d)) {
    out <- d[0, intersect(keep, names(d)), drop = FALSE]
    out[["planned_spend"]] <- numeric(0)
    out[["n_weeks"]] <- integer(0)
    rownames(out) <- NULL
    return(out)
  }

  k     <- d[["flight_id"]]
  first <- !duplicated(k)
  ids   <- k[first]
  out   <- d[first, intersect(keep, names(d)), drop = FALSE]

  out[["planned_spend"]] <- as.numeric(tapply(d[["planned_spend"]], k, sum)[ids])
  out[["n_weeks"]]       <- as.integer(table(k)[ids])

  out <- out[order(out[["flight_start"]], out[["flight_id"]]), , drop = FALSE]
  rownames(out) <- NULL
  out
}
