# Spend bounds record money that cannot move: a committed upfront, a partner
# floor, a cap. The contract worth pinning: the validator holds
# min <= spend <= max on every row; group edits route around a bound rather
# than through it; edits that name each row's value are refused at a bound;
# bounds follow their rows through every reshaping; and only `rebound` changes
# them.

# A small monthly plan with one of each kind of row:
#   Streaming  committed (min = max = spend)
#   Search     a floor of 15,000 in October, nothing in November
#   Social     a cap of 12,000 in October, nothing in November
bounded_plan <- function() {
  media_plan_from_df(
    data.frame(month = as.Date(c("2026-10-01", "2026-11-01")),
               channel = rep(c("Streaming", "Search", "Social"), each = 2),
               planned_spend = c(60000, 40000, 20000, 20000, 10000, 10000),
               min_spend = c(60000, 40000, 15000, NA, NA, NA),
               max_spend = c(60000, 40000, NA, NA, 12000, NA)),
    grain = "channel", time = "month", name = "bounded")
}

# A weekly plan with one committed four-week flight.
committed_flight <- function() {
  media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-06"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000,
               min_spend = 100000, max_spend = 100000),
    grain = "channel", name = "committed")
}

spend_where <- function(plan, ...) {
  d <- plan@data
  keep <- rep(TRUE, nrow(d))
  sel <- list(...)
  for (nm in names(sel)) keep <- keep & d[[nm]] %in% sel[[nm]]
  d$planned_spend[keep]
}

one_row <- function(...) {
  media_plan_from_df(data.frame(week = fix_week(), channel = "TV", ...),
                     grain = "channel", time = "week", name = "one row")
}

# ---- the validator -----------------------------------------------------------

test_that("the validator holds min <= spend <= max on every row", {
  expect_error(one_row(planned_spend = 50, min_spend = 60),
               "planned_spend is below min_spend on: TV")
  expect_error(one_row(planned_spend = 50, max_spend = 40),
               "planned_spend is above max_spend on: TV")
  expect_error(one_row(planned_spend = 50, min_spend = 60, max_spend = 40),
               "min_spend is above max_spend")
  expect_error(one_row(planned_spend = 50, min_spend = -1),
               "'min_spend' must not be negative")
  expect_error(one_row(planned_spend = 50, max_spend = "lots"),
               "'max_spend' must be numeric")
})

test_that("bounds are met to the cent, and NA means no bound", {
  expect_no_error(one_row(planned_spend = 99.996, min_spend = 100))
  expect_no_error(one_row(planned_spend = 50, min_spend = NA, max_spend = NA))
  p <- one_row(planned_spend = 50, min_spend = NA)
  expect_true(is.numeric(p@data$min_spend))     # an all-NA column is numeric
})

# ---- what a row is committed to ----------------------------------------------

test_that("the commitment label is derived from the bounds", {
  expect_identical(.commitment(bounded_plan()@data),
                   c("committed", "committed", "floor", "flexible",
                     "capped", "flexible"))
  expect_identical(.commitment(std_plan()@data), rep("flexible", 3))
})

test_that("line_item_summary() reports committed spend and headroom", {
  s <- line_item_summary(fix_agency_plan())
  upfront <- s[s$tactic == "Upfront", ]
  expect_equal(upfront$committed_spend, 360000)
  expect_equal(upfront$headroom, 0)
  dsp_b <- s[s$partner == "DSP B", ]
  expect_equal(dsp_b$committed_spend, 6 * 15000)
  expect_equal(dsp_b$headroom, dsp_b$planned_spend - 90000)
  expect_false("committed_spend" %in% names(line_item_summary(std_plan())))
})

# ---- water-filling -----------------------------------------------------------

test_that("with no bounds, a change spreads in plain proportion", {
  expect_equal(.distribute(c(100, 50), -30, weights = c(100, 50)), c(80, 40))
})

test_that("a row that reaches its floor stops, and the rest take up the slack", {
  # -30 each would take the first row to 70, below its floor of 80: it stops
  # at 80, and the 10 it could not give comes out of the second row.
  expect_equal(.distribute(c(100, 100), -60, weights = c(100, 100),
                           lower = c(80, 0)),
               c(80, 60))
})

test_that("a row that reaches its cap stops, and the rest take up the slack", {
  expect_equal(.distribute(c(50, 50), 40, weights = c(50, 50),
                           upper = c(60, Inf)),
               c(60, 80))
})

