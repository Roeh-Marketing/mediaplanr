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

test_that("edits accept a named numeric vector keyed by grain_key", {
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
  # unnamed numeric vector
  expect_error(build_scenario(p, edits = c(1, 2, 3)), "must be a data frame")
})

test_that("lineage chains across successive derivations", {
  p <- std_plan()
  s1 <- build_scenario(p, edits = c("TV" = 100), name = "s1")
  s2 <- build_scenario(s1, edits = c("TV" = 120), name = "s2")
  expect_identical(s1@parent_id, p@id)
  expect_identical(s2@parent_id, s1@id)
})
