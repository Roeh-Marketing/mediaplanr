test_that("line_item builds composite identifiers", {
  d <- data.frame(channel = c("TV", "TV"), partner = c("NBC", "ESPN"))
  expect_equal(line_item(d, "channel"), c("TV", "TV"))
  expect_equal(line_item(d, c("channel", "partner")), c("TV | NBC", "TV | ESPN"))
  expect_error(line_item(d, "missing"), "not found")
})

test_that("media_plan_from_df builds a valid plan and keeps @data plain", {
  p <- std_plan()
  expect_true(S7::S7_inherits(p, MediaPlan))
  expect_identical(p@grain, "channel")
  expect_s3_class(p@data, "data.frame")
  expect_true(all(c("channel", "planned_spend") %in% names(p@data)))
  expect_equal(sum(p@data$planned_spend), 160)
  expect_true(nzchar(p@id))
})

test_that("the planned_spend column is renamed to the canonical name", {
  df <- data.frame(channel = "TV", budget = 100)
  p <- media_plan_from_df(df, grain = "channel", planned_spend = "budget")
  expect_true("planned_spend" %in% names(p@data))
  expect_false("budget" %in% names(p@data))
  expect_equal(p@data$planned_spend, 100)
})

test_that("other columns ride along on @data untouched", {
  df <- data.frame(channel = "TV", planned_spend = 100,
                   flight = "Q3", note = "brand", stringsAsFactors = FALSE)
  p <- media_plan_from_df(df, grain = "channel")
  expect_true(all(c("flight", "note") %in% names(p@data)))
  expect_equal(p@data$flight, "Q3")
})

test_that("structural problems are hard errors", {
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", planned_spend = -1), grain = "channel"),
    "non-negative")
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", planned_spend = NA_real_),
                       grain = "channel"),
    "NA")
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", x = 1), grain = "channel"),
    "planned-spend column")
  expect_error(
    media_plan_from_df(data.frame(channel = c("TV", "TV"), planned_spend = c(1, 2)),
                       grain = "channel"),
    "duplicate rows")
})

# ---- week column ------------------------------------------------------------

test_that("a week column is recorded and coerced to Date", {
  p <- weekly_plan()
  expect_identical(p@week_col, "week")
  expect_s3_class(p@data$week, "Date")
  # character ISO dates are accepted and coerced
  df <- data.frame(channel = "TV", week = "2026-03-02", planned_spend = 10,
                   stringsAsFactors = FALSE)
  p2 <- media_plan_from_df(df, grain = c("channel", "week"), week = "week")
  expect_s3_class(p2@data$week, "Date")
})

test_that("the week column must be part of the grain and parseable", {
  df <- data.frame(channel = "TV", week = as.Date("2026-03-02"), planned_spend = 10)
  expect_error(
    media_plan_from_df(df, grain = "channel", week = "week"),
    "must name a single column that is part of `grain`")
  bad <- data.frame(channel = "TV", week = "not-a-date", planned_spend = 10,
                    stringsAsFactors = FALSE)
  expect_error(
    media_plan_from_df(bad, grain = c("channel", "week"), week = "week"),
    "could not be coerced to Date")
})

test_that("line_item_grain drops the week", {
  p <- weekly_plan()
  expect_identical(line_item_grain(p), c("channel", "partner"))
  expect_identical(line_item_grain(std_plan()), "channel")
})

# ---- roll_up ----------------------------------------------------------------

test_that("roll_up aggregates planned_spend to a coarser grain", {
  p <- fine_plan()  # TV: 50 + 30, Search: 40, Social: 40
  r <- roll_up(p, "channel")
  expect_identical(r@grain, "channel")
  expect_equal(nrow(r@data), 3L)
  x <- stats::setNames(r@data$planned_spend, r@data$channel)
  expect_equal(unname(x[["TV"]]), 80)
  expect_equal(sum(r@data$planned_spend), sum(p@data$planned_spend))
})

test_that("roll_up records lineage and drops a dropped week column", {
  p <- weekly_plan()
  r <- roll_up(p, c("channel", "partner"))
  expect_identical(r@parent_id, p@id)
  expect_identical(r@week_col, character(0))
  expect_equal(sum(r@data$planned_spend), sum(p@data$planned_spend))
})

test_that("roll_up keeps the week column when it is retained", {
  p <- weekly_plan()
  r <- roll_up(p, c("channel", "week"))
  expect_identical(r@week_col, "week")
})

test_that("roll_up rejects a grain outside the plan's", {
  expect_error(roll_up(std_plan(), "partner"), "must be a subset")
  expect_error(roll_up(std_plan(), character(0)), "at least one column")
})

test_that("line_item supports composite lookup against @data", {
  p <- fine_plan()
  d <- p@data
  expect_equal(d[line_item(d, p@grain) %in% "TV | B", ]$planned_spend, 30)
})