test_that("a change the bounds cannot absorb errors with what can be absorbed", {
  expect_error(
    .distribute(c(100, 100), -40, weights = c(100, 100), lower = c(80, 90),
                keys = c("A", "B"), what = "`delta` of -40"),
    "`delta` of -40 cannot take 40 out of these rows: their floors leave 30 to give. Floors: A; B")
  expect_error(
    .distribute(c(50, 50), 30, weights = c(50, 50), upper = c(60, 60)),
    "cannot put 30 into these rows: their caps leave room for 20")
})

test_that("rows with room but nothing to spread by cannot take a change", {
  expect_error(.distribute(c(50, 0), 10, weights = c(50, 0), upper = c(50, Inf)),
               "no mix to spread it by")
})

# ---- each edit against committed, floor and capped rows ----------------------

test_that("delta routes around committed rows and stops at floors", {
  p <- bounded_plan()
  s <- build_scenario(p, edits = op_delta(-20000), name = "trim")
  expect_equal(sum(s@data$planned_spend), sum(p@data$planned_spend) - 20000)
  expect_equal(spend_where(s, channel = "Streaming"), c(60000, 40000))
  expect_equal(spend_where(s, channel = "Search")[1], 15000)    # at its floor
  expect_error(build_scenario(p, edits = op_delta(-46000), name = "x"),
               "floors leave 45,000 to give")
})

test_that("delta stops at caps", {
  a <- fix_agency_plan()
  video_a <- list(partner = "Video A")
  s <- build_scenario(a, edits = op_delta(100000, target = video_a),
                      name = "more video")
  capped <- s@data$partner == "Video A" & s@data$tactic == "Prospecting"
  expect_true(all(s@data$planned_spend[capped] <= 60000))
  expect_equal(sum(spend_where(s, partner = "Video A")),
               sum(spend_where(a, partner = "Video A")) + 100000)

  expect_error(
    build_scenario(a, name = "x", edits = op_delta(
      200000, target = list(partner = "Video A", tactic = "Prospecting"))),
    "caps leave room for 150,000")
})

test_that("total respects floors", {
  a <- fix_agency_plan()
  expect_error(
    build_scenario(a, name = "x", edits = op_total(
      50000, target = list(channel = "Programmatic"))),
    "floors leave 420,000 to give")
})

test_that("set, scale and delta_each are refused at a bound, naming the rows", {
  p <- bounded_plan()
  expect_error(
    build_scenario(p, edits = op_scale(0.9, target = list(channel = "Streaming")),
                   name = "x"),
    "`scale` of 0.9 would leave 2 row\\(s\\) outside their bounds: Streaming \\| 2026-10-01 \\(committed\\) at 54,000 \\(min 60,000\\)")
  expect_error(
    build_scenario(p, edits = op_set(10000, target = list(channel = "Search")),
                   name = "x"),
    "Search \\| 2026-10-01 \\(floor\\) at 10,000 \\(min 15,000\\)")
  expect_error(
    build_scenario(p, edits = op_delta_each(5000, target = list(channel = "Social")),
                   name = "x"),
    "Social \\| 2026-10-01 \\(capped\\) at 15,000 \\(max 12,000\\)")
})

test_that("a row with a floor cannot be dropped", {
  expect_error(
    build_scenario(bounded_plan(), name = "x",
                   edits = op_drop(target = list(channel = "Search"))),
    "`drop` would remove row\\(s\\) with a floor: Search \\| 2026-10-01")
  # a row whose only bound is a cap can go
  expect_no_error(build_scenario(
    bounded_plan(), name = "x",
    edits = op_drop(target = list(channel = "Social"))))
})

test_that("an allocation that breaks a bound is refused", {
  p <- bounded_plan()
  alloc <- data.frame(month = as.Date("2026-10-01"), channel = "Streaming",
                      planned_spend = 1000)
  expect_error(build_scenario(p, edits = alloc, name = "x"),
               "the allocation in `edits` would leave 1 row")
  expect_error(build_scenario(p, edits = c("Social | 2026-10-01" = 20000),
                              name = "x"),
               "max 12,000")
})

test_that("a transfer out of a channel routes around its committed line", {
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "s", edits = op_transfer(
    50000, from = list(channel = "Streaming"), to = list(partner = "Video B")))
  upfront <- a@data$tactic == "Upfront"
  expect_identical(s@data$planned_spend[upfront], a@data$planned_spend[upfront])
  expect_equal(sum(spend_where(s, partner = "Stream B")),
               sum(spend_where(a, partner = "Stream B")) - 50000)
  expect_equal(sum(s@data$planned_spend), sum(a@data$planned_spend))
})

