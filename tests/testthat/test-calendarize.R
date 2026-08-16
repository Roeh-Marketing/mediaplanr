# calendarize() is the temporal counterpart to roll_up(). The contract worth
# pinning: spend follows the days a row is actually in market, totals survive
# every re-cut, and it returns a projection rather than pretending to be a plan.

straddler <- function() {
  # Mon 20 Apr to Sun 10 May: 21 days, 10,000 a day, crossing a month end
  media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-20"),
               flight_end = as.Date("2026-05-10"), planned_spend = 210000),
    grain = "channel", name = "straddles")
}

test_that("the total survives every basis", {
  p <- straddler()
  for (b in c("day", "week", "month")) {
    expect_equal(sum(calendarize(p, b)$planned_spend), 210000)
  }
})

test_that("a month cut splits the week that crosses the month end", {
  r <- calendarize(straddler(), "month")
  expect_identical(r$month, as.Date(c("2026-04-01", "2026-05-01")))
  # April holds 20-30 (11 days), May holds 1-10 (10 days)
  expect_equal(r$planned_spend, c(110000, 100000))
})

test_that("a day cut gives one row per day in market", {
  r <- calendarize(straddler(), "day")
  expect_identical(nrow(r), 21L)
  expect_identical(r$day[1], as.Date("2026-04-20"))
  expect_identical(r$day[21], as.Date("2026-05-10"))
  expect_equal(unique(r$planned_spend), 10000)
})

test_that("the date column is named after the basis", {
  expect_true("month" %in% names(calendarize(straddler(), "month")))
  expect_true("day" %in% names(calendarize(straddler(), "day")))
  expect_true("week" %in% names(calendarize(straddler(), "week")))
})

test_that("a weekly plan re-cut to weeks is unchanged", {
  p <- weekly_plan()
  r <- calendarize(p, "week")
  expect_equal(sum(r$planned_spend), sum(p@data$planned_spend))
  expect_identical(nrow(r), nrow(p@data))
})

test_that("rows of one line item landing in the same period are summed", {
  # two consecutive weeks of one line item fall in the same month
  p <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-04-06", "2026-04-13")),
               channel = "TV", planned_spend = c(10, 20)),
    grain = c("channel", "week"), week = "week", name = "two weeks")
  r <- calendarize(p, "month")
  expect_identical(nrow(r), 1L)
  expect_equal(r$planned_spend, 30)
})

test_that("a ragged flight contributes only its real days", {
  # a one-day buy sits in a week but is only one day of it
  p <- media_plan_from_flights(
    data.frame(channel = "Search", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-04-08"), planned_spend = 3100),
    grain = "channel", name = "one day")
  r <- calendarize(p, "day")
  expect_identical(nrow(r), 1L)
  expect_identical(r$day, as.Date("2026-04-08"))
  expect_equal(r$planned_spend, 3100)
})

test_that("week_start follows the plan, and can be overridden", {
  p <- media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-04-14"), planned_spend = 700),
    grain = "channel", name = "sunday", week_start = "Sunday")
  expect_identical(calendarize(p, "week")$week,
                   as.Date(c("2026-04-05", "2026-04-12")))
  expect_identical(calendarize(p, "week", week_start = "Monday")$week,
                   as.Date(c("2026-04-06", "2026-04-13")))
})

test_that("every period is a whole number of cents", {
  r <- calendarize(
    media_plan_from_flights(
      data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
                 flight_end = as.Date("2026-05-03"), planned_spend = 33333),
      grain = "channel", name = "odd"), "month")
  # a month sums several weekly allocations, so compare in cents with
  # tolerance rather than bit-for-bit -- see the allocation note in flighting.R
  expect_equal(r$planned_spend * 100, round(r$planned_spend * 100))
  expect_equal(sum(r$planned_spend), 33333)
})

test_that("it composes with roll_up in either order", {
  p <- media_plan_from_flights(
    data.frame(channel = c("TV", "TV"), partner = c("NBC", "ESPN"),
               flight_start = as.Date(c("2026-04-06", "2026-04-06")),
               flight_end   = as.Date(c("2026-05-03", "2026-05-03")),
               planned_spend = c(120000, 60000)),
    grain = c("channel", "partner"), name = "two partners")
  a <- calendarize(roll_up(p, c("channel", "week")), "month")
  b <- calendarize(p, "month")
  expect_equal(sum(a$planned_spend), sum(b$planned_spend))
  # the flight runs 6 Apr to 3 May, so it lands in two months either way;
  # rolling to channel first collapses the two partners into one row each
  expect_identical(nrow(a), 2L)
  expect_identical(nrow(b), 4L)
  expect_equal(tapply(b$planned_spend, b$month, sum),
               tapply(a$planned_spend, a$month, sum))
})

test_that("the result is an ordinary data frame, and can become a plan", {
  r <- calendarize(straddler(), "month")
  expect_s3_class(r, "data.frame")
  expect_false(any(flight_cols() %in% names(r)))
  p2 <- media_plan_from_df(r, grain = c("channel", "month"), week = "month",
                           name = "monthly")
  expect_equal(sum(p2@data$planned_spend), 210000)
})

test_that("a plan with no time dimension cannot be calendarized", {
  expect_error(calendarize(std_plan()), "no time dimension")
})

test_that("rows with no dates are refused rather than dropped", {
  p <- media_plan_from_df(
    data.frame(week = as.Date(c(NA, "2026-04-06")), channel = c("TV", "Search"),
               planned_spend = c(10, 20)),
    grain = c("channel", "week"), week = "week", name = "partly dated")
  expect_error(calendarize(p), "cannot be placed on a calendar")
})

test_that("calendarize rejects anything that is not a plan", {
  expect_error(calendarize(weekly_df()), "must be a MediaPlan")
})
