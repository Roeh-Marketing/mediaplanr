# level = "flight" answers the question cell level cannot: what happened to this
# BUY. The contract worth pinning: it joins on flight_id, names the change, and
# refuses to guess across plans that share no lineage.

cmp_base <- function() {
  media_plan_from_flights(
    data.frame(channel = c("OOH", "TV", "Search"),
               partner = c("JCD", "NBC", "Google"),
               flight_start = as.Date(rep("2026-04-06", 3)),
               flight_end   = as.Date(c("2026-05-03", "2026-04-19", "2026-04-19")),
               planned_spend = c(120000, 80000, 40000),
               stringsAsFactors = FALSE),
    grain = c("channel", "partner"), name = "Base", nickname = "base")
}

reworked <- function(base) {
  build_scenario(base, edits = list(
    list(target = list(channel = "OOH"), shift = 7),
    list(target = list(channel = "TV"), delta = -20000),
    list(target = list(channel = "Search"), drop = TRUE),
    list(add = list(channel = "Audio", partner = "Spotify",
                    flight_start = "2026-04-13", flight_end = "2026-04-26",
                    planned_spend = 25000))),
    name = "Reworked", nickname = "rework")
}

cmp_set <- function() {
  b <- cmp_base()
  add_scenario(scenario_set(b), reworked(b))
}

test_that("a moved flight is reported as moved, with the shift in days", {
  r <- compare_scenarios(cmp_set(), "flight")
  x <- r[r$scenario == "rework" & r$channel == "OOH", ]
  expect_identical(x$change, "moved")
  expect_identical(x$start_shift_days, 7L)
  expect_equal(x$spend_vs_base, 0)          # moved, not resized
})

test_that("a resized flight is reported as resized, holding its dates", {
  r <- compare_scenarios(cmp_set(), "flight")
  x <- r[r$scenario == "rework" & r$channel == "TV", ]
  expect_identical(x$change, "resized")
  expect_equal(x$spend_vs_base, -20000)
  expect_identical(x$start_shift_days, 0L)
})

test_that("dropped and added flights are named as such", {
  r <- compare_scenarios(cmp_set(), "flight")
  expect_identical(r$change[r$scenario == "rework" & r$channel == "Search"],
                   "dropped")
  expect_identical(r$change[r$scenario == "rework" & r$channel == "Audio"],
                   "added")
  expect_equal(r$planned_spend[r$scenario == "rework" & r$channel == "Search"], 0)
})

test_that("the baseline's own rows read as base, never as dropped", {
  r <- compare_scenarios(cmp_set(), "flight")
  b <- r[r$scenario == "base", ]
  expect_identical(sort(unique(b$change)), c("absent", "base"))
  # a flight only the scenario adds was never in the base
  expect_identical(b$change[b$channel == "Audio"], "absent")
})

test_that("a flight both moved and resized says so", {
  base <- cmp_base()
  s <- build_scenario(base, edits = list(
    list(target = list(channel = "OOH"), shift = 7),
    list(target = list(channel = "OOH"), delta = 10000)),
    name = "both", nickname = "both")
  r <- compare_scenarios(add_scenario(scenario_set(base), s), "flight")
  expect_identical(r$change[r$scenario == "both" & r$channel == "OOH"],
                   "moved & resized")
})

test_that("an untouched flight reads as unchanged", {
  base <- cmp_base()
  s <- build_scenario(base, edits = list(target = list(channel = "TV"),
                                         scale = 2), name = "tv", nickname = "tv")
  r <- compare_scenarios(add_scenario(scenario_set(base), s), "flight")
  expect_identical(r$change[r$scenario == "tv" & r$channel == "OOH"], "unchanged")
})

test_that("a hand-shaped flight reports its pacing", {
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000),
    grain = "channel", name = "P", nickname = "base")
  k <- line_item(p@data, p@grain)[1]
  bent <- build_scenario(p, edits = stats::setNames(24230.77, k),
                         name = "bent", nickname = "bent")
  r <- compare_scenarios(add_scenario(scenario_set(p), bent), "flight")
  expect_identical(r$pacing[r$scenario == "bent"], "custom")
  expect_identical(r$pacing[r$scenario == "base"], "even")
})

test_that("totals reconcile with the summary level", {
  set <- cmp_set()
  fl  <- compare_scenarios(set, "flight")
  sm  <- compare_scenarios(set, "summary")
  for (nm in sm$scenario) {
    expect_equal(sum(fl$planned_spend[fl$scenario == nm]),
                 sm$total_planned_spend[sm$scenario == nm])
  }
})

test_that("a set whose plans record no flights returns no rows", {
  w <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-04-06", "2026-04-13")), channel = "TV",
               planned_spend = c(10, 20)),
    grain = c("channel", "week"), week = "week", name = "w", nickname = "w")
  set <- add_scenario(scenario_set(w),
                      build_scenario(w, edits = list(scale = 2), name = "x"))
  r <- compare_scenarios(set, "flight")
  expect_identical(nrow(r), 0L)
  expect_true(all(c("scenario", "flight_id", "change") %in% names(r)))
})

test_that("plans with no shared lineage warn rather than inventing changes", {
  mk <- function(nm) media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-06"),
               flight_end = as.Date("2026-05-03"), planned_spend = 120000),
    grain = "channel", name = nm, nickname = nm)
  set <- add_scenario(scenario_set(mk("a")), mk("b"))
  expect_warning(compare_scenarios(set, "flight"), "no flight is shared")
})

test_that("a set of one scenario does not warn about sharing", {
  expect_silent(compare_scenarios(scenario_set(cmp_base()), "flight"))
})
