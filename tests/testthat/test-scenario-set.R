test_that("scenario_set registers the base plan as baseline", {
  p <- std_plan()
  set <- scenario_set(p, name = "base")
  expect_true(S7::S7_inherits(set, ScenarioSet))
  expect_identical(set@base_name, "base")
  expect_equal(length(set@scenarios), 1L)
  expect_true(S7::S7_inherits(set@scenarios$base, MediaPlan))
  expect_identical(set@grain, p@grain)
})

test_that("scenario_set falls back to the plan's @name", {
  set <- scenario_set(std_plan(name = "Q3 base"))
  expect_identical(set@base_name, "Q3 base")
})

test_that("add_scenario appends without mutating the original set", {
  p <- std_plan()
  set0 <- scenario_set(p, name = "base")
  s <- build_scenario(p, edits = c("Search" = 100), name = "boost")
  set1 <- add_scenario(set0, s)

  expect_equal(length(set0@scenarios), 1L)  # original untouched
  expect_equal(length(set1@scenarios), 2L)
  expect_true("boost" %in% names(set1@scenarios))
})

test_that("add_scenario auto-names and de-duplicates names", {
  p <- std_plan()
  set <- scenario_set(p, name = "base")
  set <- add_scenario(set, build_scenario(p, edits = c("TV" = 100), name = "s"))
  set <- add_scenario(set, build_scenario(p, edits = c("TV" = 120), name = "s"))
  expect_equal(length(unique(names(set@scenarios))), 3L)

  # explicit duplicate name gets a suffix rather than clobbering
  set <- add_scenario(set, build_scenario(p, edits = c("TV" = 130), name = "s"), name = "base")
  expect_equal(length(set@scenarios), 4L)
  expect_true("base_2" %in% names(set@scenarios))
})

test_that("add_scenario rejects a grain mismatch", {
  set <- scenario_set(std_plan())
  expect_error(add_scenario(set, fine_plan()), "must match the set grain")
})

test_that("compare_scenarios summary reports planned_spend deltas vs base", {
  p <- std_plan()
  set <- scenario_set(p, name = "base")
  set <- add_scenario(set, build_scenario(p, edits = c("Search" = 120),
                                          name = "boost"))

  cmp <- compare_scenarios(set)
  expect_equal(nrow(cmp), 2L)
  expect_true(all(c("scenario", "plan_id", "parent_id", "total_planned_spend",
                    "spend_vs_base", "spend_pct_vs_base") %in% names(cmp)))

  base_row <- cmp[cmp$scenario == "base", ]
  expect_equal(base_row$total_planned_spend, 160)
  expect_equal(base_row$spend_vs_base, 0)
  expect_true(is.na(base_row$parent_id))

  boost_row <- cmp[cmp$scenario == "boost", ]
  expect_equal(boost_row$total_planned_spend, 240)
  expect_equal(boost_row$spend_vs_base, 80)
  expect_equal(boost_row$spend_pct_vs_base, 0.5)
  expect_identical(boost_row$parent_id, p@id)
})

test_that("compare_scenarios cell reports share and per-cell delta", {
  p <- std_plan()
  set <- scenario_set(p, name = "base")
  set <- add_scenario(set, build_scenario(p, edits = c("TV" = 40), name = "cut"))

  cell <- compare_scenarios(set, "cell")
  expect_equal(nrow(cell), 6L)  # 2 scenarios x 3 cells
  expect_true(all(c("scenario", "channel", "planned_spend", "share_of_total",
                    "spend_vs_base") %in% names(cell)))

  base_tv <- cell[cell$scenario == "base" & cell$channel == "TV", ]
  expect_equal(base_tv$share_of_total, 0.5)
  expect_equal(base_tv$spend_vs_base, 0)

  cut_tv <- cell[cell$scenario == "cut" & cell$channel == "TV", ]
  expect_equal(cut_tv$spend_vs_base, -40)
  # shares within each scenario sum to 1
  for (nm in unique(cell$scenario)) {
    expect_equal(sum(cell$share_of_total[cell$scenario == nm]), 1)
  }
})

test_that("compare_scenarios works at a composite grain", {
  p <- fine_plan()
  set <- scenario_set(p, name = "base")
  set <- add_scenario(set, build_scenario(p, edits = c("TV | A" = 70),
                                          name = "shift"))
  cell <- compare_scenarios(set, "cell")
  expect_equal(nrow(cell), 8L)
  expect_true(all(c("channel", "partner") %in% names(cell)))
  shift_a <- cell[cell$scenario == "shift" & cell$partner == "A", ]
  expect_equal(shift_a$spend_vs_base, 20)
})

test_that("scenario labels prefer nickname over the formal name", {
  base <- media_plan_from_df(
    data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
    grain = "channel", name = "Q2 2026 Brand Plan", nickname = "baseline")
  set <- scenario_set(base)
  expect_identical(names(set@scenarios), "baseline")

  s <- build_scenario(base, edits = c("TV" = 100),
                      name = "Q2 2026 Brand Plan v2", nickname = "aggressive TV")
  set <- add_scenario(set, s)
  expect_true("aggressive TV" %in% names(set@scenarios))
})

test_that("labels fall back to the formal name when there is no nickname", {
  set <- scenario_set(std_plan(name = "Formal Name"))
  expect_identical(names(set@scenarios), "Formal Name")
})
