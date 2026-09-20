# Flighting: how a buy is authored, and how it maps onto the plan's calendar.
#
# A planner states a buy as a FLIGHT -- "OOH, Apr 6 to May 3, 120k". The plan
# holds PERIODS: weeks, usually, but days or months just as well. These two are
# different things and the package keeps them separate: @data stays long, one
# row per line item per period, and a flight is an authoring format plus an
# exact view back over those rows.
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
#'   period moves in proportion, so only the amount changed, not the shape.
#' * Editing one period, or adding a flat amount to periods of unequal length,
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

# Roll each date back to the start of the period it falls in. A moment lands on
# the calendar by the day it falls on, so a plan keyed by moments can still be
# cut onto days, weeks or months.
.period_floor <- function(d, basis, week_start = 1L) {
  d <- .to_date(d)
  switch(basis,
    day   = d,
    week  = .week_floor(d, week_start),
    month = .as_date(as.Date(format(d, "%Y-%m-01"))))
}

#' The weekday a plan's weeks begin on
#'
#' Derived from the time column rather than stored, so it cannot disagree with
#' the data. US broadcast weeks begin on a Monday; some advertisers plan
#' Sunday-start, and a plan read from a workbook may be either.
#'
#' Only a weekly plan has one: on a plan whose `@time_basis` is `"day"`,
#' `"month"` or `"instant"` there is no such weekday and this is `NA`.
#'
#' @param plan A [MediaPlan].
#' @return The weekday name, or `NA_character_` when the plan is not weekly,
#'   has no rows, or has weeks that do not all fall on the same weekday.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week = as.Date(c("2026-04-06", "2026-04-13")),
#'              channel = c("TV", "TV"), planned_spend = c(1, 2)),
#'   grain = "channel", time = "week", name = "Q2 plan"
#' )
#' week_start(p)
#' @export
week_start <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!identical(plan@time_basis, "week") || !nrow(plan@data)) {
    return(NA_character_)
  }
  w <- plan@data[[plan@time_col]]
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

# One flight -> the plan rows it occupies, with its spend spread evenly across
# its days and then gathered into the periods those days fall in.
#
# A timed buy is the exception, and it is not a special case so much as the
# degenerate one: a spot bought for 20:00 to 20:30 occupies exactly one row, so
# there is nothing to spread. The whole total sits on the moment the buy starts
# and .span_of() reads its length back off the flight.
.spread_flight <- function(start, end, spend, basis = "week", week_start = 1L) {
  if (identical(basis, "instant")) {
    return(data.frame(period = start, planned_spend = spend))
  }
  days    <- seq(.to_date(start), .to_date(end), by = "day")
  per     <- .period_floor(days, basis, week_start)
  periods <- sort(unique(per))
  n_day   <- as.integer(table(factor(as.character(per),
                                     levels = as.character(periods))))
  data.frame(period = periods, planned_spend = .allocate_minor(spend, n_day))
}

# What kind of period is this, when the caller did not say?
.infer_basis <- function(start, end, week_start = 1L) {
  n <- as.integer(end - start) + 1L
  if (n == 1L) return("day")
  if (n == 7L && identical(.week_floor(start, week_start), start)) return("week")
  "flight"
}

