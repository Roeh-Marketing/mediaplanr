# The inventory answers "what is in this plan?". The contract worth pinning:
# values come back in a shape an edit `target` accepts, the roster reconciles
# with the plan total, and asking for a column the plan lacks names the ones it
# has rather than returning nothing.

test_that("grain_values() returns sorted distinct values for one column", {
  expect_identical(grain_values(fine_plan(), "channel"),
                   c("Search", "Social", "TV"))
})

test_that("grain_values() keeps the column's own type", {
  expect_s3_class(grain_values(weekly_plan(), "week"), "Date")
  expect_type(grain_values(weekly_plan(), "channel"), "character")
})

test_that("grain_values() with no column covers the whole grain, week included", {
  v <- grain_values(weekly_plan())
  expect_identical(names(v), c("channel", "partner", "week"))
  expect_identical(v$partner, c("Google", "Hulu", "NBC"))
})

test_that("a column outside the grain errors, naming the valid ones", {
  expect_error(grain_values(fine_plan(), "tactic"),
               "must name a single grain column \\(channel, partner, week\\)")
})

test_that("its values are usable as an edit target", {
  p <- fine_plan()
  ch <- grain_values(p, "channel")[1]
  expect_silent(build_scenario(p, edits = list(target = list(channel = ch),
                                               scale = 2), name = "ok"))
})

test_that("the roster has one row per line item and reconciles to the total", {
  p <- weekly_plan()
  s <- line_item_summary(p)
  expect_identical(nrow(s), 3L)
  expect_identical(sum(s$planned_spend), sum(p@data$planned_spend))
  expect_identical(sum(s$n_rows), nrow(p@data))
})

test_that("the roster carries the grain columns, the key, and a flight window", {
  s <- line_item_summary(weekly_plan())
  expect_identical(names(s), c("channel", "partner", "line_item",
                               "planned_spend", "n_rows",
                               "flight_start", "flight_end"))
  hulu <- s[s$line_item == "TV | Hulu", ]
  expect_identical(hulu$planned_spend, 15)
  expect_identical(hulu$n_rows, 1L)
  # TV | Hulu runs only in the April week
  expect_identical(hulu$flight_start, as.Date("2026-04-06"))
  expect_identical(hulu$flight_end, as.Date("2026-04-12"))
})

test_that("the roster is ordered by spend, largest first", {
  s <- line_item_summary(weekly_plan())
  expect_identical(s$planned_spend, sort(s$planned_spend, decreasing = TRUE))
  expect_identical(s$line_item[1], "TV | NBC")
})

test_that("every roster carries the item's own window, in the time column's type", {
  s <- line_item_summary(std_plan())
  expect_true(all(c("flight_start", "flight_end") %in% names(s)))
  expect_s3_class(s$flight_start, "Date")
  expect_identical(nrow(s), 3L)

  spots <- media_plan_from_df(
    data.frame(airs = as.POSIXct(c("2026-04-06 20:30:00", "2026-04-06 21:00:00"),
                                 tz = "UTC"),
               channel = c("TV", "Radio"), planned_spend = c(1, 2)),
    grain = "channel", time = "airs", name = "spots")
  expect_s3_class(line_item_summary(spots)$flight_start, "POSIXct")
})

test_that("an empty plan gives an empty roster with the columns still there", {
  p <- MediaPlan(
    data = data.frame(week = as.Date(character(0)), channel = character(0),
                      planned_spend = numeric(0)),
    grain = c("channel", "week"), time_col = "week", name = "Empty")
  s <- line_item_summary(p)
  expect_identical(nrow(s), 0L)
  expect_true(all(c("channel", "line_item", "planned_spend") %in% names(s)))
})

test_that("a plan cannot be keyed on time alone", {
  expect_error(
    media_plan_from_df(
      data.frame(week = as.Date(c("2026-03-02", "2026-03-09")),
                 planned_spend = c(10, 20)),
      grain = c(), time = "week", name = "Weeks only"),
    "at least one line item column")
})

test_that("the inventory verbs reject anything that is not a plan", {
  expect_error(grain_values(weekly_df(), "channel"), "must be a MediaPlan")
  expect_error(line_item_summary(weekly_df()), "must be a MediaPlan")
})
