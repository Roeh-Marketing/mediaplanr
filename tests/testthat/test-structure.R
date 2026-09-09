# Structure views are projections: the table a UI builds from, a console tree,
# a lineage table, and a Mermaid string. The contract: they describe the tree
# and the derivation graph faithfully, and a flat plan or a one-scenario set
# comes out clean rather than decorated.

tv_detail <- function() {
  media_plan_from_df(
    data.frame(channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50), stringsAsFactors = FALSE),
    grain = c("channel", "partner"), name = "TV detail", nickname = "tv")
}

nbc_detail <- function() {
  media_plan_from_df(
    data.frame(channel = "TV", partner = "NBC", daypart = c("prime", "day"),
               planned_spend = c(60, 15)),
    grain = c("channel", "partner", "daypart"), name = "NBC upfront")
}

two_level <- function() {
  attach_subplan(std_plan(name = "Q3 topline"),
                 attach_subplan(tv_detail(), nbc_detail()))
}

# ---- subplan_map ---------------------------------------------------------------

test_that("subplan_map lists the tree in pre-order with depth, key and path", {
  m <- subplan_map(two_level())
  expect_equal(nrow(m), 3)
  expect_equal(m$depth, c(0L, 1L, 2L))
  expect_equal(m$key,   c(NA, "TV", "TV | NBC"))
  expect_equal(m$path,  c("", "TV", "TV > TV | NBC"))
  expect_equal(m$name,  c("Q3 topline", "TV detail", "NBC upfront"))
  expect_equal(m$spend, c(125 + 40 + 40, 125, 75))   # TV 80 -> 125
  expect_equal(m$subplans, c(1L, 1L, 0L))
  expect_equal(m$line_items, c(3L, 2L, 2L))
  expect_equal(m$grain, c("channel", "channel + partner",
                          "channel + partner + daypart"))
  expect_equal(m$cadence, rep("timeless", 3))
  expect_equal(m$nickname[2], "tv")
})

test_that("a flat plan is one row", {
  m <- subplan_map(std_plan())
  expect_equal(nrow(m), 1)
  expect_true(is.na(m$key))
  expect_equal(m$subplans, 0L)
})

test_that("cadence is read off the data", {
  expect_equal(subplan_map(weekly_plan())$cadence, "weekly")
  fl <- media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-04-21"), planned_spend = 14),
    grain = "channel", name = "fl")
  expect_equal(subplan_map(fl)$cadence, "flighted")
  wk <- media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-06"),
               flight_end = as.Date("2026-04-12"), planned_spend = 14),
    grain = "channel", name = "wk")
  expect_equal(subplan_map(wk)$cadence, "weekly")
  expect_error(subplan_map(1), "must be a MediaPlan")
})

# ---- plan_tree -----------------------------------------------------------------

test_that("plan_tree draws the tree and an editable line under each topline", {
  out <- utils::capture.output(lines <- plan_tree(two_level()))
  expect_identical(out, lines)
  expect_equal(length(out), 5)
  expect_match(out[1], "^Q3 topline +205$")
  expect_match(out[2], "^├─ TV +TV detail +timeless +2 line items +125$")
  expect_match(out[3], "^│  ├─ TV \\| NBC +NBC upfront +timeless +2 line items +75$")
  expect_match(out[4], "^│  └─ \\(editable\\) +1 line item +50$")
  expect_match(out[5], "^└─ \\(editable\\) +2 line items +80$")
})

test_that("plan_tree on a flat plan is one line with the header facts", {
  p <- revise(std_plan(name = "Base"), revision = 2, status = "approved")
  out <- utils::capture.output(plan_tree(p))
  expect_equal(length(out), 1)
  expect_match(out, "^Base  Rev 2  \\[approved\\] +160$")
  expect_false(grepl("editable", out))
})

# ---- ownership_map -------------------------------------------------------------

test_that("ownership_map labels each cell with the subplan that owns it", {
  p <- attach_subplan(std_plan(), tv_detail())
  o <- ownership_map(p)
  expect_equal(nrow(o), 3)
  expect_equal(o$key, c("Search", "Social", "TV"))          # timeless: by key
  expect_equal(o$owner, c(NA, NA, "TV"))
  expect_equal(o$owner_name, c(NA, NA, "TV detail"))
  expect_equal(o$locked, c(FALSE, FALSE, TRUE))
  expect_equal(o$planned_spend, c(40, 40, 120))
  expect_named(o, c("channel", "key", "owner", "owner_name", "locked", "planned_spend"))
})

