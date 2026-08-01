test_that("edits override matched cells and preserve lineage", {
  p <- std_plan()
  s <- build_scenario(p, edits = data.frame(channel = "Search", planned_spend = 100),
                      name = "boost")
  expect_true(S7::S7_inherits(s, MediaPlan))
  expect_identical(s@parent_id, p@id)
  expect_false(identical(s@id, p@id))
  expect_equal(s@data$planned_spend[s@data$channel == "Search"], 100)
  # untouched cells unchanged
  expect_equal(s@data$planned_spend[s@data$channel == "TV"], 80)
  expect_identical(s@grain, p@grain)
})

test_that("the base plan is never mutated", {
  p <- std_plan()
  before <- p@data$planned_spend
  build_scenario(p, edits = c("Search" = 999))
  expect_equal(p@data$planned_spend, before)
})

test_that("edits accept a named numeric vector keyed by line_item", {
  p <- std_plan()
  s <- build_scenario(p, edits = c("TV" = 200))
  expect_equal(s@data$planned_spend[s@data$channel == "TV"], 200)
  expect_equal(s@data$planned_spend[s@data$channel == "Search"], 40)
})

test_that("edits work at a composite grain", {
  p <- fine_plan()
  s <- build_scenario(p, edits = c("TV | B" = 75))
  expect_equal(s@data$planned_spend[s@data$partner == "B"], 75)
  expect_equal(s@data$planned_spend[s@data$partner == "A"], 50)
})

test_that("multiple cells can be edited at once", {
  p <- std_plan()
  s <- build_scenario(
    p, edits = data.frame(channel = c("TV", "Social"), planned_spend = c(10, 20)))
  x <- stats::setNames(s@data$planned_spend, s@data$channel)
  expect_equal(unname(x[c("TV", "Search", "Social")]), c(10, 40, 20))
})

test_that("edits referencing an unknown cell error", {
  p <- std_plan()
  expect_error(
    build_scenario(p, edits = data.frame(channel = "Radio", planned_spend = 1)),
    "not in the plan")
  expect_error(build_scenario(p, edits = c("Radio" = 1)), "not in the plan")
})

test_that("edits are validated like any plan", {
  p <- std_plan()
  expect_error(build_scenario(p, edits = c("TV" = -5)), "non-negative")
})

test_that("build_scenario requires edits", {
  p <- std_plan()
  expect_error(build_scenario(p), "`edits` is required")
})

test_that("malformed edits are rejected", {
  p <- std_plan()
  # data frame missing planned_spend
  expect_error(build_scenario(p, edits = data.frame(channel = "TV")),
               "must contain a 'planned_spend' column")
  # data frame missing the grain column
  expect_error(build_scenario(p, edits = data.frame(planned_spend = 1)),
               "missing grain column")
  # unnamed numeric vector matches no supported shape
  expect_error(build_scenario(p, edits = c(1, 2, 3)), "must be one of")
})

test_that("lineage chains across successive derivations", {
  p <- std_plan()
  s1 <- build_scenario(p, edits = c("TV" = 100), name = "s1")
  s2 <- build_scenario(s1, edits = c("TV" = 120), name = "s2")
  expect_identical(s1@parent_id, p@id)
  expect_identical(s2@parent_id, s1@id)
})

# ---- operation form ---------------------------------------------------------

test_that("scale multiplies matched cells", {
  s <- build_scenario(std_plan(),
                      edits = list(target = list(channel = "Search"), scale = 1.2))
  x <- stats::setNames(s@data$planned_spend, s@data$channel)
  expect_equal(unname(x[["Search"]]), 48)
  expect_equal(unname(x[["TV"]]), 80)  # untouched
})

test_that("delta adds to matched cells and may be negative", {
  s <- build_scenario(std_plan(),
                      edits = list(target = list(channel = "TV"), delta = -30))
  expect_equal(s@data$planned_spend[s@data$channel == "TV"], 50)
})

test_that("set is per-cell, total is across cells", {
  p <- fine_plan()  # TV has two partner rows: 50 and 30
  per_cell <- build_scenario(p, edits = list(target = list(channel = "TV"), set = 50))
  expect_equal(per_cell@data$planned_spend[per_cell@data$channel == "TV"], c(50, 50))

  across <- build_scenario(p, edits = list(target = list(channel = "TV"), total = 160))
  tv <- across@data$planned_spend[across@data$channel == "TV"]
  expect_equal(sum(tv), 160)
  expect_equal(tv, c(100, 60))  # 50:30 mix preserved
})

