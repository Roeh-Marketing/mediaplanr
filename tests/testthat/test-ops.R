# Structural ops change which rows a plan has, where every op before them only
# changed spend on rows that were already there. The contract worth pinning: a
# plan can gain and lose line items, a flight can move without losing its
# identity, and every refusal names what to do instead.

ops_plan <- function(name = "ops") {
  media_plan_from_flights(
    data.frame(channel = c("OOH", "TV"), partner = c("JCD", "NBC"),
               flight_start = as.Date(c("2026-04-06", "2026-04-06")),
               flight_end   = as.Date(c("2026-05-03", "2026-04-19")),
               planned_spend = c(120000, 80000),
               stringsAsFactors = FALSE),
    grain = c("channel", "partner"), name = name)
}

weekly_two <- function() {
  media_plan_from_df(
    data.frame(week = as.Date(c("2026-04-06", "2026-04-13")), channel = "TV",
               planned_spend = c(10, 20)),
    grain = c("channel", "week"), week = "week", name = "weekly two")
}

# ---- add ---------------------------------------------------------------------

test_that("add introduces a line item as a flight", {
  s <- build_scenario(ops_plan(), edits = list(add = list(
    channel = "Audio", partner = "Spotify",
    flight_start = "2026-04-13", flight_end = "2026-04-26",
    planned_spend = 20000)), name = "with audio")
  expect_identical(nrow(s@data), 8L)
  expect_equal(sum(s@data$planned_spend), 220000)
  fl <- flights(s)
  expect_identical(nrow(fl), 3L)
  expect_equal(fl$planned_spend[fl$channel == "Audio"], 20000)
})

test_that("add introduces a line item for a single week", {
  s <- build_scenario(weekly_two(), edits = list(add = list(
    channel = "Radio", week = "2026-04-06", planned_spend = 100)), name = "radio")
  expect_identical(nrow(s@data), 3L)
  expect_equal(sum(s@data$planned_spend), 130)
})

test_that("adding a flight to a plan that has none introduces the flight columns", {
  s <- build_scenario(weekly_two(), edits = list(add = list(
    channel = "Radio", flight_start = "2026-04-06", flight_end = "2026-04-19",
    planned_spend = 100)), name = "radio flight")
  expect_true(all(flight_cols() %in% names(s@data)))
  expect_identical(nrow(flights(s)), 1L)          # the TV rows record no flight
  expect_equal(sum(s@data$planned_spend), 130)
})

test_that("add refuses to duplicate a cell that already exists", {
  expect_error(
    build_scenario(weekly_two(), edits = list(add = list(
      channel = "TV", week = "2026-04-06", planned_spend = 5)), name = "dup"),
    "already has row")
})

test_that("add must say when the line item runs", {
  expect_error(
    build_scenario(weekly_two(), edits = list(add = list(
      channel = "Radio", planned_spend = 5)), name = "when"),
    "needs either")
})

test_that("add must name the line item columns and a spend", {
  expect_error(
    build_scenario(weekly_two(), edits = list(add = list(
      week = "2026-04-06", planned_spend = 5)), name = "who"),
    "missing line item column")
  expect_error(
    build_scenario(weekly_two(), edits = list(add = list(
      channel = "Radio", week = "2026-04-06")), name = "what"),
    "needs a `planned_spend`")
})

test_that("add takes no target -- the row does not exist yet", {
  expect_error(
    build_scenario(weekly_two(), edits = list(
      target = list(channel = "TV"),
      add = list(channel = "Radio", week = "2026-04-06", planned_spend = 5)),
      name = "both"),
    "does not take a `target`")
})

# ---- drop --------------------------------------------------------------------

test_that("drop removes rows rather than zeroing them", {
  s <- build_scenario(ops_plan(), edits = list(target = list(channel = "TV"),
                                               drop = TRUE), name = "no tv")
  expect_identical(nrow(s@data), 4L)
  expect_false("TV" %in% s@data$channel)
  expect_identical(nrow(flights(s)), 1L)
})

test_that("a dropped line item still reports a real delta against the base", {
  base <- ops_plan("base")
  gone <- build_scenario(base, edits = list(target = list(channel = "TV"),
                                            drop = TRUE), name = "no tv",
                         nickname = "cut")
  cmp <- compare_scenarios(add_scenario(scenario_set(base), gone), "cell")
  tv <- cmp[cmp$scenario == "cut" & cmp$channel == "TV", ]
  expect_identical(nrow(tv), 2L)                  # zero-filled, not missing
  expect_equal(sum(tv$spend_vs_base), -80000)
})

test_that("drop takes no value", {
  expect_error(
    build_scenario(ops_plan(), edits = list(target = list(channel = "TV"),
                                            drop = 1), name = "x"),
    "must be TRUE")
})

# ---- during ------------------------------------------------------------------

test_that("during selects rows whose period overlaps the window", {
  s <- build_scenario(ops_plan(), edits = list(
    during = list(from = "2026-04-20", to = "2026-05-31"), scale = 0.5),
    name = "back half")
  # TV's flight ends 2026-04-19, so it is untouched
  expect_equal(sum(s@data$planned_spend[s@data$channel == "TV"]), 80000)
  expect_equal(sum(s@data$planned_spend[s@data$channel == "OOH"]), 90000)
})

test_that("during composes with target", {
  s <- build_scenario(ops_plan(), edits = list(
    target = list(channel = "OOH"),
    during = list(from = "2026-04-01", to = "2026-04-12"), scale = 0),
    name = "kill april head")
  expect_equal(sum(s@data$planned_spend), 170000)
})

