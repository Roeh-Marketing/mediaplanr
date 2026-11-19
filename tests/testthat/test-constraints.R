# PlanConstraints holds the group rules a plan lives under, and
# check_constraints() measures a plan against them. The contract worth
# pinning: a rule is a plain list, checked where it is written and stored one
# way however it was built; each rule type measures what it says, to the
# cent or exactly; a violation is warned about and reported, never refused;
# and the rules survive JSON and match their schema.

q4 <- list(from = "2026-10-01", to = "2026-12-31")
q1 <- list(from = "2027-01-01", to = "2027-03-31")

# Check quietly, and return one rule's row.
row_for <- function(plan, rule, reference = NULL) {
  out <- suppressWarnings(check_constraints(
    plan, plan_constraints(list(rule)), reference = reference))
  out[!is.na(out$rule), ]
}

# The agency plan with 80,000 moved out of Streaming in Q1 only: every row
# bound holds, but Streaming falls below 40% of the plan.
moved_in_q1 <- function() {
  build_scenario(fix_agency_plan(), name = "Q1 shift", edits = op_transfer(
    80000, from = list(channel = "Streaming"), to = list(partner = "DSP A"),
    during = q1))
}

# ---- building rules -----------------------------------------------------------

test_that("each constructor builds the hand-written rule", {
  tv <- list(channel = "TV")
  expect_identical(rule_min_spend(100), list(type = "min_spend", value = 100))
  expect_identical(rule_max_share(0.3, target = tv, during = q4, note = "cap"),
                   list(type = "max_share", value = 0.3, target = tv,
                        during = q4, note = "cap"))
  for (type in names(.rule_types)) {
    expect_true(exists(paste0("rule_", type), mode = "function"), info = type)
  }
})

test_that("a malformed rule errors where it is written", {
  expect_error(rule_min_share(1.5), "is a share, from 0 to 1; got 1.5")
  expect_error(rule_max_spend(-1), "`value` must be 0 or more")
  expect_error(rule_min_spend(5, target = list("TV")), "named list")
  expect_error(rule_min_spend(5, during = list(from = "2026-10-01 08:00",
                                               to = "2026-10-02")),
               "must be a date \\(a rule measures whole days\\)")
  expect_error(plan_constraints(list(list(type = "at_least", value = 1))),
               "rule 1: `type` must be one of: min_spend")
  expect_error(plan_constraints(list(list(type = "min_spend", value = 1,
                                          scope = "all"))),
               "unknown field\\(s\\): scope")
  expect_error(plan_constraints(data.frame(type = "min_spend", value = 1,
                                           from = "2026-10-01", to = NA)),
               "rules row 1: give both `from` and `to`")
})

test_that("a sheet and a list of rules build the same object", {
  sheet <- fix_agency_constraints()
  listed <- plan_constraints(name = "agency guardrails", id = "constraints_agency",
    rules = list(
      rule_min_share(0.4, target = list(channel = "Streaming"),
                     note = "Streaming holds at least 40% of the plan"),
      rule_fixed_total(360000, target = list(partner = "Stream A"),
                       note = "Upfront: total fixed, phasing free"),
      rule_max_spend(320000, target = list(channel = "Programmatic"),
                     during = q4, note = "Programmatic Q4 authorisation"),
      rule_max_share(0.25, target = list(channel = "Online Video"),
                     note = "Online Video at most a quarter of the plan"),
      rule_max_change_pct(0.25, target = list(channel = "Online Video"),
                          note = "Online Video moves at most 25% from the approved plan")))
  expect_identical(listed, sheet)
})

test_that("printing shows each rule in words", {
  out <- utils::capture.output(print(fix_agency_constraints()))
  expect_match(out[1], "<PlanConstraints> agency guardrails  \\(5 rules\\)")
  expect_match(out[4], "max_spend 320,000 on channel Programmatic, 2026-10-01..2026-12-31")
})

# ---- each rule type ------------------------------------------------------------

test_that("spend rules hold at their limit, to the cent", {
  a <- fix_agency_plan()                     # Streaming plans 600,000
  streaming <- list(channel = "Streaming")
  expect_true(row_for(a, rule_min_spend(600000, target = streaming))$ok)
  expect_false(row_for(a, rule_min_spend(600000.01, target = streaming))$ok)
  expect_true(row_for(a, rule_max_spend(600000, target = streaming))$ok)
  r <- row_for(a, rule_max_spend(599000, target = streaming))
  expect_false(r$ok)
  expect_equal(r$slack, -1000)
})

test_that("a fixed total holds only when met exactly, phasing aside", {
  a <- fix_agency_plan()
  ok <- row_for(a, rule_fixed_total(360000, target = list(partner = "Stream A")))
  expect_true(ok$ok)
  expect_equal(ok$slack, 0)
  off <- row_for(a, rule_fixed_total(359000, target = list(partner = "Stream A")))
  expect_false(off$ok)
  expect_equal(off$slack, -1000)
})

test_that("share rules measure against the whole plan in the same window", {
  s <- moved_in_q1()
  streaming <- list(channel = "Streaming")
  whole <- row_for(s, rule_min_share(0.4, target = streaming))
  expect_false(whole$ok)
  expect_equal(whole$actual, round(520000 / 1320600, 4))
  # Q4 is untouched by a Q1 move; Q1 bears all of it
  expect_true(row_for(s, rule_min_share(0.4, target = streaming, during = q4))$ok)
  expect_false(row_for(s, rule_min_share(0.4, target = streaming, during = q1))$ok)
  expect_true(row_for(s, rule_max_share(1, target = streaming))$ok)
})

