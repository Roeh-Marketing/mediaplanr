# The time axis: @time_col is required, it joins @grain on its own, and
# @time_basis says how far a row reaches. Everything temporal is derived from
# those two, so this is where the derivation is pinned.

# ---- basis inference ----------------------------------------------------------

# A spot schedule: two 30-second spots and a half-hour sponsorship, authored
# the way a buyer states them -- one row per slot, with its own start and end.
spot_plan <- function() {
  media_plan_from_flights(
    data.frame(
      channel   = "TV",
      programme = c("Super Bowl", "Late Night", "Sunday Sponsorship"),
      flight_start = as.POSIXct(c("2026-02-08 20:00:00", "2026-02-08 23:30:00",
                                  "2026-02-15 20:00:00"), tz = "UTC"),
      flight_end   = as.POSIXct(c("2026-02-08 20:00:30", "2026-02-08 23:30:30",
                                  "2026-02-15 20:30:00"), tz = "UTC"),
      planned_spend = c(7e6, 45000, 250000),
      stringsAsFactors = FALSE
    ),
    grain = c("channel", "programme"), basis = "instant", name = "Spot schedule")
}

plan_on <- function(v, ...) {
  media_plan_from_df(
    data.frame(week = fix_week(), t = v, channel = "TV", planned_spend = seq_along(v)),
    grain = "channel", time = "t", ..., name = "t")
}

test_that("the basis is inferred from the column, weekly when ambiguous", {
  expect_identical(plan_on(as.Date(c("2026-04-06", "2026-04-13")))@time_basis,
                   "week")
  # a gap of several weeks is still weekly: same weekday, whole weeks apart
  expect_identical(plan_on(as.Date(c("2026-03-02", "2026-04-06")))@time_basis,
                   "week")
  expect_identical(plan_on(as.Date(c("2026-04-06", "2026-04-07")))@time_basis,
                   "day")
  expect_identical(plan_on(as.Date(c("2026-04-01", "2026-05-01")))@time_basis,
                   "month")
  expect_identical(
    plan_on(as.POSIXct(c("2026-04-06 20:30:00", "2026-04-06 21:00:00"),
                       tz = "UTC"))@time_basis,
    "instant")
  # one date says nothing, so the guess is the package's own default
  expect_identical(plan_on(as.Date("2026-04-08"))@time_basis, "week")
})

test_that("a declared basis wins over the guess", {
  p <- plan_on(as.Date(c("2026-04-01", "2026-05-01")), time_basis = "day")
  expect_identical(p@time_basis, "day")
  expect_identical(unname(flight_window(p)[["end"]]), as.Date("2026-05-01"))
})

test_that("the basis must match the column's type", {
  expect_error(plan_on(as.Date("2026-04-06"), time_basis = "instant"),
               "needs a POSIXct time column")
  expect_error(plan_on(as.POSIXct("2026-04-06 20:30:00", tz = "UTC"),
                       time_basis = "week"),
               "holds POSIXct moments")
  expect_error(plan_on(as.Date("2026-04-06"), time_basis = "fortnight"),
               "@time_basis must be one of")
})

# ---- how far a row reaches ----------------------------------------------------

test_that("a row's period is its basis, not always a week", {
  day   <- plan_on(as.Date(c("2026-04-06", "2026-04-07")))
  week  <- plan_on(as.Date(c("2026-04-06", "2026-04-13")))
  month <- plan_on(as.Date(c("2026-04-01", "2026-05-01")))
  spot  <- plan_on(as.POSIXct("2026-04-06 20:30:00", tz = "UTC"))

  expect_identical(day@flight_days,   2L)   # two days
  expect_identical(week@flight_days, 14L)   # two full weeks
  expect_identical(month@flight_days, 61L)  # April and May
  expect_identical(spot@flight_days,  1L)   # a moment is a point in time
})

test_that("a flight still clips the period it sits in", {
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-04-10"), planned_spend = 300),
    grain = "channel", name = "part week")
  # the row is the week of Apr 6, but the buy is only Wed-Fri
  expect_identical(unname(flight_window(p)),
                   as.Date(c("2026-04-08", "2026-04-10")))
})

# ---- the grain ----------------------------------------------------------------