test_that("during rejects a backwards or unparseable window", {
  expect_error(build_scenario(ops_plan(), edits = list(
    during = list(from = "2026-05-31", to = "2026-04-01"), scale = 1),
    name = "x"), "ends .* before it starts")
  expect_error(build_scenario(ops_plan(), edits = list(
    during = list(from = "not a date", to = "2026-04-01"), scale = 1),
    name = "x"), "ISO-8601")
})

test_that("during that matches nothing errors rather than silently doing nothing", {
  expect_error(build_scenario(ops_plan(), edits = list(
    during = list(from = "2027-01-01", to = "2027-02-01"), scale = 2),
    name = "x"), "no rows are in market")
})

# ---- shift and restage -------------------------------------------------------

test_that("shift moves a flight and keeps its identity", {
  base <- ops_plan()
  s <- build_scenario(base, edits = list(target = list(channel = "OOH"),
                                         shift = 7), name = "pushed")
  fl <- flights(s)[flights(s)$channel == "OOH", ]
  expect_identical(fl$flight_start, as.Date("2026-04-13"))
  expect_identical(fl$flight_end, as.Date("2026-05-10"))
  expect_equal(fl$planned_spend, 120000)
  # the same buy, moved -- not a drop plus an add
  expect_identical(sort(unique(s@data$flight_id)),
                   sort(unique(base@data$flight_id)))
})

test_that("restage moves a flight to explicit dates", {
  s <- build_scenario(ops_plan(), edits = list(
    target = list(channel = "TV"),
    restage = list(from = "2026-05-04", to = "2026-05-31")), name = "later")
  fl <- flights(s)[flights(s)$channel == "TV", ]
  expect_identical(fl$flight_start, as.Date("2026-05-04"))
  expect_equal(fl$planned_spend, 80000)
})

test_that("a shifted flight keeps its total even when the new dates are ragged", {
  s <- build_scenario(ops_plan(), edits = list(target = list(channel = "OOH"),
                                               shift = 3), name = "ragged")
  expect_equal(sum(s@data$planned_spend[s@data$channel == "OOH"]), 120000)
  expect_identical(nrow(s@data[s@data$channel == "OOH", ]), 5L)
})

test_that("a custom-paced flight keeps its shape through a whole-week shift", {
  p <- ops_plan()
  k <- line_item(p@data, p@grain)[p@data$channel == "OOH"][1]
  bent <- build_scenario(p, edits = stats::setNames(50000, k), name = "bent")
  expect_identical(flights(bent)$pacing[flights(bent)$channel == "OOH"], "custom")

  s <- build_scenario(bent, edits = list(target = list(channel = "OOH"),
                                         shift = 7), name = "moved")
  ooh <- s@data[s@data$channel == "OOH", ]
  ooh <- ooh[order(ooh$week), ]
  expect_equal(ooh$planned_spend, c(50000, 30000, 30000, 30000))
})

test_that("a custom-paced flight refuses a shift that changes its week structure", {
  p <- ops_plan()
  k <- line_item(p@data, p@grain)[p@data$channel == "OOH"][1]
  bent <- build_scenario(p, edits = stats::setNames(50000, k), name = "bent")
  expect_error(
    build_scenario(bent, edits = list(target = list(channel = "OOH"), shift = 3),
                   name = "x"),
    "custom-paced")
})

test_that("moving a flight onto one already planned is a collision", {
  two <- media_plan_from_flights(
    data.frame(channel = c("OOH", "OOH"),
               flight_start = as.Date(c("2026-04-06", "2026-05-04")),
               flight_end   = as.Date(c("2026-04-12", "2026-05-10")),
               planned_spend = c(10, 20)),
    grain = "channel", name = "two bursts")
  expect_error(
    build_scenario(two, edits = list(
      during = list(from = "2026-05-04", to = "2026-05-10"),
      restage = list(from = "2026-04-06", to = "2026-04-12")), name = "x"),
    "would collide")
})

test_that("rows with no flight shift by whole weeks only", {
  s <- build_scenario(weekly_two(), edits = list(shift = 7), name = "later")
  expect_identical(s@data$week, as.Date(c("2026-04-13", "2026-04-20")))
  expect_error(build_scenario(weekly_two(), edits = list(shift = 3), name = "x"),
               "multiple of 7")
})

test_that("restage refuses rows that record no flight, naming the alternative", {
  expect_error(
    build_scenario(weekly_two(), edits = list(
      restage = list(from = "2026-05-04", to = "2026-05-10")), name = "x"),
    "`restage` needs flights")
})

test_that("shift must be a whole number of days", {
  expect_error(build_scenario(ops_plan(), edits = list(shift = 2.5), name = "x"),
               "whole number of days")
})

# ---- composition -------------------------------------------------------------

test_that("structural and value ops compose in order", {
  s <- build_scenario(weekly_two(), edits = list(
    list(add = list(channel = "Radio", week = "2026-04-06", planned_spend = 100)),
    list(target = list(channel = "Radio"), scale = 0.5)), name = "add then trim")
  expect_equal(s@data$planned_spend[s@data$channel == "Radio"], 50)
})

test_that("a scenario built with structural ops still records its parent", {
  base <- ops_plan("base")
  before <- base@data                       # flight ids are random per import,
  s <- build_scenario(base, edits = list(target = list(channel = "TV"),
                                         drop = TRUE), name = "cut")
  expect_identical(s@parent_id, base@id)
  expect_identical(base@data, before)       # so snapshot rather than rebuild
})
