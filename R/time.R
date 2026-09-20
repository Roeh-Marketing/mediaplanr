# The plan's time axis: what a row's time value means, and how long it covers.
#
# Two facts, and everything temporal follows from them. @time_col names the
# column; @time_basis says what one value of it stands for. Together they answer
# the only question the rest of the package asks of time -- what dates is this
# row in market? -- and that answer is derived in ONE place (.span_of) from
# those two plus the flight a row belongs to. Nothing stores a period.
#
# The basis is what the package used to assume. A time column was called the
# week column and a row was silently seven days long, which is wrong for a daily
# plan and meaningless for a timestamp, so the assumption is now a declared
# property, inferred from the data when the caller does not say.

#' What one value of a plan's time column stands for
#'
#' A plan's `@time_basis`. `"day"`, `"week"` and `"month"` are `Date` columns
#' holding the first day of the period, so a row covers that day, that week, or
#' that calendar month. `"instant"` is a `POSIXct` column holding the exact
#' moment a buy runs — a dated spot, an 8pm takeover, a half-hour sponsorship.
#'
#' A timed row is keyed by the moment it starts, and its **length is its
#' flight's**: a 30-second spot flighted `20:00:00` to `20:00:30` covers half a
#' minute, a sponsorship flighted `20:00` to `20:30` covers half an hour, and a
#' moment with no flight is a point in time. That is the same rule as every
#' other basis — the row's period, resolved against the buy it belongs to —
#' with the difference that a timed buy occupies exactly one row, so there is
#' nothing to spread across.
#'
#' The basis is tied to the column's type: a `Date` column is `"day"`,
#' `"week"` or `"month"`, and a `POSIXct` column is always `"instant"`.
#'
#' @return A character vector of the valid, canonical values.
#' @examples
#' time_basis_levels()
#' @seealso [media_plan_from_df()], [period_basis_levels()] for the *flight*
#'   cadence, which is a different thing: what kind of buy a flight is, rather
#'   than what one plan row covers.
#' @export
time_basis_levels <- function() {
  c("day", "week", "month", "instant")
}

# "date" or "datetime" -- which of the two kinds of time column this is.
# NA_character_ for anything that is neither, which the validator reports.
.time_type <- function(x) {
  if (inherits(x, "POSIXct")) return("datetime")
  if (inherits(x, "Date"))    return("date")
  NA_character_
}

# The bases a column type admits. A moment cannot be a week; a Date cannot be a
# moment.
.bases_for_type <- function(type) {
  if (identical(type, "datetime")) "instant" else c("day", "week", "month")
}

# The wall-clock date a time value falls on. as.Date() on a POSIXct converts in
# UTC by default, which moves an evening spot to the next day, so the date is
# read off the formatted value instead.
.to_date <- function(x) {
  if (inherits(x, "Date")) return(.as_date(x))
  .as_date(as.Date(format(x, "%Y-%m-%d")))
}

# Add whole months to a month start.
.add_months <- function(d, n) {
  lt <- as.POSIXlt(.to_date(d))
  lt$mon <- lt$mon + n
  lt$mday <- 1L
  .as_date(as.Date(lt))
}

# The last moment of the period a time value opens, in the value's own type.
#
# THE definition of how long a row is, before the row's flight is taken into
# account. An instant ends where it begins -- a bare moment is a point in time
# -- and .span_of() gives a timed row its buy's own interval when it has one.
.period_end <- function(start, basis) {
  switch(basis,
    instant = start,
    day     = .as_date(start),
    week    = .as_date(start + 6L),
    month   = .as_date(.add_months(start, 1L) - 1L),
    stop("unknown time basis '", basis, "'.", call. = FALSE))
}

# The basis a time column looks like, for a caller who did not declare one.
#
# Deliberately conservative, and deliberately weekly in the ambiguous cases:
# weeks are what the package was built on, so an undeclared plan keeps the
# spans it has always had. Declare @time_basis when the guess is wrong -- a
# single month of a monthly plan cannot be told from a single week.
.infer_time_basis <- function(x) {
  if (identical(.time_type(x), "datetime")) return("instant")
  v <- sort(unique(x[!is.na(x)]))
  if (!length(v)) return("week")

  if (length(v) > 1L && all(as.integer(format(v, "%d")) == 1L)) return("month")

  dow  <- unique(as.integer(format(v, "%u")))
  gaps <- if (length(v) > 1L) as.integer(diff(v)) else integer(0)
  if (length(dow) == 1L && (!length(gaps) || all(gaps %% 7L == 0L))) return("week")

  "day"
}