test_that("the time column is appended to the grain and kept through a rollup", {
  p <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("A", "B"),
               planned_spend = c(1, 2)),
    grain = c("channel", "partner"), time = "week", name = "t")
  expect_identical(p@grain, c("channel", "partner", "week"))
  expect_identical(line_item_grain(p), c("channel", "partner"))
  expect_identical(roll_up(p, "channel")@grain, c("channel", "week"))
})

# ---- authoring from flights onto a chosen calendar ----------------------------

test_that("flights can be expanded onto days or months, not just weeks", {
  buy <- data.frame(channel = "OOH", flight_start = as.Date("2026-04-29"),
                    flight_end = as.Date("2026-05-02"), planned_spend = 400)

  d <- media_plan_from_flights(buy, grain = "channel", basis = "day",
                               name = "daily")
  expect_identical(d@time_basis, "day")
  expect_identical(d@grain, c("channel", "day"))
  expect_equal(nrow(d@data), 4L)
  expect_equal(d@data$planned_spend, rep(100, 4))

  m <- media_plan_from_flights(buy, grain = "channel", basis = "month",
                               name = "monthly")
  expect_identical(m@time_basis, "month")
  expect_identical(m@data$month, as.Date(c("2026-04-01", "2026-05-01")))
  expect_equal(m@data$planned_spend, c(200, 200))   # Apr 29-30, May 1-2
  expect_equal(sum(m@data$planned_spend), 400)
})

# ---- editing across bases -----------------------------------------------------

test_that("a shift has to land on the plan's own calendar", {
  wk <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-04-06", "2026-04-13")), channel = "TV",
               planned_spend = c(10, 20)),
    grain = "channel", time = "week", name = "w")
  expect_error(build_scenario(wk, list(shift = 3), name = "s"),
               "whole number of weeks")
  expect_identical(build_scenario(wk, list(shift = 7), name = "s")@data$week,
                   as.Date(c("2026-04-13", "2026-04-20")))

  dy <- media_plan_from_df(
    data.frame(day = as.Date(c("2026-04-06", "2026-04-07")), channel = "TV",
               planned_spend = c(10, 20)),
    grain = "channel", time = "day", name = "d")
  expect_identical(build_scenario(dy, list(shift = 3), name = "s")@data$day,
                   as.Date(c("2026-04-09", "2026-04-10")))

  mo <- media_plan_from_df(
    data.frame(month = as.Date(c("2026-04-01", "2026-05-01")), channel = "TV",
               planned_spend = c(10, 20)),
    grain = "channel", time = "month", name = "m")
  expect_error(build_scenario(mo, list(shift = 30), name = "s"),
               "off month starts")
})

test_that("a plan of moments shifts by days, carrying its flights with it", {
  p <- spot_plan()
  s <- build_scenario(p, list(target = list(programme = "Late Night"),
                              shift = 1), name = "s")
  i <- s@data$programme == "Late Night"
  expect_identical(s@data$time[i],
                   as.POSIXct("2026-02-09 23:30:00", tz = "UTC"))
  # the buy moved with it: same length, a day later
  expect_identical(s@data$flight_end[i],
                   as.POSIXct("2026-02-09 23:30:30", tz = "UTC"))
})

test_that("a timed buy keeps its length: the flight is the row's extent", {
  p <- spot_plan()
  sp <- .row_span(p)
  secs <- as.numeric(difftime(sp$end, sp$start, units = "secs"))
  expect_equal(secs, c(30, 30, 1800))       # two spots, one half-hour slot

  # and the plan's window runs to the end of the last buy, not its start
  expect_identical(unname(flight_window(p)[["end"]]),
                   as.POSIXct("2026-02-15 20:30:00", tz = "UTC"))

  # a moment with no flight is still a point in time
  bare <- media_plan_from_df(
    data.frame(airs = as.POSIXct("2026-04-06 20:30:00", tz = "UTC"),
               channel = "TV", planned_spend = 10),
    grain = "channel", time = "airs", name = "bare")
  s <- .row_span(bare)
  expect_identical(s$start, s$end)
})