test_that("a transfer into a capped line cannot overfill it", {
  expect_error(
    build_scenario(fix_agency_plan(), name = "s", edits = op_transfer(
      200000, from = list(partner = "DSP A"),
      to = list(partner = "Video A", tactic = "Prospecting"))),
    "`to`: `transfer` of 200,000 cannot put 200,000 into these rows")
})

# ---- bounds follow their rows ------------------------------------------------

test_that("a flight's bounds are spread across its periods like its spend", {
  p <- committed_flight()
  expect_equal(p@data$min_spend, p@data$planned_spend)
  expect_equal(p@data$max_spend, p@data$planned_spend)
  expect_true(all(.commitment(p@data) == "committed"))
})

test_that("bounds move with a flight shifted by whole periods", {
  s <- build_scenario(committed_flight(), edits = op_shift(7), name = "later")
  expect_equal(s@data$week, as.Date("2026-04-13") + 7 * 0:3)
  expect_true(all(.commitment(s@data) == "committed"))
})

test_that("a bounded flight cannot move onto a different period structure", {
  expect_error(build_scenario(committed_flight(), edits = op_shift(3), name = "x"),
               "bound by min/max spend.*7\\+7\\+7\\+7 days becomes 4\\+7\\+7\\+7\\+3")
  expect_error(
    build_scenario(committed_flight(), name = "x",
                   edits = op_restage("2026-05-04", "2026-05-24")),
    "bound by min/max spend")
  # without its bounds it moves freely
  expect_no_error(build_scenario(committed_flight(), name = "x", edits = list(
    op_rebound(min = NA, max = NA), op_shift(3))))
})

test_that("add can bring bounds with a new line item", {
  s <- build_scenario(std_plan(), name = "s", edits = op_add(
    channel = "Audio", week = "2026-07-06", planned_spend = 25,
    min_spend = 25, max_spend = 25))
  expect_true(all(bound_cols() %in% names(s@data)))
  expect_identical(.commitment(s@data),
                   c("flexible", "flexible", "flexible", "committed"))

  # a flight's bounds cover the whole buy
  s <- build_scenario(weekly_plan(), name = "s", edits = op_add(
    channel = "Audio", partner = "Spotify", flight_start = "2026-04-08",
    flight_end = "2026-04-19", planned_spend = 1200, min_spend = 1200))
  audio <- s@data$channel == "Audio"
  expect_equal(s@data$min_spend[audio], s@data$planned_spend[audio])
  expect_error(op_add(channel = "Audio", week = "2026-07-06",
                      planned_spend = 5, min_spend = -1),
               "add\\$min_spend` must be 0 or more")
})

test_that("snapping an even flight to the cent never crosses a bound", {
  # An even three-day flight holding a third each, not yet snapped to cents,
  # with a floor at exactly what it holds. Snapping would give
  # 33.34 / 33.33 / 33.33 and take two days below their floor.
  third <- 100 / 3
  flight <- data.frame(
    day = as.Date("2026-04-06") + 0:2, channel = "OOH", planned_spend = third,
    flight_id = "fl_ooh", flight_start = as.Date("2026-04-06"),
    flight_end = as.Date("2026-04-08"), period_basis = "flight",
    pacing = "even", min_spend = third)
  other <- data.frame(day = as.Date("2026-04-06"), channel = "TV",
                      planned_spend = 50, flight_id = NA,
                      flight_start = as.Date(NA), flight_end = as.Date(NA),
                      period_basis = NA, pacing = NA, min_spend = NA)
  build <- function(df) {
    p <- media_plan_from_df(df, grain = "channel", time = "day", name = "p")
    build_scenario(p, edits = op_scale(2, target = list(channel = "TV")),
                   name = "touch TV")
  }

  floored <- build(rbind(flight, other))
  expect_equal(spend_where(floored, channel = "OOH"), rep(third, 3))

  free <- build(rbind(transform(flight, min_spend = NA), other))
  expect_equal(spend_where(free, channel = "OOH"), c(33.34, 33.33, 33.33))
})

test_that("roll_up() sums floors and caps", {
  r <- roll_up(fix_agency_plan(), "channel")
  oct <- r@data$month == as.Date("2026-10-01")
  at <- function(ch, col) r@data[[col]][oct & r@data$channel == ch]
  # Streaming: Stream A's committed 72,000 floor; Stream B has none
  expect_equal(at("Streaming", "min_spend"), 72000)
  expect_true(is.na(at("Streaming", "max_spend")))   # one uncapped line: no cap
  expect_equal(at("Programmatic", "min_spend"), 15000)
  expect_true(is.na(at("Online Video", "min_spend")))
})

