# describe_plan() is what an agent reads before it edits a plan. The contract
# worth pinning: its shape is stable (snapshotted), its size does not grow
# with the plan, and every number in it reconciles to @data.

# The agency fixture with a fixed id, so its description is reproducible.
agency <- function() {
  .copy_plan(fix_agency_plan(name = "Q4-Q1 national digital"),
             id = "plan_agency")
}

# A scenario of it, also with fixed ids.
agency_scenario <- function() {
  s <- build_scenario(agency(), name = "Move to regional", nickname = "s1",
    objective = "Shift programmatic to regional streaming",
    rationale = list(author = "agent"),
    edits = list(
      op_transfer(37419, from = list(partner = "DSP A"),
                  to = list(channel = "Streaming", tactic = "Regional")),
      op_scale(1.1, target = list(partner = "Stream B"))))
  .copy_plan(s, id = "plan_s1")
}

# A plan of `n_items` line items over `n_weeks` weeks, no bounds, no units.
big_plan <- function(n_items, n_weeks) {
  items <- expand.grid(channel = paste0("Channel ", 1:5),
                       partner = paste0("Partner ", seq_len(n_items / 5)),
                       stringsAsFactors = FALSE)
  weeks <- seq(as.Date("2026-01-05"), by = "week", length.out = n_weeks)
  df <- merge(items, data.frame(week = weeks))
  df$planned_spend <- (seq_len(nrow(df)) %% 97) * 100
  media_plan_from_df(df, grain = c("channel", "partner"), time = "week",
                     name = "big")
}

compact_json <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE, dataframe = "rows", na = "null")
}

# ---- shape -------------------------------------------------------------------

test_that("the description of a plan is stable", {
  expect_snapshot(cat(describe_plan(agency(), top_n = 3, as_json = TRUE)))
})

test_that("the description of a scenario is stable", {
  expect_snapshot(cat(describe_plan(agency_scenario(), top_n = 3,
                                    as_json = TRUE)))
})

test_that("its size does not grow with the plan", {
  small <- nchar(compact_json(describe_plan(big_plan(100, 1))))
  large <- nchar(compact_json(describe_plan(big_plan(100, 50))))   # 5,000 rows
  expect_lt(large, 4000)
  # the only section that grows is spend by month: ~a dozen of them here
  expect_lt(large - small, 600)

  d <- describe_plan(big_plan(100, 50))
  expect_identical(nrow(d$money$spend_by$partner$top), 10L)
  expect_identical(d$money$spend_by$partner$other$n_values, 10L)
  expect_length(d$targetable$values$partner$top, 10)
})

test_that("one-element lists stay JSON arrays", {
  s <- build_scenario(agency(), name = "s", edits = op_scale(
    1.1, target = list(partner = "Stream B")))
  js <- describe_plan(s, as_json = TRUE)
  expect_match(js, '"edits": \\["scale"\\]')
  expect_match(js, '"subplan_cells": \\[\\]')
})

# ---- every number reconciles to @data -----------------------------------------

test_that("money, commitments, units and months all add back to the plan", {
  for (plan in list(agency(), agency_scenario(), big_plan(100, 8))) {
    d <- plan@data
    total <- sum(d$planned_spend)
    desc <- describe_plan(plan, top_n = 2)

    expect_equal(desc$money$total, total)
    for (col in line_item_grain(plan)) {
      by <- desc$money$spend_by[[col]]
      expect_equal(sum(by$top$spend) + by$other$spend, total, tolerance = 1e-9)
      expect_identical(nrow(by$top) + by$other$n_values,
                       length(unique(d[[col]])))
    }

    c <- desc$commitments
    expect_equal(c$committed + c$floor_locked + c$headroom, total)
    expect_lte(c$flexible, c$headroom)

    expect_equal(sum(desc$time$spend), total)
    expect_identical(desc$shape$n_rows, nrow(d))
    expect_identical(desc$shape$n_line_items, nrow(line_item_summary(plan)))
  }
})

test_that("commitments are read from the bounds", {
  c <- describe_plan(agency())$commitments
  expect_equal(c$committed, 360000)          # the upfront line
  expect_equal(c$floor_locked, 6 * 15000)    # DSP B's floor, six months
  expect_identical(c$n_bounded_line_items, 3L)

  none <- describe_plan(std_plan())$commitments
  expect_equal(none$headroom, 160)
  expect_equal(none$committed + none$floor_locked, 0)
})

test_that("units are totalled by type with a blended rate", {
  u <- describe_plan(agency())$units
  d <- agency()@data
  expect_identical(u$unit_type, "impression")
  expect_equal(u$planned_units, round(sum(d$planned_units), 2))
  expect_equal(u$rate, round(sum(d$planned_spend) * 1000 / sum(d$planned_units), 4))
  expect_identical(nrow(describe_plan(std_plan())$units), 0L)
})

# ---- identity, structure, time -----------------------------------------------

test_that("a scenario names its parent, its author and the ops that made it", {
  id <- describe_plan(agency_scenario())$identity
  expect_identical(id$parent_id, "plan_agency")
  expect_identical(id$author, "agent")
  expect_identical(as.character(id$edits), c("transfer", "scale"))

  alloc <- build_scenario(std_plan(), edits = at_cell(TV = 50), name = "a")
  expect_identical(as.character(describe_plan(alloc)$identity$edits),
                   "allocation")
})

test_that("a topline lists the cells its subplans own", {
  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  shape <- describe_plan(attach_subplan(std_plan(), tv))$shape
  expect_true(shape$is_topline)
  expect_identical(as.character(shape$subplan_cells), "TV")
})

test_that("a plan of moments is described on its own clock", {
  spots <- media_plan_from_flights(
    data.frame(channel = "TV", programme = c("Final", "Late"),
               flight_start = c("2026-02-08 20:00:00", "2026-02-28 23:30:00"),
               flight_end   = c("2026-02-08 20:00:30", "2026-03-01 00:30:00"),
               planned_spend = c(450000, 90000)),
    grain = c("channel", "programme"), basis = "instant",
    tz = "America/New_York", name = "spots")
  desc <- describe_plan(spots)
  expect_identical(desc$shape$tz, "America/New_York")
  expect_identical(desc$shape$flight_start, "2026-02-08 20:00:00")
  expect_identical(desc$shape$flight_end, "2026-03-01 00:30:00")
  expect_identical(desc$time$month, c("2026-02", "2026-03"))
  expect_equal(sum(desc$time$spend), 540000)
})

test_that("targetable values are exactly what a target can name", {
  plan <- agency()
  t <- describe_plan(plan, top_n = 2)$targetable
  expect_identical(as.character(t$values$channel$top),
                   c("Streaming", "Programmatic"))
  expect_identical(t$values$channel$n_more, 1L)
  expect_identical(t$periods$first, "2026-10-01")
  expect_identical(t$periods$n_values, 6L)
  # each listed value builds a scenario when used as a target
  expect_no_error(build_scenario(plan, name = "s", edits = op_delta(
    -100, target = list(channel = as.character(t$values$channel$top[2]),
                        month = t$periods$last))))
})

test_that("top_n must be a whole number of at least 1", {
  expect_error(describe_plan(std_plan(), top_n = 0), "whole number, 1 or more")
  expect_error(describe_plan(std_plan(), top_n = 2.5), "whole number")
})