test_that("timed buys can be authored as flights, one row per slot", {
  p <- spot_plan()
  expect_identical(p@time_basis, "instant")
  expect_identical(p@grain, c("channel", "programme", "time"))
  expect_identical(nrow(p@data), 3L)
  # the whole total sits on the moment the buy starts: nothing is spread
  expect_equal(sum(p@data$planned_spend), 7295000)
  expect_identical(unique(p@data$period_basis), "flight")

  # and flights() inverts it exactly
  fl <- flights(p)
  expect_identical(nrow(fl), 3L)
  expect_identical(fl$n_periods, rep(1L, 3))
  expect_equal(sum(fl$planned_spend), sum(p@data$planned_spend))
  expect_s3_class(fl$flight_end, "POSIXct")
})

test_that("a timed flight can be added, moved and re-slotted", {
  p <- spot_plan()
  s <- build_scenario(p, list(add = list(
    channel = "TV", programme = "Halftime",
    flight_start = "2026-02-08 20:45:00",
    flight_end   = "2026-02-08 20:45:30",
    planned_spend = 8e6)), name = "halftime")
  i <- s@data$programme == "Halftime"
  expect_identical(s@data$time[i],
                   as.POSIXct("2026-02-08 20:45:00", tz = "UTC"))
  expect_identical(nrow(flights(s)), 4L)

  r <- build_scenario(p, list(target = list(programme = "Late Night"),
                              restage = list(from = "2026-03-01 21:00:00",
                                             to   = "2026-03-01 21:00:30")),
                      name = "moved")
  j <- r@data$programme == "Late Night"
  expect_identical(r@data$time[j], as.POSIXct("2026-03-01 21:00:00", tz = "UTC"))
  expect_identical(r@data$flight_end[j],
                   as.POSIXct("2026-03-01 21:00:30", tz = "UTC"))
  expect_equal(sum(r@data$planned_spend), sum(p@data$planned_spend))
})

test_that("an op's clock is the plan's, not the session's", {
  # A bare string means that time on the plan's own clock. Parsed in the
  # session zone instead, a spot added at 20:45 to a UTC schedule would land
  # hours out for anyone west of Greenwich -- silently.
  withr::with_timezone("America/New_York", {
    s <- build_scenario(spot_plan(), list(add = list(
      channel = "TV", programme = "Halftime",
      flight_start = "2026-02-08 20:45:00",
      flight_end   = "2026-02-08 20:45:30",
      planned_spend = 8e6)), name = "halftime")
    expect_identical(s@data$time[s@data$programme == "Halftime"],
                     as.POSIXct("2026-02-08 20:45:00", tz = "UTC"))
  })
})

test_that("a new row can be added at its own moment", {
  p <- media_plan_from_df(
    data.frame(airs = as.POSIXct("2026-04-06 20:30:00", tz = "UTC"),
               channel = "TV", planned_spend = 10),
    grain = "channel", time = "airs", name = "spots")
  s <- build_scenario(p, list(add = list(channel = "Radio",
                                         airs = "2026-04-06 21:00:00",
                                         planned_spend = 5)), name = "s")
  expect_equal(nrow(s@data), 2L)
  expect_s3_class(s@data$airs, "POSIXct")
  expect_equal(sum(s@data$planned_spend), 15)
})

test_that("a window given as dates reaches the moments inside those days", {
  p <- media_plan_from_df(
    data.frame(airs = as.POSIXct(c("2026-04-06 20:30:00", "2026-04-08 21:00:00"),
                                 tz = "UTC"),
               channel = c("TV", "Radio"), planned_spend = c(10, 20)),
    grain = "channel", time = "airs", name = "spots")
  s <- build_scenario(p, list(during = list(from = "2026-04-06",
                                            to = "2026-04-06"),
                              scale = 2), name = "s")
  expect_equal(s@data$planned_spend, c(20, 20))
})

# ---- serialization ------------------------------------------------------------

test_that("moments survive a JSON round trip, and the basis travels with them", {
  p <- media_plan_from_df(
    data.frame(airs = as.POSIXct(c("2026-04-06 20:30:00", "2026-04-06 21:00:00"),
                                 tz = "UTC"),
               channel = c("TV", "Radio"), planned_spend = c(10, 20)),
    grain = "channel", time = "airs", name = "spots")
  q <- plan_from_json(plan_to_json(p))
  expect_identical(q@time_col, "airs")
  expect_identical(q@time_basis, "instant")
  expect_identical(q@data$airs, p@data$airs)
})

