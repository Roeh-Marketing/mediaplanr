# Spend, units and rate are bound by one identity. The contract worth pinning:
# a plan can be authored from any two of the three, the stored set is always
# self-consistent, and the RATE is what survives an edit -- a cut budget buys
# fewer impressions, it does not win a better CPM.

social <- function(...) {
  media_plan_from_df(
    data.frame(channel = "Social", unit_type = "impression", ...,
               stringsAsFactors = FALSE),
    grain = "channel", name = "social")
}

two_channel <- function() {
  media_plan_from_df(
    data.frame(channel = c("Social", "Search"),
               unit_type = c("impression", "click"),
               planned_spend = c(140000, 95000),
               planned_rate  = c(5, 0.80),
               stringsAsFactors = FALSE),
    grain = "channel", name = "two")
}

# ---- authoring ---------------------------------------------------------------

test_that("any two of spend, units and rate give the same stored plan", {
  from_rate  <- social(planned_spend = 140000, planned_rate = 5)
  from_units <- social(planned_units = 28000000, planned_rate = 5)
  from_both  <- social(planned_spend = 140000, planned_units = 28000000)

  for (p in list(from_rate, from_units, from_both)) {
    expect_equal(p@data$planned_spend, 140000)
    expect_equal(p@data$planned_units, 28000000)
    expect_equal(p@data$planned_rate, 5)
  }
})

test_that("impressions are priced per thousand and everything else per unit", {
  imp <- social(planned_spend = 140000, planned_units = 28000000)
  expect_equal(imp@data$planned_rate, 5)              # a CPM
  clk <- media_plan_from_df(
    data.frame(channel = "Search", unit_type = "click",
               planned_spend = 95000, planned_units = 118750),
    grain = "channel", name = "clicks")
  expect_equal(clk@data$planned_rate, 0.80)           # a CPC, per single click
})

test_that("an unknown unit type is accepted and priced per single unit", {
  p <- media_plan_from_df(
    data.frame(channel = "New", unit_type = "attention_second",
               planned_spend = 1000, planned_units = 500),
    grain = "channel", name = "novel")
  expect_equal(p@data$planned_rate, 2)
  expect_false("attention_second" %in% unit_type_levels())
})

test_that("spend may be omitted when units and a rate can produce it", {
  p <- media_plan_from_df(
    data.frame(channel = "Social", unit_type = "impression",
               planned_units = 28000000, planned_rate = 5),
    grain = "channel", name = "no spend column")
  expect_equal(p@data$planned_spend, 140000)
})

test_that("only one of the three may be missing", {
  expect_error(
    media_plan_from_df(
      data.frame(channel = "Social", unit_type = "impression",
                 planned_units = 28000000),
      grain = "channel", name = "one only"),
    "not found in `df`")
})

test_that("the columns can be named anything and are renamed", {
  p <- media_plan_from_df(
    data.frame(channel = "Social", medium = "impression",
               budget = 140000, cpm = 5),
    grain = "channel", planned_spend = "budget",
    planned_rate = "cpm", unit_type = "medium", name = "renamed")
  expect_equal(p@data$planned_units, 28000000)
  expect_true(all(c("unit_type", "planned_rate") %in% names(p@data)))
})

test_that("a plan that records no units is entirely unaffected", {
  p <- std_plan()
  expect_false(any(unit_cols() %in% names(p@data)))
  expect_true(all(is.na(cost_per_unit(p))))
})

# ---- the identity is enforced ------------------------------------------------

test_that("an inconsistent trio is rejected", {
  p <- two_channel()
  d <- p@data
  d$planned_units[1] <- 999
  expect_error(MediaPlan(data = d, grain = p@grain, name = "bad"),
               "does not equal planned_spend")
})

test_that("negative units or rates are rejected", {
  expect_error(social(planned_spend = 100, planned_rate = -5), "not be negative")
  expect_error(
    MediaPlan(data = data.frame(channel = "TV", planned_spend = 100,
                                planned_units = -5, planned_rate = 20),
              grain = "channel", name = "bad"),
    "not be negative")
})

# ---- editing: the rate holds -------------------------------------------------

test_that("cutting the budget buys fewer units at the same rate", {
  p <- two_channel()
  s <- build_scenario(p, edits = list(target = list(channel = "Social"),
                                      delta = -40000), name = "cut")
  i <- s@data$channel == "Social"
  expect_equal(s@data$planned_spend[i], 100000)
  expect_equal(s@data$planned_units[i], 20000000)   # units follow
  expect_equal(s@data$planned_rate[i], 5)           # rate holds
})

