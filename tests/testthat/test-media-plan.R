test_that("grain_key builds composite keys", {
  d <- data.frame(channel = c("TV", "TV"), partner = c("A", "B"))
  expect_equal(grain_key(d, "channel"), c("TV", "TV"))
  expect_equal(grain_key(d, c("channel", "partner")), c("TV | A", "TV | B"))
  expect_error(grain_key(d, "missing"), "not found")
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

test_that("the spend column is renamed to canonical planned_spend", {
  df <- data.frame(channel = "TV", spend = 100)
  p <- media_plan_from_df(df, grain = "channel", planned_spend = "spend")
  expect_true("planned_spend" %in% names(p@data))
  expect_false("spend" %in% names(p@data))
  expect_equal(p@data$planned_spend, 100)
})

test_that("other columns ride along on @data untouched", {
  df <- data.frame(channel = "TV", planned_spend = 100,
                   flight = "Q3", note = "brand", stringsAsFactors = FALSE)
  p <- media_plan_from_df(df, grain = "channel")
  expect_true(all(c("flight", "note") %in% names(p@data)))
  expect_equal(p@data$flight, "Q3")
})

test_that("validator rejects invalid plans", {
  # negative spend
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", planned_spend = -1),
                       grain = "channel"),
    "non-negative")
  # NA spend
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", planned_spend = NA_real_),
                       grain = "channel"),
    "NA")
  # missing planned_spend column
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", x = 1), grain = "channel"),
    "planned-spend column")
  # duplicate grain cells
  expect_error(
    media_plan_from_df(
      data.frame(channel = c("TV", "TV"), planned_spend = c(1, 2)),
      grain = "channel"),
    "duplicate grain cells")
})

test_that("valid_keys enforces coverage against a known key set", {
  df <- data.frame(channel = c("TV", "Radio"), planned_spend = c(1, 2))
  expect_error(
    media_plan_from_df(df, grain = "channel", valid_keys = c("TV", "Search")),
    "not present in `valid_keys`")
  # data-frame form of valid_keys is accepted
  decomp <- data.frame(channel = c("TV", "Radio", "Search"))
  expect_silent(media_plan_from_df(df, grain = "channel", valid_keys = decomp))
})

test_that("grain_key supports composite-key lookup against @data", {
  p <- media_plan_from_df(
    data.frame(channel = c("TV", "TV", "Search"),
               partner = c("A", "B", "X"),
               planned_spend = c(1, 2, 3)),
    grain = c("channel", "partner"))
  d <- p@data
  expect_equal(d[grain_key(d, p@grain) %in% "TV | B", ]$planned_spend, 2)
})
