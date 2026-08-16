# The plan's own dates. Everything here is derived from @data, so none of it can
# go stale: a value that could change without the plan changing does not belong
# on a plan (see vignette("plan_concepts")).

# The dates each row is in market.
#
# THE ONE PLACE that answers "what dates does this row cover?". Today a row is a
# week, so its span runs from the week start through the following six days.
# When rows come to carry an explicit flight, only this function changes --
# flight_window(), line_item_summary() and print() are already written in span
# terms and do not move.
#
# Returns a data frame of Date columns `start` and `end`, positionally aligned
# with plan@data, or NULL when the plan has no time dimension. NULL rather than
# a zero-row frame, because callers rely on the alignment and so must handle the
# timeless case explicitly rather than by accident.
.row_span <- function(plan) {
  if (!length(plan@week_col)) return(NULL)
  start <- plan@data[[plan@week_col]]
  data.frame(start = start, end = start + 6L)
}

#' The plan's flight window
#'
#' The first and last dates on which the plan has any line item in market — the
#' plan's own **extent**, derived from `@data`. A weekly row runs from its week
#' start through the following six days, so a plan whose last week begins
#' `2026-04-06` is in market through `2026-04-12`.
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
#' @return A `Date` vector of length 2, named `start` and `end`. Length 0 when
#'   the plan has no time dimension, no rows, or no non-missing dates — never
#'   `NA`, so absence is tested with `length()`, exactly as for `@week_col`.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week    = as.Date(c("2026-03-02", "2026-04-06")),
#'              channel = c("TV", "TV"),
#'              planned_spend = c(30, 35)),
#'   grain = c("channel", "week"), week = "week", name = "Q2 plan"
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
  none <- as.Date(character(0))

  span <- .row_span(plan)
  if (is.null(span) || !nrow(span)) return(none)

  # A week column is only type-checked as a Date, so it may legitimately hold
  # NA. min()/max() on an all-NA vector would give Inf with a warning, so the
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
  as.integer(w[["end"]] - w[["start"]]) + 1L
}