#' Build a plan from flights rather than periods
#'
#' The other door into a [MediaPlan]. Where [media_plan_from_df()] takes the
#' plan already laid out period by period, this takes it as a planner states
#' it — one row per **flight**, with in-market dates and a total — and expands
#' it onto the rows `@data` holds. Everything downstream (the grid,
#' `roll_up()`, `build_scenario()`, `compare_scenarios()`) sees the ordinary
#' shape.
#'
#' Spend is spread evenly across the flight's days and then gathered into the
#' periods those days fall in, so a flight that starts mid-week contributes a
#' part week at each ragged end. The split is exact to the cent: the period
#' figures always re-sum to the flight total.
#'
#' A buy bought by the slot rather than the period — a 30-second spot, a
#' half-hour sponsorship — is the degenerate case: with `basis = "instant"` each
#' one becomes a single row at the moment it starts, carrying its whole total.
#' Nothing is spread, and the buy's length is read back off its flight.
#'
#' Each input row is given a `flight_id`, which is what makes [flights()] an
#' exact inverse. Without it the expansion could not be undone — four equal
#' weeks are indistinguishable from four weekly buys.
#'
#' @param df A data frame with one row per flight: the line item columns, a
#'   start date, an end date, and a spend.
#' @param grain Character vector naming the **line item** columns (channel,
#'   partner, tactic). The time column is created and appended, so do not
#'   include it.
#' @param start,end Names of the flight start and end date columns. `end` is
#'   inclusive. Coerced to `Date`.
#' @param planned_spend Name of the flight's total spend column.
#' @param basis The calendar the flights are expanded onto, and the plan's
#'   `@time_basis`: `"week"` (default), `"day"`, `"month"` or `"instant"`.
#'   `"instant"` is for buys bought by the slot rather than the period — a
#'   30-second spot at 20:00:00, a half-hour sponsorship from 20:00 to 20:30.
#'   Each one becomes a single row keyed at the moment it starts, carrying its
#'   whole total: there is nothing to spread, and the buy's length is read back
#'   off its flight dates.
#' @param time Name for the time column to create. Defaults to `basis`, so a
#'   weekly plan gets a `week` column and a monthly one a `month` column; a
#'   timed plan gets `time`.
#' @param week_start Weekday the plan's weeks begin on — a name or 1-7 with
#'   Monday as 1. Default `"Monday"`, the US broadcast convention. Used when
#'   `basis = "week"`.
#' @param tz The plan's timezone, as an Olson name. Timed flight dates given as
#'   strings are read on it. See [media_plan_from_df()].
#' @param period_basis Optional column naming each flight's cadence, validated
#'   against [period_basis_levels()]. Inferred per flight when absent.
#' @param name Formal plan name. **Required**.
#' @param ... Further arguments passed to [media_plan_from_df()] — `nickname`,
#'   `advertiser`, `planner`, `status`, `objective`, `id`, `parent_id`.
#' @return A validated [MediaPlan] at grain `c(grain, time)`, carrying the
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
                                    basis = c("week", "day", "month",
                                              "instant"),
                                    time = NULL,
                                    week_start = "Monday",
                                    tz = NULL,
                                    period_basis = NULL,
                                    name, ...) {
  basis <- match.arg(basis)
  time  <- if (!is.null(time)) {
    as.character(time)[1]
  } else if (identical(basis, "instant")) {
    "time"
  } else {
    basis
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  ws <- .weekday_num(week_start)

  need <- c(grain, start, end, planned_spend)
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    stop("column(s) not found in `df`: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  if (time %in% names(df)) {
    stop("`time` ('", time, "') already exists in `df`. This constructor ",
         "creates the time column from the flight dates; use ",
         "media_plan_from_df() for a plan that is already laid out by period.",
         call. = FALSE)
  }

  fs <- .as_flight_time(df[[start]], start, basis, tz)
  fe <- .as_flight_time(df[[end]], end, basis, tz)
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

  # Each flight's own cadence, which is a different question from the plan's
  # `basis`: what kind of buy this is, not what one plan row covers.
  fb <- if (is.null(period_basis) && identical(basis, "instant")) {
    # A slot is a continuous in-market period that is neither a dated
    # insertion nor a standard week, which is what "flight" names.
    rep("flight", nrow(df))
  } else if (is.null(period_basis)) {
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

  # Expand each flight onto its periods, remembering which flight each row is
  # part of so the operation can be undone exactly. A timed buy expands onto
  # exactly one row: the slot it occupies.
  pieces <- lapply(seq_len(nrow(df)), function(i) {
    sp <- .spread_flight(fs[i], fe[i], spend[i], basis, ws)
    sp[[".src"]] <- i
    sp
  })
  alloc <- do.call(rbind, pieces)

  carry <- setdiff(names(df), c(start, end, planned_spend, period_basis))
  out <- df[alloc[[".src"]], carry, drop = FALSE]
  out[[time]]            <- alloc[["period"]]
  out[["planned_spend"]] <- alloc[["planned_spend"]]
  out[["flight_id"]]     <- .flight_ids(nrow(df))[alloc[[".src"]]]
  out[["flight_start"]]  <- fs[alloc[[".src"]]]
  out[["flight_end"]]    <- fe[alloc[[".src"]]]
  out[["period_basis"]]  <- fb[alloc[[".src"]]]
  out[["pacing"]]        <- rep("even", nrow(alloc))
  rownames(out) <- NULL

  # A flight's units belong to the whole buy, so carrying them down each week
  # would repeat the total. Re-derive them from each week's share of the spend
  # at the held rate.
  out <- .reunit(out)

  .stop_on_flight_collision(out, grain, time)

  media_plan_from_df(out, grain = grain, time = time, time_basis = basis,
                     tz = tz, planned_spend = "planned_spend", name = name,
                     ...)
}

# Flight dates, in the type the plan's time column holds: moments on a timed
# plan, dates otherwise. A timed buy given whole dates starts at midnight.
.as_flight_time <- function(x, what, basis, tz = NULL) {
  if (!identical(basis, "instant")) return(.as_flight_date(x, what))
  zone <- if (!is.null(tz) && !is.na(tz[1])) tz[1] else ""
  v <- .as_time_col(x, what, zone)
  if (inherits(v, "Date")) {
    v <- as.POSIXct(paste0(format(v), " 00:00:00"), tz = zone)
  }
  .stamp_tz(v, zone)
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

# Two flights of the same line item that overlap the same period would produce
# two rows at one grain cell. Rather than silently summing them -- which would
# merge two distinct buys and make flights() ambiguous -- say so, and name the
# fix.
.stop_on_flight_collision <- function(d, grain, time) {
  k <- line_item(d, c(grain, time))
  if (!anyDuplicated(k)) return(invisible(NULL))
  dups <- unique(k[duplicated(k)])
  stop("two flights of the same line item overlap the same period: ",
       paste(utils::head(dups, 3), collapse = "; "),
       ". A plan holds one row per line item per period, so add a column that ",
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
.repace <- function(d, time_col, basis, tol = 1e-6) {
  if (!all(c("flight_id", "pacing") %in% names(d)) || !nrow(d)) return(d)
  span <- .span_of(d, time_col, basis)
  if (is.null(span)) return(d)

  ndays <- as.integer(.to_date(span$end) - .to_date(span$start)) + 1L
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
.validate_flight_cols <- function(d, type = "date") {
  errs <- character(0)
  present <- intersect(flight_cols(), names(d))
  if (!length(present) || !nrow(d)) return(errs)

  # Flight dates are compared against the time column on every span, so they
  # are held to its type: Dates on a dated plan, moments on a timed one.
  if (is.na(type)) type <- "date"
  want <- if (identical(type, "datetime")) "POSIXct" else "Date"
  for (nm in intersect(c("flight_start", "flight_end"), present)) {
    if (!inherits(d[[nm]], want)) {
      errs <- c(errs, paste0("'", nm, "' must hold ", want, " values",
                             if (identical(want, "POSIXct")) {
                               ", to match a time column of moments"
                             } else "", "."))
    }
  }
  if (all(c("flight_start", "flight_end") %in% present) &&
      inherits(d[["flight_start"]], want) &&
      inherits(d[["flight_end"]], want)) {
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

#' Re-cut a plan onto a different calendar
#'
#' The temporal counterpart to [roll_up()]. Where `roll_up()` aggregates over
#' *dimensions* — channel, partner, tactic — this aggregates over *time*: it
#' spreads each row's spend across the days it is actually in market, then
#' gathers those days into days, weeks or months.
#'
#' The two are deliberately separate verbs rather than one with a mode flag, so
#' they compose: roll a plan up to channel, then cut it to months, in whichever
#' order suits.
#'
#' Because each row's period is the period its time value opens **clipped to its
#' flight**, a flight that starts mid-week contributes only its real days.
#' Re-cutting to months therefore splits a week that straddles a month boundary,
#' which is exactly the thing that is tedious and error-prone to do by hand.
#' Spend is split in whole cents that re-sum to the row's original total.
#'
#' A plan keyed by moments cuts onto a calendar too: each spot lands on the day
#' it airs, and from there into its week or month.
#'
#' @section Why a data frame, not a plan:
#' This returns a **projection**, like [compare_scenarios()] — something to
#' chart, export, or hand to a reconciliation. It is not a [MediaPlan], because
#' aggregating over time can merge two of a line item's rows into one period,
#' and a flight that spanned them is no longer one row's worth of anything: the
#' flighting columns cannot survive the operation honestly, so they are dropped
#' rather than guessed at. Editing belongs on the plan, where the flights still
#' are. If you do want a plan at the new grain, pass the result to
#' [media_plan_from_df()].
#'
#' @param plan A [MediaPlan].
#' @param basis The calendar to cut onto: `"week"` (default), `"day"` or
#'   `"month"`. Not `"instant"` — re-cutting spreads a period's spend across
#'   days, and there is no such thing as spreading it across moments.
#' @param week_start Weekday weeks begin on, when `basis = "week"`. Defaults to
#'   the plan's own, read off its data by [week_start()], and to Monday when
#'   the plan is not weekly.
#' @return A data frame: the line item columns, a date column named after
#'   `basis` holding each period's start, and `planned_spend`. One row per line
#'   item per period, ordered by period.
#' @examples
#' p <- media_plan_from_flights(
#'   data.frame(channel = "OOH",
#'              flight_start = as.Date("2026-04-20"),
#'              flight_end   = as.Date("2026-05-10"),
#'              planned_spend = 210000),
#'   grain = "channel", name = "Straddles a month end"
#' )
#'
#' calendarize(p, "week")
#' calendarize(p, "month")   # the week of Apr 27 is split across April and May
#' @export
calendarize <- function(plan, basis = c("week", "day", "month"),
                        week_start = NULL) {
  basis <- match.arg(basis)
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  span <- .row_span(plan)
  ws <- if (is.null(week_start)) .plan_week_start(plan) else .weekday_num(week_start)

  d  <- plan@data
  lg <- setdiff(line_item_grain(plan), flight_cols())
  if (!length(lg)) {
    stop("the plan's grain is only its time column and flight bookkeeping, so ",
         "there are no line items to re-cut.", call. = FALSE)
  }

  if (!nrow(d)) {
    out <- d[0, lg, drop = FALSE]
    out[[basis]] <- as.Date(character(0))
    out[["planned_spend"]] <- numeric(0)
    rownames(out) <- NULL
    return(out)
  }
  bad <- which(is.na(span$start) | is.na(span$end))
  if (length(bad)) {
    stop("row(s) ", paste(utils::head(bad, 5), collapse = ", "),
         " have no dates, so they cannot be placed on a calendar.",
         call. = FALSE)
  }

  pieces <- lapply(seq_len(nrow(d)), function(i) {
    days    <- seq(.to_date(span$start[i]), .to_date(span$end[i]), by = "day")
    per     <- .period_floor(days, basis, ws)
    periods <- sort(unique(per))
    n_day   <- as.integer(table(factor(as.character(per),
                                       levels = as.character(periods))))
    data.frame(.src = i, period = periods,
               planned_spend = .allocate_minor(d[["planned_spend"]][i], n_day))
  })
  a <- do.call(rbind, pieces)

  # Carry what units need to be re-derived from each period's share of the
  # spend: the unit type and the held rate. Units themselves are recomputed
  # rather than split, so they follow the money exactly.
  carry <- intersect(c("unit_type", "planned_rate"), names(d))
  out <- d[a[[".src"]], c(lg, carry), drop = FALSE]
  out[[basis]]           <- a[["period"]]
  out[["planned_spend"]] <- a[["planned_spend"]]
  if ("planned_rate" %in% carry) {
    out[["planned_units"]] <- NA_real_
    out <- .reunit(out)
  }

  # Re-cutting can land two of a line item's rows in one period -- two weeks in
  # a month, two spots in a day, or two flights of the same buy -- so periods
  # are summed. This is
  # aggregation, unlike the import path, where a collision means two distinct
  # buys and is an error.
  res <- .aggregate_to(out, c(lg, basis))

  res <- res[order(res[[basis]], line_item(res, lg)), , drop = FALSE]
  rownames(res) <- NULL
  res
}

#' The flights a plan was authored from
#'
#' The inverse of [media_plan_from_flights()]: one row per flight, recovered by
#' grouping the plan's rows on `flight_id`.
#'
#' This is **exact, never inferred**. A plan built by [media_plan_from_df()]
#' has no flight identity recorded, and this returns no rows rather than
#' guessing — four consecutive equal weeks are equally consistent with one long
#' flight, four weekly buys, or two fortnightly ones, and nothing in the data
#' distinguishes them.
#'
#' @param plan A [MediaPlan].
#' @return A data frame: the [line_item_grain()] columns, `flight_id`,
#'   `flight_start`, `flight_end`, `period_basis`, `pacing`, `planned_spend`
#'   (the flight total) and `n_periods` — how many plan rows the flight
#'   occupies. Zero rows when the plan records no flights.
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
    out[["n_periods"]] <- integer(0)
    rownames(out) <- NULL
    return(out)
  }

  d <- d[!is.na(d[["flight_id"]]), , drop = FALSE]
  if (!nrow(d)) {
    out <- d[0, intersect(keep, names(d)), drop = FALSE]
    out[["planned_spend"]] <- numeric(0)
    out[["n_periods"]] <- integer(0)
    rownames(out) <- NULL
    return(out)
  }

  k     <- d[["flight_id"]]
  first <- !duplicated(k)
  ids   <- k[first]
  out   <- d[first, intersect(keep, names(d)), drop = FALSE]

  out[["planned_spend"]] <- as.numeric(tapply(d[["planned_spend"]], k, sum)[ids])
  out[["n_periods"]]     <- as.integer(table(k)[ids])

  out <- out[order(out[["flight_start"]], out[["flight_id"]]), , drop = FALSE]
  rownames(out) <- NULL
  out
}