test_that("total with no target rescales the whole plan", {
  s <- build_scenario(std_plan(), edits = list(total = 320))
  expect_equal(sum(s@data$planned_spend), 320)
  # mix preserved: TV was half the plan
  expect_equal(s@data$planned_spend[s@data$channel == "TV"], 160)
})

test_that("omitting target matches every row", {
  s <- build_scenario(std_plan(), edits = list(scale = 2))
  expect_equal(s@data$planned_spend, c(160, 80, 80))
})

test_that("a partial-key target hits every matching cell", {
  wk <- media_plan_from_df(
    data.frame(channel = rep(c("TV", "Search"), each = 2),
               week = rep(c("w1", "w2"), 2),
               planned_spend = c(30, 25, 15, 10)),
    grain = c("channel", "week"))
  # halve one week across all channels, without enumerating the cells
  s <- build_scenario(wk, edits = list(target = list(week = "w2"), scale = 0.5))
  expect_equal(s@data$planned_spend[s@data$week == "w2"], c(12.5, 5))
  expect_equal(s@data$planned_spend[s@data$week == "w1"], c(30, 15))
})

test_that("target values may be vectors", {
  s <- build_scenario(std_plan(),
                      edits = list(target = list(channel = c("TV", "Social")),
                                   set = 10))
  x <- stats::setNames(s@data$planned_spend, s@data$channel)
  expect_equal(unname(x[c("TV", "Search", "Social")]), c(10, 40, 10))
})

test_that("multiple ops apply in order", {
  s <- build_scenario(std_plan(), edits = list(
    list(target = list(channel = "TV"),     delta = -10),
    list(target = list(channel = "Search"), delta =  10)
  ))
  x <- stats::setNames(s@data$planned_spend, s@data$channel)
  expect_equal(unname(x[c("TV", "Search")]), c(70, 50))
  expect_equal(sum(s@data$planned_spend), 160)  # budget-neutral shift
})

test_that("a bad target value errors and names the alternatives", {
  expect_error(
    build_scenario(std_plan(),
                   edits = list(target = list(channel = "Radio"), scale = 2)),
    "no such value\\(s\\) in 'channel': Radio")
  expect_error(
    build_scenario(std_plan(),
                   edits = list(target = list(channel = "Radio"), scale = 2)),
    "Valid: TV, Search, Social")
})

test_that("target may only name grain columns", {
  expect_error(
    build_scenario(std_plan(),
                   edits = list(target = list(planned_spend = 80), scale = 2)),
    "may only name grain columns")
})

test_that("an op must carry exactly one operation key", {
  expect_error(build_scenario(std_plan(), edits = list(target = list(channel = "TV"))),
               "exactly one of")
  expect_error(build_scenario(std_plan(),
                              edits = list(target = list(channel = "TV"),
                                           scale = 2, delta = 1)),
               "exactly one of")
})

test_that("unknown op fields are rejected", {
  expect_error(
    build_scenario(std_plan(), edits = list(channel = "TV", scale = 2)),
    "unknown field\\(s\\): channel")
})

test_that("op values must be a single number", {
  expect_error(build_scenario(std_plan(), edits = list(scale = c(1, 2))),
               "single non-missing number")
  expect_error(build_scenario(std_plan(), edits = list(scale = "2")),
               "single non-missing number")
})

test_that("total on an all-zero group errors rather than guessing a split", {
  p <- media_plan_from_df(
    data.frame(channel = c("TV", "Search"), planned_spend = c(0, 0)),
    grain = "channel")
  expect_error(build_scenario(p, edits = list(total = 100)),
               "current planned_spend is 0")
})

test_that("ops still run through the plan validator", {
  expect_error(build_scenario(std_plan(),
                              edits = list(target = list(channel = "TV"),
                                           delta = -1000)),
               "non-negative")
})

test_that("an empty op list is rejected", {
  expect_error(build_scenario(std_plan(), edits = list()), "empty list")
})
