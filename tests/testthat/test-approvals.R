# Approval is a status and an optional date on a plan; a "revision" is the
# plan's place among the approved plans in its lineage, and the "current"
# approved plan is the latest approval on its branch. The contract worth
# pinning: revisions count approvals only, along the branch; the current plan
# is found by lineage, never by date; and compare_scenarios() can measure
# against the base, each parent, or the current approved plan.

approve <- function(plan, on) revise(plan, status = "approved", approved_on = on)

# base (Rev 1) -> r2 (Rev 2) -> r3 (Rev 3) -> r4 (Rev 4) -> r5 (Rev 5), with a
# draft off r3 that was never approved -- the rejected branch -- and a
# follow-up drafted on top of it.
approval_chain <- function() {
  base <- approve(std_plan(name = "base"), "2026-06-01")
  r2 <- approve(build_scenario(base, op_scale(1.10), name = "r2"), "2026-06-20")
  r3 <- approve(build_scenario(r2, op_delta(-10), name = "r3"), "2026-07-10")
  rejected <- revise(build_scenario(r3, op_scale(2), name = "rejected"),
                     status = "to review")
  follow_up <- build_scenario(rejected, op_delta(5), name = "follow-up")
  r4 <- approve(build_scenario(r3, op_delta(20), name = "r4"), "2026-08-01")
  r5 <- approve(build_scenario(r4, op_scale(0.95), name = "r5"), "2026-09-15")

  set <- scenario_set(base)
  for (p in list(r2, r3, rejected, follow_up, r4, r5)) set <- add_scenario(set, p)
  set
}

# Two approvals on sibling branches, the later one dated EARLIER.
parallel_approvals <- function() {
  base <- approve(std_plan(name = "base"), "2026-06-01")
  a <- approve(build_scenario(base, op_scale(1.1), name = "a"), "2026-07-01")
  b <- approve(build_scenario(base, op_scale(0.9), name = "b"), "2026-06-15")
  add_scenario(add_scenario(scenario_set(base), a), b)
}

# ---- revisions and the current plan ------------------------------------------

test_that("a revision counts the approved plans along the branch", {
  lin <- lineage(approval_chain())
  rev <- stats::setNames(lin$revision, lin$scenario)
  expect_identical(rev[c("base", "r2", "r3", "r4", "r5")],
                   c(base = 1L, r2 = 2L, r3 = 3L, r4 = 4L, r5 = 5L))
  # drafts are not revisions, and do not count toward the ones after them
  expect_true(all(is.na(rev[c("rejected", "follow-up")])))
  expect_identical(lin$approved_on[lin$scenario == "r3"], as.Date("2026-07-10"))
  expect_true(is.na(lin$approved_on[lin$scenario == "rejected"]))
})

test_that("the current approved plan has no approved plan after it", {
  set <- approval_chain()
  lin <- lineage(set)
  expect_identical(lin$scenario[lin$current], "r5")
  expect_identical(current_approved(set), "r5")
})

test_that("parallel approvals are all current, and dates do not pick one", {
  set <- parallel_approvals()
  expect_warning(current <- current_approved(set), "parallel branches: a, b")
  expect_identical(current, c("a", "b"))
  expect_identical(lineage(set)$revision, c(1L, 2L, 2L))
})

test_that("a set with no approvals has no current plan", {
  set <- add_scenario(scenario_set(std_plan()),
                      build_scenario(std_plan(), op_scale(2), name = "s"))
  expect_message(current <- current_approved(set), "no scenario in the set is approved")
  expect_identical(current, character(0))
})

test_that("revisions count only what the set records", {
  # r4 and r5 alone: the earlier approvals are not in the set, so r4 is the
  # first one this set can see.
  full <- approval_chain()
  part <- add_scenario(scenario_set(full@scenarios$r4), full@scenarios$r5)
  expect_identical(lineage(part)$revision, c(1L, 2L))
})

# ---- comparing against ---------------------------------------------------------

test_that("against = \"parent\" reconciles with lineage()", {
  set <- approval_chain()
  lin <- lineage(set)
  summary <- compare_scenarios(set, against = "parent")
  expect_equal(summary$spend_vs_parent, lin$spend_vs_parent)
  expect_true(is.na(summary$spend_vs_parent[summary$scenario == "base"]))

  cells <- compare_scenarios(set, "cell", against = "parent")
  by_scenario <- tapply(cells$spend_vs_parent, cells$scenario, sum)
  expect_equal(as.numeric(by_scenario[lin$scenario]), lin$spend_vs_parent)
})

test_that("against = \"current_approved\" measures from the current plan", {
  set <- approval_chain()
  out <- compare_scenarios(set, against = "current_approved")
  r5_spend <- out$total_planned_spend[out$scenario == "r5"]
  expect_equal(out$spend_vs_current_approved,
               out$total_planned_spend - r5_spend)
  expect_equal(out$spend_vs_current_approved[out$scenario == "r5"], 0)
})

test_that("against = \"current_approved\" needs exactly one current plan", {
  expect_error(compare_scenarios(parallel_approvals(), against = "current_approved"),
               "needs exactly one current approved plan; the set has 2 \\(a, b\\)")
  expect_error(compare_scenarios(scenario_set(std_plan()), against = "current_approved"),
               "the set has none")
})

test_that("the default still compares against the base", {
  set <- approval_chain()
  expect_identical(compare_scenarios(set),
                   compare_scenarios(set, against = "base"))
  expect_true("spend_vs_base" %in% names(compare_scenarios(set, "cell")))
})

test_that("flights are compared against each scenario's own parent", {
  base <- media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-06"),
               flight_end = as.Date("2026-05-03"), planned_spend = 10000),
    grain = "channel", name = "base")
  moved   <- build_scenario(base, op_shift(7), name = "moved")
  resized <- build_scenario(moved, op_delta(-2000), name = "resized")
  set <- add_scenario(add_scenario(scenario_set(base), moved), resized)

  vs_base <- compare_scenarios(set, "flight")
  expect_identical(vs_base$change[vs_base$scenario == "resized"], "moved & resized")

  vs_parent <- compare_scenarios(set, "flight", against = "parent")
  row <- vs_parent[vs_parent$scenario == "resized", ]
  expect_identical(row$change, "resized")       # its parent had already moved
  expect_equal(row$spend_vs_parent, -2000)
  expect_identical(row$start_shift_days, 0L)
  root <- vs_parent[vs_parent$scenario == "base", ]
  expect_true(is.na(root$change) && is.na(root$spend_vs_parent))
})

# ---- where approval shows ------------------------------------------------------

test_that("describe_plan() and subplan_map() show the approval date", {
  p <- approve(std_plan(), "2026-10-29")
  expect_identical(describe_plan(p)$identity$approved_on, "2026-10-29")
  expect_true(is.na(describe_plan(std_plan())$identity$approved_on))
  expect_identical(subplan_map(p)$approved_on, as.Date("2026-10-29"))
})