test_that("ownership_map on a weekly plan is one row per cell-week, by week", {
  parent <- weekly_plan()
  sub <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-03-02", "2026-03-09")), channel = "TV",
               partner = "NBC", daypart = "prime", planned_spend = c(10, 12)),
    grain = c("channel", "partner", "daypart", "week"), week = "week",
    name = "NBC detail")
  o <- ownership_map(attach_subplan(parent, sub))
  expect_true("week" %in% names(o))
  expect_equal(o$week, sort(o$week))
  expect_equal(o$owner[o$key == "TV | NBC"], rep("TV | NBC", 2))
  expect_true(all(is.na(o$owner[o$key != "TV | NBC"])))
  expect_equal(sum(o$locked), 2)
})

test_that("ownership_map on a flat plan locks nothing", {
  o <- ownership_map(std_plan())
  expect_false(any(o$locked))
  expect_true(all(is.na(o$owner)))
  expect_error(ownership_map(1), "must be a MediaPlan")
})

# ---- lineage -------------------------------------------------------------------

test_that("lineage points each scenario at the parent it came from", {
  base <- std_plan(name = "base")
  s1   <- build_scenario(base, c(Search = 60), name = "s1")
  s2   <- build_scenario(s1, c(TV = 70), name = "s2", status = "to review")
  set  <- add_scenario(add_scenario(scenario_set(base), s1), s2)
  l    <- lineage(set)
  expect_equal(l$scenario, c("base", "s1", "s2"))
  expect_equal(l$parent,   c(NA, "base", "s1"))
  expect_equal(l$depth,    c(0L, 1L, 2L))
  expect_equal(l$spend,    c(160, 180, 170))
  expect_equal(l$spend_vs_parent, c(NA, 20, -10))
  expect_equal(l$spend_pct_vs_parent, c(NA, 20 / 160, -10 / 180))
  expect_equal(l$status[3], "to review")
  expect_equal(l$id, c(base@id, s1@id, s2@id))
})

test_that("a scenario whose parent is not in the set is a root", {
  base <- std_plan(name = "base")
  s1   <- build_scenario(base, c(Search = 60), name = "s1")
  set  <- add_scenario(scenario_set(s1), std_plan(name = "other"))
  l    <- lineage(set)
  expect_true(all(is.na(l$parent)))
  expect_equal(l$depth, c(0L, 0L))
  expect_true(all(is.na(l$spend_vs_parent)))
  expect_equal(l$parent_id[1], base@id)
  expect_error(lineage(base), "must be a ScenarioSet")
})

# ---- plan_mermaid --------------------------------------------------------------

test_that("plan_mermaid draws the subplan tree with keys on the edges", {
  s <- plan_mermaid(two_level())
  expect_match(s, "^graph TD\n")
  expect_match(s, 'n1\\["Q3 topline<br/>205 · timeless"\\]')
  expect_match(s, "n1 -->\\|TV\\| n2")
  # a pipe in a key would end the edge label, so it is entity-encoded
  expect_match(s, "n2 -->\\|TV #124; NBC\\| n3", fixed = FALSE)
  expect_false(grepl("-->\\|TV \\| NBC", s))
  expect_match(plan_mermaid(two_level(), "LR"), "^graph LR\n")
})

test_that("plan_mermaid draws lineage with deltas and marks the baseline", {
  base <- std_plan(name = "base")
  s1   <- build_scenario(base, c(Search = 60), name = "s1")
  set  <- add_scenario(scenario_set(base), s1)
  s    <- plan_mermaid(set)
  expect_match(s, 'n1\\["base<br/>160"\\]:::base')
  expect_match(s, 'n2\\["s1<br/>180 · in development"\\]')
  expect_match(s, "n1 -->\\|\\+20 \\(\\+12%\\)\\| n2")
  expect_match(s, "classDef base")
})

test_that("plan_mermaid escapes quotes and refuses other objects", {
  p <- std_plan(name = 'the "big" plan')
  expect_match(plan_mermaid(p), "the #quot;big#quot; plan")
  expect_error(plan_mermaid(1), "must be a MediaPlan or a ScenarioSet")
})