test_that("calendarize() splits bounds by the same days as spend", {
  cal <- calendarize(fix_agency_plan(), "week")
  upfront <- cal[cal$tactic == "Upfront", ]
  expect_equal(upfront$min_spend, upfront$planned_spend)
  expect_equal(upfront$max_spend, upfront$planned_spend)
  expect_equal(sum(cal$min_spend, na.rm = TRUE),
               sum(fix_agency_plan()@data$min_spend, na.rm = TRUE))
})

test_that("a subplan's rollup carries its summed bounds onto the topline", {
  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50), min_spend = c(70, 20),
               max_spend = c(70, NA)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  top <- attach_subplan(std_plan(), tv)
  d <- top@data
  expect_equal(d$min_spend[d$channel == "TV"], 90)
  expect_true(is.na(d$max_spend[d$channel == "TV"]))
  expect_true(all(is.na(d$min_spend[d$channel != "TV"])))
})

test_that("bounds survive a JSON round trip", {
  a <- fix_agency_plan()
  back <- plan_from_json(plan_to_json(a))
  expect_equal(back@data$min_spend, a@data$min_spend)
  expect_equal(back@data$max_spend, a@data$max_spend)

  # a column with no bounds in it comes back numeric, not logical
  p <- one_row(planned_spend = 50, min_spend = NA)
  expect_true(is.numeric(plan_from_json(plan_to_json(p))@data$min_spend))
})

test_that("comparing scenarios is unaffected by bounds", {
  a <- fix_agency_plan(name = "base")
  s <- build_scenario(a, name = "s", nickname = "moved", edits = op_transfer(
    10000, from = list(partner = "DSP A"), to = list(partner = "Video B")))
  cmp <- compare_scenarios(add_scenario(scenario_set(a), s), "summary")
  expect_equal(cmp$total_planned_spend[cmp$scenario == "moved"],
               sum(a@data$planned_spend))
  expect_equal(cmp$spend_vs_base[cmp$scenario == "moved"], 0)
})

# ---- rebound -----------------------------------------------------------------

test_that("rebound lowers a commitment so the line can then be cut", {
  p <- bounded_plan()
  nov <- list(channel = "Streaming", month = "2026-11-01")
  s <- build_scenario(p, name = "renegotiated", edits = list(
    op_rebound(min = 30000, target = nov),
    op_delta(-10000, target = nov)))
  expect_equal(spend_where(s, channel = "Streaming"), c(60000, 30000))
  expect_equal(s@data$min_spend[s@data$channel == "Streaming"], c(60000, 30000))
})

test_that("rebound changes bounds and no spend", {
  p <- bounded_plan()
  s <- build_scenario(p, name = "uncap",
                      edits = op_rebound(max = NA, target = list(channel = "Social")))
  expect_identical(s@data$planned_spend, p@data$planned_spend)
  expect_true(all(is.na(s@data$max_spend[s@data$channel == "Social"])))
  # a bound left out is untouched
  expect_identical(s@data$min_spend, p@data$min_spend)
})

test_that("rebound brings the bound columns to a plan that had none", {
  s <- build_scenario(std_plan(), name = "s",
                      edits = op_rebound(min = 40, target = list(channel = "Search")))
  expect_equal(s@data$min_spend, c(NA, 40, NA))
  expect_true(all(is.na(s@data$max_spend)))
})

test_that("rebound refuses bounds that would exclude the spend already planned", {
  expect_error(
    build_scenario(bounded_plan(), name = "x",
                   edits = op_rebound(min = 30000, target = list(channel = "Social"))),
    "`rebound` would leave 2 row\\(s\\) outside their bounds.*Choose bounds that contain")
  expect_error(op_rebound(min = 50, max = 40), "`rebound\\$min` \\(50\\) is above")
  expect_error(op_rebound(), "naming `min` and/or `max`")
  expect_error(op_rebound(floor = 5), "unused argument")
})

test_that("a JSON null removes a bound", {
  ops <- jsonlite::fromJSON(
    '[{"rebound": {"max": null}, "target": {"channel": "Social"}}]',
    simplifyVector = FALSE)
  s <- build_scenario(bounded_plan(), edits = ops, name = "s")
  expect_true(all(is.na(s@data$max_spend)[s@data$channel == "Social"]))
})