# Coerce a user-supplied time column. Date and POSIXct pass through untouched --
# a planner's timezone is their own -- and strings are read as moments when they
# carry a clock and as dates when they do not.
.as_time_col <- function(x, what, tz = "") {
  if (inherits(x, "POSIXct") || inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXlt")) return(as.POSIXct(x))

  chr <- as.character(x)
  known <- chr[!is.na(chr)]
  timed <- length(known) > 0 && all(grepl("\\d{1,2}:\\d{2}", known))

  # ISO-8601 with a T separator, and a trailing Z for UTC, is what a JSON file
  # or an API hands over; base R's parser wants a space and a timezone argument.
  # A trailing Z states the zone, so it wins; otherwise the string is read on
  # the plan's clock, and only falls back to the session's when there is none.
  utc  <- timed && all(grepl("Z$", known))
  norm <- sub("Z$", "", sub("T", " ", chr))
  ztz  <- if (utc) "UTC" else if (length(tz) && !is.na(tz)) tz else ""

  # as.Date() *errors* on unparseable strings rather than returning NA.
  conv <- suppressWarnings(tryCatch(
    if (timed) as.POSIXct(norm, tz = ztz) else as.Date(norm),
    error = function(e) rep(NA, length(chr))))

  if (length(known) && anyNA(conv[!is.na(chr)])) {
    stop("time column '", what, "' could not be read as a date or a moment. ",
         "Supply Date or POSIXct values, or ISO-8601 strings such as ",
         "\"2026-04-06\" or \"2026-04-06 20:30:00\".", call. = FALSE)
  }
  conv
}

# The single time column a data frame offers, when the caller did not name one.
# Flight dates are excluded: they say when a buy runs, not what a row is keyed
# by. Exactly one candidate or this errors -- guessing between two date columns
# is how a plan ends up keyed by the wrong one.
.infer_time_col <- function(df) {
  cand <- setdiff(names(df)[vapply(df, function(v) !is.na(.time_type(v)),
                                   logical(1))],
                  flight_cols())
  if (length(cand) == 1L) return(cand)
  if (!length(cand)) {
    stop("every plan needs a time column, and `df` has no Date or POSIXct ",
         "column to use as one. Add the week, day, month or moment each row ",
         "is planned for, or build the plan from flights with ",
         "media_plan_from_flights().", call. = FALSE)
  }
  stop("`time` must name the plan's time column: `df` has ", length(cand),
       " date columns to choose from (", paste(cand, collapse = ", "), ").",
       call. = FALSE)
}

# How a basis reads in prose, for print() and the structure views.
.basis_word <- function(basis) {
  switch(basis, day = "daily", week = "weekly", month = "monthly",
         instant = "timed", basis)
}

# Put a boundary value in the same type as a plan's time column, so the two can
# be compared. A date compared against moments means the start of that day; a
# moment compared against dates is the day it falls on.
.align_time <- function(x, like) {
  want <- .time_type(like)
  got  <- .time_type(x)
  if (is.na(want) || is.na(got) || identical(want, got)) return(x)
  if (identical(want, "datetime")) {
    tz <- attr(like, "tzone")
    if (is.null(tz)) tz <- ""
    return(as.POSIXct(paste0(format(.to_date(x)), " 00:00:00"), tz = tz))
  }
  .to_date(x)
}

# A date used as an inclusive END boundary. Against a plan of moments it means
# the last moment of that day, not its midnight -- "through Apr 6" includes the
# 8pm spot on Apr 6.
.align_time_end <- function(x, like) {
  if (!identical(.time_type(like), "datetime") ||
      identical(.time_type(x), "datetime")) {
    return(.align_time(x, like))
  }
  tz <- attr(like, "tzone")
  if (is.null(tz)) tz <- ""
  as.POSIXct(paste0(format(.to_date(x)), " 23:59:59"), tz = tz)
}

# Move time values by a whole number of days, in the column's own type.
.shift_time <- function(x, days) {
  if (inherits(x, "POSIXct")) return(x + days * 86400)
  .as_date(x + days)
}

# ifelse() and other vector plumbing drop a time column's class, so values that
# have been through them come back to their own type here -- which of the two it
# is taken from a column that kept it.
.as_time_like <- function(x, like) {
  if (inherits(like, "POSIXct")) {
    tz <- attr(like, "tzone")
    return(structure(as.numeric(x), class = c("POSIXct", "POSIXt"),
                     tzone = if (is.null(tz)) "" else tz))
  }
  .as_date(x)
}

# A timezone name the platform knows, or "" for "unstated -- the session's".
#
# "" is not the same as a declared zone: it means nobody has said, so the
# machine running the code decides. That is exactly the ambiguity @tz exists to
# remove, which is why it is allowed but reported in print().
.valid_tz <- function(tz) {
  if (!length(tz) || is.na(tz) || !nzchar(tz)) return(TRUE)
  known <- OlsonNames()
  !length(known) || tz %in% known
}

# The zone a time value is displayed in. tzone is a display attribute -- the
# instant is unchanged -- so stamping the plan's zone onto a column re-reads the
# same moments on the plan's clock.
#
# An unstated zone stamps nothing: "" means nobody has said, which is not the
# same as saying "the session's", and clearing a zone the data already carries
# would throw away the one statement anybody made.
.stamp_tz <- function(x, tz) {
  if (!inherits(x, "POSIXct") || !length(tz) || is.na(tz) || !nzchar(tz)) {
    return(x)
  }
  attr(x, "tzone") <- tz
  x
}

# The zone a column is already carrying, "" when it carries none.
.tz_of <- function(x) {
  tz <- attr(x, "tzone")
  if (is.null(tz) || is.na(tz[1])) "" else tz[1]
}
