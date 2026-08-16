# The flight window is the plan's own extent, derived from @data. The contract
# worth pinning: a week is seven days long, absence is length-0 rather than NA,
# and the derived properties cannot be assigned into.

test_that("the window runs from the first week start to the last week's last day", {
  w <- flight_window(weekly_plan())
  expect_s3_class(w, "Date")
  expect_identical(names(w), c("start", "end"))
  expect_identical(unname(w[["start"]]), as.Date("2026-03-02"))
  # the plan's last week begins 2026-04-06 and runs a full seven days
  expect_identical(unname(w[["end"]]), as.Date("2026-04-12"))
})

test_that("the derived properties read from the window", {
  p <- weekly_plan()
  expect_identical(p@flight_start, as.Date("2026-03-02"))
  expect_identical(p@flight_end, as.Date("2026-04-12"))
  # inclusive: 2026-03-02 through 2026-04-12
  expect_identical(p@flight_days, 42L)
})

test_that("the derived properties are unnamed scalars", {
  p <- weekly_plan()
  expect_null(names(p@flight_start))
  expect_null(names(p@flight_end))
})

test_that("a plan with no time dimension has no window, and does not error", {
  p <- std_plan()
  expect_identical(flight_window(p), as.Date(character(0)))
  expect_length(p@flight_start, 0)
  expect_length(p@flight_end, 0)
  expect_length(p@flight_days, 0)
})

test_that("a plan with no rows has no window", {
  p <- MediaPlan(
    data = data.frame(channel = character(0), week = as.Date(character(0)),
                      planned_spend = numeric(0)),
    grain = c("channel", "week"), week_col = "week", name = "Empty")
  expect_length(flight_window(p), 0)
})

test_that("missing week values are skipped rather than poisoning the window", {
  # the week column is only type-checked as a Date, so NA can legitimately occur
  p <- media_plan_from_df(
    data.frame(week = as.Date(c(NA, "2026-04-06")),
               channel = c("TV", "Search"), planned_spend = c(1, 2)),
    grain = c("channel", "week"), week = "week", name = "Partly dated")
  expect_identical(p@flight_start, as.Date("2026-04-06"))
  expect_identical(p@flight_end, as.Date("2026-04-12"))
})

test_that("the derived properties cannot be assigned", {
  p <- weekly_plan()
  expect_error(p@flight_start <- as.Date("2020-01-01"), "read-only")
  expect_error(p@flight_days <- 1L, "read-only")
})

test_that("the window follows the data through a derivation", {
  # scenarios inherit the row set, so the window is unchanged; a rollup that
  # drops the week genuinely has no time dimension any more.
  p <- weekly_plan()
  s <- build_scenario(p, edits = list(scale = 2), name = "double")
  expect_identical(s@flight_end, p@flight_end)
  expect_length(roll_up(p, "channel")@flight_end, 0)
})

test_that("flight_window() rejects anything that is not a plan", {
  expect_error(flight_window(weekly_df()), "must be a MediaPlan")
})
