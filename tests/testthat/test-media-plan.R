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
  p <- media_plan_from_df(df, grain = "channel", planned_spend = "budget", name = "t")
  expect_true("planned_spend" %in% names(p@data))
  expect_false("budget" %in% names(p@data))
  expect_equal(p@data$planned_spend, 100)
})

test_that("other columns ride along on @data untouched", {
  df <- data.frame(channel = "TV", planned_spend = 100,
                   flight = "Q3", note = "brand", stringsAsFactors = FALSE)
  p <- media_plan_from_df(df, grain = "channel", name = "t")
  expect_true(all(c("flight", "note") %in% names(p@data)))
  expect_equal(p@data$flight, "Q3")
})

test_that("structural problems are hard errors", {
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", planned_spend = -1), grain = "channel", name = "t"),
    "non-negative")
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", planned_spend = NA_real_),
                       grain = "channel", name = "t"),
    "NA")
  expect_error(
    media_plan_from_df(data.frame(channel = "TV", x = 1), grain = "channel", name = "t"),
    "planned-spend column")
  expect_error(
    media_plan_from_df(data.frame(channel = c("TV", "TV"), planned_spend = c(1, 2)),
                       grain = "channel", name = "t"),
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
  p2 <- media_plan_from_df(df, grain = c("channel", "week"), week = "week", name = "t")
  expect_s3_class(p2@data$week, "Date")
})

test_that("the week column must be part of the grain and parseable", {
  df <- data.frame(channel = "TV", week = as.Date("2026-03-02"), planned_spend = 10)
  expect_error(
    media_plan_from_df(df, grain = "channel", week = "week", name = "t"),
    "must name a single column that is part of `grain`")
  bad <- data.frame(channel = "TV", week = "not-a-date", planned_spend = 10,
                    stringsAsFactors = FALSE)
  expect_error(
    media_plan_from_df(bad, grain = c("channel", "week"), week = "week", name = "t"),
    "could not be coerced to Date")
})

test_that("line_item_grain drops the week", {
  p <- weekly_plan()
  expect_identical(line_item_grain(p), c("channel", "partner"))
  expect_identical(line_item_grain(std_plan()), "channel")
})

# ---- check_coverage (the plan-decomp pairing) -------------------------------

test_that("missing decomp line items warn and are returned", {
  p <- weekly_plan()
  decomp <- data.frame(channel = c("TV", "TV", "Search"),
                       partner = c("NBC", "ESPN", "Google"),
                       stringsAsFactors = FALSE)
  expect_warning(
    missing <- check_coverage(p, decomp, through = as.Date("2026-03-15")),
    "missing 1 line item\\(s\\).*TV \\| ESPN")
  expect_equal(missing, "TV | ESPN")
})

test_that("complete coverage is silent and returns nothing missing", {
  p <- weekly_plan()
  decomp <- data.frame(channel = c("TV", "Search"),
                       partner = c("NBC", "Google"), stringsAsFactors = FALSE)
  expect_no_warning(
    missing <- check_coverage(p, decomp, through = as.Date("2026-03-15")))
  expect_equal(missing, character(0))
})

test_that("new line items in the future are never flagged", {
  # TV|Hulu exists only after the through-date; it must not be reported
  p <- weekly_plan()
  decomp <- data.frame(channel = c("TV", "Search"),
                       partner = c("NBC", "Google"), stringsAsFactors = FALSE)
  missing <- expect_no_warning(
    check_coverage(p, decomp, through = as.Date("2026-03-15")))
  expect_false("TV | Hulu" %in% missing)
})

test_that("through= scopes the check to rows before it", {
  # TV|Hulu is only in the future, so requiring it warns
  p <- weekly_plan()
  expect_warning(
    check_coverage(p, data.frame(channel = "TV", partner = "Hulu",
                                 stringsAsFactors = FALSE),
                   through = as.Date("2026-03-15")),
    "TV \\| Hulu")
  # without through=, the whole plan counts and it is covered
  expect_no_warning(
    check_coverage(p, data.frame(channel = "TV", partner = "Hulu",
                                 stringsAsFactors = FALSE)))
})

test_that("decomp may name a subset of the line item grain", {
  p <- weekly_plan()
  expect_warning(
    check_coverage(p, data.frame(channel = c("TV", "Search", "Audio"),
                                 stringsAsFactors = FALSE),
                   through = as.Date("2026-03-15")),
    "Audio")
})

test_that("check_coverage never errors on a mismatch, only warns", {
  p <- weekly_plan()
  missing <- suppressWarnings(
    check_coverage(p, data.frame(channel = "Nowhere", stringsAsFactors = FALSE)))
  expect_equal(missing, "Nowhere")
})

test_that("a decomp sharing no columns with the line item grain warns clearly", {
  expect_warning(check_coverage(std_plan(), data.frame(vendor = "X")),
                 "shares no line item columns")
})

test_that("media_plan_from_df knows nothing about decomps", {
  expect_false(any(c("decomp", "decomp_through") %in%
                     names(formals(media_plan_from_df))))
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

# ---- metadata: name, nickname, advertiser, planner, status ------------------

test_that("name is required", {
  df <- data.frame(channel = "TV", planned_spend = 10)
  expect_error(media_plan_from_df(df, grain = "channel"), "`name` is required")
  expect_error(media_plan_from_df(df, grain = "channel", name = ""),
               "`name` is required")
  # and the class itself refuses an unnamed plan
  expect_error(MediaPlan(data = df, grain = "channel"), "@name is required")
})

test_that("optional metadata is stored and defaults to empty", {
  p <- media_plan_from_df(
    data.frame(channel = "TV", planned_spend = 10), grain = "channel",
    name = "Q2 Brand Plan", nickname = "aggressive TV",
    advertiser = "Acme", planner = "R. Roe", status = "to review")
  expect_identical(p@name, "Q2 Brand Plan")
  expect_identical(p@nickname, "aggressive TV")
  expect_identical(p@advertiser, "Acme")
  expect_identical(p@planner, "R. Roe")
  expect_identical(p@status, "to review")

  bare <- std_plan()
  expect_identical(bare@nickname, "")
  expect_identical(bare@advertiser, "")
  expect_identical(bare@status, "")
})

test_that("status is constrained to the fixed vocabulary", {
  expect_equal(status_levels(), c("in development", "to review", "approved"))
  df <- data.frame(channel = "TV", planned_spend = 10)
  expect_error(
    media_plan_from_df(df, grain = "channel", name = "t", status = "aproved"),
    "must be one of")
  # matched case-insensitively and stored canonically
  p <- media_plan_from_df(df, grain = "channel", name = "t", status = " APPROVED ")
  expect_identical(p@status, "approved")
  # the class rejects a non-canonical value set directly
  expect_error(MediaPlan(data = df, grain = "channel", name = "t",
                         status = "Approved"), "@status must be one of")
})

test_that("roll_up carries metadata and keeps the plan's name", {
  p <- media_plan_from_df(
    data.frame(channel = c("TV", "TV"), partner = c("A", "B"),
               planned_spend = c(10, 20)),
    grain = c("channel", "partner"), name = "Q2 Plan",
    advertiser = "Acme", planner = "R. Roe", status = "approved")
  r <- roll_up(p, "channel")
  expect_identical(r@name, "Q2 Plan")
  expect_identical(r@advertiser, "Acme")
  expect_identical(r@status, "approved")
})