test_that("scaling and re-totalling hold every rate", {
  p <- two_channel()
  for (e in list(list(scale = 0.5), list(total = 500000),
                 list(target = list(channel = "Search"), set = 10000))) {
    s <- build_scenario(p, edits = e, name = "x")
    expect_equal(s@data$planned_rate, p@data$planned_rate)
  }
})

test_that("units stay consistent with spend through any edit", {
  s <- build_scenario(two_channel(), edits = list(scale = 0.37), name = "odd")
  rp <- .rate_per(s@data$unit_type)
  expect_equal(s@data$planned_units * s@data$planned_rate / rp,
               s@data$planned_spend)
})

test_that("a row with no rate keeps its units rather than being guessed at", {
  p <- media_plan_from_df(
    data.frame(channel = c("TV", "Bonus"), unit_type = c("grp", "impression"),
               planned_spend = c(100, 0), planned_units = c(50, 1000000)),
    grain = "channel", name = "with bonus")
  expect_equal(p@data$planned_units[p@data$channel == "Bonus"], 1000000)
  s <- build_scenario(p, edits = list(target = list(channel = "TV"),
                                      scale = 2), name = "x")
  expect_equal(s@data$planned_units[s@data$channel == "Bonus"], 1000000)
})

# ---- aggregation -------------------------------------------------------------

test_that("roll_up sums units within a type and blends the rate", {
  p <- media_plan_from_df(
    data.frame(channel = "Social", partner = c("Meta", "TikTok"),
               unit_type = "impression", planned_spend = c(140000, 60000),
               planned_rate = c(5, 4)),
    grain = c("channel", "partner"), name = "two partners")
  r <- roll_up(p, "channel")@data
  expect_equal(r$planned_units, 43000000)
  expect_equal(r$planned_rate, 200000 / 43000000 * 1000)
  expect_identical(r$unit_type, "impression")
})

test_that("rolling across mixed unit types keeps spend and drops units", {
  p <- media_plan_from_df(
    data.frame(bucket = "all", channel = c("Social", "Search"),
               unit_type = c("impression", "click"),
               planned_spend = c(140000, 95000), planned_rate = c(5, 0.8)),
    grain = c("bucket", "channel"), name = "mixed")
  r <- roll_up(p, "bucket")@data
  expect_equal(r$planned_spend, 235000)             # the common currency stays
  expect_true(is.na(r$planned_units))               # GRPs plus clicks mean nothing
  expect_true(is.na(r$unit_type))
})

test_that("a flight's units follow each week's share of the spend", {
  p <- media_plan_from_flights(
    data.frame(channel = "Social", unit_type = "impression", planned_rate = 5,
               flight_start = as.Date("2026-04-06"),
               flight_end   = as.Date("2026-05-03"), planned_spend = 140000),
    grain = "channel", name = "flighted")
  expect_equal(sum(p@data$planned_units), 28000000)
  expect_equal(unique(p@data$planned_units), 7000000)   # not repeated whole
  expect_equal(unique(p@data$planned_rate), 5)
})

test_that("calendarize carries units and the rate", {
  p <- media_plan_from_flights(
    data.frame(channel = "Social", unit_type = "impression", planned_rate = 5,
               flight_start = as.Date("2026-04-20"),
               flight_end   = as.Date("2026-05-10"), planned_spend = 210000),
    grain = "channel", name = "straddles")
  r <- calendarize(p, "month")
  expect_equal(r$planned_units, c(22000000, 20000000))
  expect_equal(unique(r$planned_rate), 5)
  expect_equal(sum(r$planned_units), 42000000)
})

test_that("line_item_summary reports what each line item buys", {
  s <- line_item_summary(two_channel())
  expect_true(all(c("unit_type", "planned_units", "planned_rate") %in% names(s)))
  expect_equal(s$planned_rate[s$channel == "Social"], 5)
})

# ---- derived rates -----------------------------------------------------------

test_that("cost_per_unit and cpm derive from spend and units", {
  p <- two_channel()
  expect_equal(cost_per_unit(p), c(140000 / 28000000, 0.80))
  expect_equal(cpm(p), c(5, 800))
})

test_that("cost_per_unit rejects anything that is not a plan", {
  expect_error(cost_per_unit(weekly_df()), "must be a MediaPlan")
})

# ---- print -------------------------------------------------------------------

test_that("print reports units by type with the blended rate", {
  out <- paste(utils::capture.output(print(two_channel())), collapse = "\n")
  expect_match(out, "units       click")
  expect_match(out, "@ 5.00 CPM")           # impressions are quoted per thousand
  expect_match(out, "@ 0.80")               # clicks are not
  # the unit columns are summarised, not repeated down the preview
  expect_false(grepl("planned_rate", out))
})

test_that("a plan with no units shows no units line", {
  expect_false(grepl("units", paste(utils::capture.output(print(std_plan())),
                                    collapse = "\n")))
})