test_that("change rules measure against the reference", {
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "more video", edits = op_scale(
    1.2, target = list(partner = "Video B")))         # Video B plans 0
  more <- build_scenario(a, name = "more video", edits = op_transfer(
    52650, from = list(partner = "DSP A"), to = list(channel = "Online Video")))
  # Online Video 210,600 -> 263,250: +25% exactly
  video <- list(channel = "Online Video")
  expect_true(row_for(more, rule_max_change_pct(0.25, target = video), a)$ok)
  expect_false(row_for(more, rule_max_change_pct(0.2, target = video), a)$ok)
  r <- row_for(more, rule_max_change_abs(50000, target = video), a)
  expect_false(r$ok)
  expect_equal(r$actual, 52650)
  expect_equal(row_for(s, rule_max_change_pct(0, target = video), a)$actual, 0)
})

test_that("a change rule needs a reference", {
  expect_error(check_constraints(fix_agency_plan(), fix_agency_constraints()),
               "`reference` is required: rule\\(s\\) 5 measure change")
})

test_that("a line the plan dropped can still be measured against the reference", {
  a <- fix_agency_plan()
  dropped <- build_scenario(a, name = "no added value", edits = op_drop(
    target = list(tactic = "Added Value")))
  r <- row_for(dropped, rule_max_change_abs(100, target = list(tactic = "Added Value")), a)
  expect_false(r$ok)
  expect_equal(r$actual, 600)
})

# ---- reporting -------------------------------------------------------------------

test_that("a scenario that respects every row bound can still break a group rule", {
  a <- fix_agency_plan()
  expect_silent(ok <- check_constraints(a, fix_agency_constraints(), reference = a))
  expect_true(all(ok$ok))

  expect_warning(
    out <- check_constraints(moved_in_q1(), fix_agency_constraints(), reference = a),
    "1 of 6 rule\\(s\\) violated: min_share 0.4 on channel Streaming: actual 0.3938")
  expect_identical(out$type[!out$ok], "min_share")
  expect_true(out$ok[out$type == "row_bounds"])          # the rows are fine
})

test_that("row bounds are reported only for a plan that has them", {
  rules <- plan_constraints(list(rule_min_spend(1)))
  expect_false("row_bounds" %in% check_constraints(std_plan(), rules)$type)
  expect_true("row_bounds" %in% check_constraints(fix_agency_plan(), rules)$type)
})

test_that("a rule's target is checked against the plan like an op's", {
  a <- fix_agency_plan()
  expect_error(check_constraints(a, plan_constraints(list(
    rule_min_spend(1, target = list(channel = "Radio"))))),
    "rule 1: no such value\\(s\\) in 'channel': Radio. Valid:")
  expect_error(check_constraints(a, plan_constraints(list(
    rule_min_spend(1, target = list(month = "2026-10-01"))))),
    "may only name grain columns \\(channel, partner, campaign, tactic\\)")
})

# ---- JSON and schema -------------------------------------------------------------

test_that("rules survive a JSON round trip", {
  rules <- plan_constraints(name = "r", rules = list(
    rule_min_share(0.3, target = list(channel = c("Streaming", "Programmatic")),
                   during = list(from = as.Date("2026-10-01"), to = "2026-12-31")),
    rule_fixed_total(360000, target = list(partner = "Stream A")),
    rule_max_spend(2e6)))
  expect_identical(plan_from_json(plan_to_json(rules)), rules)
})

test_that("the schema accepts good rules and refuses bad ones", {
  schema <- jsonlite::fromJSON(constraints_schema(fix_agency_plan(), as_json = TRUE),
                               simplifyVector = FALSE)
  check <- function(json) {
    schema_problems(jsonlite::fromJSON(paste0("[", json, "]"),
                                       simplifyVector = FALSE), schema)
  }
  good <- c(
    '{"type": "min_share", "value": 0.4, "target": {"channel": "Streaming"}}',
    '{"type": "max_spend", "value": 320000, "target": {"channel": ["Programmatic"]},
      "during": {"from": "2026-10-01", "to": "2026-12-31"}, "note": "Q4"}',
    '{"type": "max_change_pct", "value": 1.5}')
  for (json in good) expect_identical(check(json), character(0), info = json)

  bad <- c(
    share_over_one = '{"type": "max_share", "value": 1.2}',
    negative       = '{"type": "min_spend", "value": -1}',
    unknown_type   = '{"type": "at_least", "value": 1}',
    no_value       = '{"type": "min_spend"}',
    time_target    = '{"type": "min_spend", "value": 1, "target": {"month": "2026-10-01"}}',
    unknown_value  = '{"type": "min_spend", "value": 1, "target": {"channel": "Radio"}}',
    moment_window  = '{"type": "min_spend", "value": 1,
                       "during": {"from": "2026-10-01 08:00", "to": "2026-10-02"}}')
  for (nm in names(bad)) expect_gt(length(check(bad[[nm]])), 0, label = nm)
})

# ---- in describe_plan() ------------------------------------------------------------

test_that("describe_plan() summarises the check: broken and binding rules", {
  a <- fix_agency_plan()
  section <- describe_plan(moved_in_q1(), constraints = fix_agency_constraints(),
                           reference = a)$constraints
  expect_identical(section$id, "constraints_agency")
  expect_identical(section$n_rules, 5L)
  expect_identical(section$n_ok, 4L)
  expect_match(section$violated$rule, "^min_share 0.4 on channel Streaming")
  # the upfront's fixed total holds with no slack to spare
  expect_match(section$binding$rule, "^fixed_total 360000 on partner Stream A")
})