# ---- the plan's clock ----------------------------------------------------------

test_that("the plan carries its own timezone, and the column is put on it", {
  p <- spot_plan()                       # built from UTC moments, undeclared
  expect_identical(p@tz, "UTC")          # adopted from the data
  expect_identical(attr(p@data$time, "tzone"), "UTC")

  # declared wins, and the same wall clock on two clocks is two instants
  ny <- media_plan_from_df(
    data.frame(airs = "2026-02-08 20:00:00", channel = "TV", planned_spend = 1),
    grain = "channel", time = "airs", tz = "America/New_York", name = "ny")
  uk <- media_plan_from_df(
    data.frame(airs = "2026-02-08 20:00:00", channel = "TV", planned_spend = 1),
    grain = "channel", time = "airs", tz = "Europe/London", name = "uk")
  expect_identical(ny@tz, "America/New_York")
  expect_false(identical(as.numeric(ny@data$airs), as.numeric(uk@data$airs)))
  expect_equal(as.numeric(ny@data$airs) - as.numeric(uk@data$airs), 5 * 3600)
})

test_that("a zone the platform does not know is refused", {
  expect_error(
    media_plan_from_df(
      data.frame(airs = as.POSIXct("2026-02-08 20:00:00", tz = "UTC"),
                 channel = "TV", planned_spend = 1),
      grain = "channel", time = "airs", tz = "Mars/Olympus", name = "bad"),
    "not a timezone this platform knows")

  # and the class refuses a column that disagrees with the plan's own clock
  expect_error(
    MediaPlan(data = data.frame(
                airs = as.POSIXct("2026-02-08 20:00:00", tz = "Europe/London"),
                channel = "TV", planned_spend = 1),
              grain = c("channel", "airs"), time_col = "airs",
              time_basis = "instant", tz = "America/New_York", name = "drift"),
    "but @tz is")
})

test_that("an edit is read on the plan's clock, not the machine's", {
  p <- media_plan_from_df(
    data.frame(airs = "2026-02-08 20:00:00", channel = "TV", planned_spend = 1),
    grain = "channel", time = "airs", tz = "America/New_York", name = "ny")
  add <- list(add = list(channel = "Radio", airs = "2026-02-08 21:30:00",
                         planned_spend = 2))
  here  <- build_scenario(p, add, name = "here")@data$airs
  there <- withr::with_timezone("Asia/Tokyo",
                                build_scenario(p, add, name = "there")@data$airs)
  expect_identical(as.numeric(here), as.numeric(there))
  expect_identical(format(here[2], "%H:%M", tz = "America/New_York"), "21:30")
})

test_that("a plan keeps its clock across a JSON round trip", {
  p <- media_plan_from_flights(
    data.frame(channel = "TV", programme = "Grand Final",
               flight_start = "2026-02-08 20:00:00",
               flight_end   = "2026-02-08 20:00:30",
               planned_spend = 7e6, stringsAsFactors = FALSE),
    grain = c("channel", "programme"), basis = "instant",
    tz = "America/New_York", name = "ny spots")
  js <- plan_to_json(p, pretty = FALSE)
  # written as the instant, in UTC, so it cannot be read as another moment
  expect_match(js, '"time":"2026-02-09T01:00:00Z"', fixed = TRUE)
  expect_match(js, '"tz":"America/New_York"', fixed = TRUE)

  q <- plan_from_json(js)
  expect_identical(q@tz, p@tz)
  expect_identical(q@data$time, p@data$time)
  expect_identical(q@data$flight_end, p@data$flight_end)
})

test_that("a dated plan may carry a zone, and keeps its Date column", {
  p <- media_plan_from_df(
    data.frame(week = as.Date("2026-07-06"), channel = "TV", planned_spend = 1),
    grain = "channel", time = "week", tz = "Europe/London", name = "weekly")
  expect_identical(p@tz, "Europe/London")
  expect_s3_class(p@data$week, "Date")
})
