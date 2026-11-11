# The plan's own dates. Everything here is derived from @data, so none of it can
# go stale: a value that could change without the plan changing does not belong
# on a plan (see vignette("plan_concepts")).

# The dates each row is in market.
#
# THE ONE PLACE that answers "what dates does this row cover?". A row's period
# is the period its time value opens -- a day, a week, a month, or the moment
# itself -- clipped to the flight the row belongs to. That clipping is what
# makes ragged periods work: a flight starting on a Wednesday makes its first
# weekly row a five-day period, and a flight ending mid-week makes its last one
# shorter too. A row with no flight simply spans its whole period.
#
# Because the period is derived from (time value, @time_basis, flight_start,
# flight_end), no period_start / period_end columns are stored and nothing can
# disagree. The basis is what keeps this honest across cadences: before it
# existed every row was seven days long, which was wrong for a daily plan and
# meaningless for a timestamp.
#
# Returns a data frame of `start` and `end` in the time column's own type,
# positionally aligned with plan@data.
.row_span <- function(plan) {
  .span_of(plan@data, plan@time_col, plan@time_basis)
}

# The same question asked of a bare data frame, for the edit path -- which works
# on @data before a MediaPlan exists to wrap it. NULL when the frame carries no
# time column, which a plan's never does.
.span_of <- function(d, time_col, basis) {
  if (!length(time_col) || !time_col %in% names(d)) return(NULL)
  start <- d[[time_col]]
  end   <- .period_end(start, basis)

  if (all(c("flight_start", "flight_end") %in% names(d))) {
    fs <- .align_time(d[["flight_start"]], start)
    fe <- .align_time(d[["flight_end"]],   start)
    on <- !is.na(fs) & !is.na(fe)
    if (identical(basis, "instant")) {
      # A timed row IS its buy -- one row per flight, not a period the buy was
      # spread across -- so the flight's own interval is the row's extent. That
      # is what gives a 30-second spot at 20:00:00 and a half-hour sponsorship
      # from 20:00 to 20:30 different lengths: the moment keys the row, the
      # flight says how long it runs.
      start[on] <- fs[on]
      end[on]   <- fe[on]
    } else {
      start[on] <- pmax(start[on], fs[on])
      end[on]   <- pmin(end[on],   fe[on])
    }
  }
  data.frame(start = start, end = end)
}

# How many calendar days each row is in market, from .span_of(). This is the
# weight an even flight spreads its spend by, so anything that wants to spread
# money "the way an even flight would" uses it too.
.row_days <- function(d, time_col, basis) {
  span <- .span_of(d, time_col, basis)
  as.integer(.to_date(span$end) - .to_date(span$start)) + 1L
}

#' The plan's flight window
#'
#' The first and last dates on which the plan has any line item in market — the
#' plan's own **extent**, derived from `@data`. How far a row reaches is read
#' from `@time_basis`: a weekly row runs from its week start through the
#' following six days, so a plan whose last week begins `2026-04-06` is in
#' market through `2026-04-12`, while a daily row covers its day and a monthly
#' one its month. On a plan keyed by moments the window comes back in `POSIXct`
#' and runs from the first moment planned to the end of the last buy: a row's
#' length is its flight's, so a spot at 20:00 with no flight is an instant and
#' a sponsorship flighted 20:00 to 20:30 is half an hour.
#'
#' This is a property of the plan alone: it changes only when the plan changes.
#' It is emphatically **not** the `through` date of [check_coverage()], which is
#' the boundary of what a decomp has measured. That one belongs to a *pairing*
#' rather than to either artifact, and it moves every time the decomp refreshes.
#' The rule the package follows, and the reason one is a property while the
#' other is an argument: *if a value can change without the plan changing, it
#' does not belong on the plan.*
#'
#' `@flight_start` and `@flight_end` on a [MediaPlan] read from here.
#'
#' @param plan A [MediaPlan].
#' @return A vector of length 2, named `start` and `end`, in the time column's
#'   own type (`Date`, or `POSIXct` on a plan keyed by moments). Length 0 when
#'   the plan has no rows or no non-missing dates — never `NA`, so absence is
#'   tested with `length()`.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week    = as.Date(c("2026-03-02", "2026-04-06")),
#'              channel = c("TV", "TV"),
#'              planned_spend = c(30, 35)),
#'   grain = "channel", time = "week", name = "Q2 plan"
#' )
#'
#' flight_window(p)   # ends 2026-04-12: the last week runs a full seven days
#' p@flight_start
#' p@flight_days
#' @export
flight_window <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  # An empty window keeps the time column's type, so a caller that stores the
  # result never has to special-case the shape of nothing.
  none <- plan@data[[plan@time_col]][0]

  span <- .row_span(plan)
  if (is.null(span) || !nrow(span)) return(none)

  # A time column is only type-checked, so it may legitimately hold NA.
  # min()/max() on an all-NA vector would give Inf with a warning, so the
  # window is taken over the dates that are actually known.
  start <- span$start[!is.na(span$start)]
  end   <- span$end[!is.na(span$end)]
  if (!length(start) || !length(end)) return(none)

  stats::setNames(c(min(start), max(end)), c("start", "end"))
}

# The inclusive length of the flight window in days, or integer(0) when there is
# no window. Backs @flight_days.
.flight_days <- function(plan) {
  w <- flight_window(plan)
  if (!length(w)) return(integer(0))
  # Calendar days, whatever the window's type: subtracting two POSIXct values
  # gives whichever unit difftime picks, which is not a day count.
  as.integer(.to_date(w[["end"]]) - .to_date(w[["start"]])) + 1L
}
