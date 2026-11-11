# transfer moves money from one set of rows to another and leaves the plan's
# total where it was. The contract worth pinning: it is budget-neutral at any
# grain, the source keeps its mix, a destination that plans nothing fills the
# way an even flight would, and every refusal names what to do instead.

oct <- list(from = "2026-10-01", to = "2026-10-31")
mar <- list(from = "2027-03-01", to = "2027-03-31")

# The planned spend on the rows matching column = value(s).
spend_of <- function(plan, ...) {
  d <- plan@data
  keep <- rep(TRUE, nrow(d))
  for (nm in names(list(...))) keep <- keep & d[[nm]] %in% list(...)[[nm]]
  sum(d$planned_spend[keep])
}

total_of <- function(plan) sum(plan@data$planned_spend)

# A weekly flighted plan: TV and Search are bought, OOH is a flight held at
# zero that starts on a Wednesday, so its first week is five days long.
flights_plan <- function() {
  media_plan_from_flights(
    data.frame(channel = c("TV", "OOH", "Search"),
               flight_start = as.Date(c("2026-04-06", "2026-04-08", "2026-04-06")),
               flight_end   = as.Date(c("2026-05-03", "2026-05-03", "2026-04-19")),
               planned_spend = c(10000, 0, 4000)),
    grain = "channel", name = "Base", nickname = "base")
}

# ---- budget neutrality -------------------------------------------------------

test_that("a transfer leaves the plan's total unchanged, at any grain", {
  s <- build_scenario(std_plan(), name = "s", edits = op_transfer(
    30, from = list(channel = "TV"), to = list(channel = "Search")))
  expect_equal(total_of(s), 160)
  expect_equal(spend_of(s, channel = "TV"), 50)
  expect_equal(spend_of(s, channel = "Search"), 70)

  # the two sides may be named at different columns of the grain
  s <- build_scenario(fine_plan(), name = "s", edits = op_transfer(
    20, from = list(partner = "A"), to = list(channel = "Social")))
  expect_equal(total_of(s), 160)
  expect_equal(spend_of(s, partner = "A"), 30)
  expect_equal(spend_of(s, channel = "Social"), 60)

  a <- fix_agency_plan()
  s <- build_scenario(a, name = "s", edits = op_transfer(
    37419, from = list(partner = "DSP A"),
    to = list(channel = "Streaming", tactic = "Regional")))
  expect_equal(total_of(s), total_of(a))
  expect_equal(spend_of(s, partner = "DSP A"),
               spend_of(a, partner = "DSP A") - 37419)
  expect_equal(spend_of(s, channel = "Streaming", tactic = "Regional"),
               spend_of(a, channel = "Streaming", tactic = "Regional") + 37419)
})

# ---- how the money is spread -------------------------------------------------

test_that("the source gives in proportion, keeping its mix", {
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "s", edits = op_transfer(
    36000, from = list(partner = "DSP A"), to = list(partner = "Video A")))
  src <- a@data$partner == "DSP A"                    # 360,000 across 12 rows
  expect_equal(s@data$planned_spend[src],
               a@data$planned_spend[src] * (1 - 36000 / 360000))
})

test_that("a destination that plans something receives in proportion", {
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "s", edits = op_transfer(
    36000, from = list(partner = "DSP A"), to = list(partner = "Video A")))
  dst <- a@data$partner == "Video A"                  # 210,600 across 12 rows
  expect_equal(s@data$planned_spend[dst],
               a@data$planned_spend[dst] * (1 + 36000 / 210600))
})

test_that("a destination that plans nothing fills evenly by in-market days", {
  # weekly, with a ragged first week: 5 days, then 7, 7, 7
  s <- build_scenario(flights_plan(), name = "s", edits = op_transfer(
    2600, from = list(channel = "TV"), to = list(channel = "OOH")))
  expect_equal(s@data$planned_spend[s@data$channel == "OOH"],
               c(500, 700, 700, 700))

  # daily: every row is one day
  daily <- media_plan_from_df(
    data.frame(day = rep(as.Date("2026-04-06") + 0:2, 2),
               channel = rep(c("TV", "OOH"), each = 3),
               planned_spend = c(100, 100, 100, 0, 0, 0)),
    grain = "channel", time = "day", name = "daily")
  s <- build_scenario(daily, name = "s", edits = op_transfer(
    90, from = list(channel = "TV"), to = list(channel = "OOH")))
  expect_equal(s@data$planned_spend[s@data$channel == "OOH"], c(30, 30, 30))

  # monthly: Oct-Mar is 31 + 30 + 31 + 31 + 28 + 31 = 182 days, so 100 a day
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "s", edits = op_transfer(
    18200, from = list(partner = "Stream B"), to = list(partner = "Video B")))
  expect_equal(s@data$planned_spend[s@data$partner == "Video B"],
               c(3100, 3000, 3100, 3100, 2800, 3100))
})

# ---- choosing the two sides --------------------------------------------------

test_that("per-side windows move money within one line item", {
  a <- fix_agency_plan()
  line <- list(partner = "Stream B", tactic = "Prospecting")
  s <- build_scenario(a, name = "Oct to Mar", edits = op_transfer(
    5000, from = line, to = line, from_during = oct, to_during = mar))

  is_line <- a@data$partner == "Stream B" & a@data$tactic == "Prospecting"
  month   <- format(a@data$month, "%m")
  change  <- s@data$planned_spend - a@data$planned_spend
  expect_equal(change[is_line & month == "10"], -5000)
  expect_equal(change[is_line & month == "03"], 5000)
  expect_equal(sum(abs(change[!(is_line & month %in% c("10", "03"))])), 0)
})

test_that("a shared window narrows both sides", {
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "October only", edits = op_transfer(
    6000, from = list(partner = "DSP A"), to = list(partner = "Video A"),
    during = oct))
  changed <- s@data$planned_spend != a@data$planned_spend
  expect_true(all(format(a@data$month[changed], "%m") == "10"))
  expect_equal(total_of(s), total_of(a))
})

test_that("a shared window and a per-side window cannot both be given", {
  expect_error(
    op_transfer(1, from = list(channel = "TV"), to = list(channel = "Search"),
                during = oct, from_during = oct),
    "give `during` or `from_during`, not both")
  # the same check on a hand-written op
  expect_error(
    build_scenario(std_plan(), name = "s", edits = list(
      transfer = 1, from = list(channel = "TV"), to = list(channel = "Search"),
      during = oct, to_during = oct)),
    "give `during` or `to_during`, not both")
})

# ---- refusals ----------------------------------------------------------------

test_that("the two sides must not share a row", {
  expect_error(
    build_scenario(fine_plan(), name = "s", edits = op_transfer(
      10, from = list(channel = "TV"), to = list(partner = "A"))),
    "`from` and `to` share 1 row")
})

test_that("a source cannot give more than it holds", {
  expect_error(
    build_scenario(std_plan(), name = "s", edits = op_transfer(
      81, from = list(channel = "TV"), to = list(channel = "Search"))),
    "more than `from` holds: it plans 80")
})

test_that("asking for all of a fractional source, to the cent, moves all of it", {
  thirds <- build_scenario(std_plan(), edits = op_scale(1 / 3), name = "thirds")
  tv <- spend_of(thirds, channel = "TV")              # 26.666...
  s <- build_scenario(thirds, name = "s", edits = op_transfer(
    26.67, from = list(channel = "TV"), to = list(channel = "Search")))
  expect_equal(spend_of(s, channel = "TV"), 0)
  expect_equal(total_of(s), total_of(thirds))
})

test_that("a destination not in the plan errors naming add", {
  expect_error(
    build_scenario(std_plan(), name = "s", edits = op_transfer(
      10, from = list(channel = "TV"), to = list(channel = "Audio"))),
    "`to`: no such value.*Audio.*`add` it first")
})

test_that("adding the destination earlier in the same edits makes it legal", {
  s <- build_scenario(std_plan(), name = "s", edits = list(
    op_add(channel = "Audio", week = "2026-07-06", planned_spend = 0),
    op_transfer(25, from = list(channel = "TV"), to = list(channel = "Audio"))))
  expect_equal(spend_of(s, channel = "Audio"), 25)
  expect_equal(total_of(s), 160)
})

test_that("rows a subplan owns are read-only on either side", {
  tv_detail <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  topline <- attach_subplan(std_plan(), tv_detail)

  expect_error(
    build_scenario(topline, name = "s", edits = op_transfer(
      10, from = list(channel = "TV"), to = list(channel = "Search"))),
    "is planned in a subplan")
  expect_error(
    build_scenario(topline, name = "s", edits = op_transfer(
      10, from = list(channel = "Search"), to = list(channel = "TV"))),
    "is planned in a subplan")
})

# ---- what follows the money --------------------------------------------------

test_that("units follow the money at the held rate", {
  a <- fix_agency_plan()
  s <- build_scenario(a, name = "s", edits = op_transfer(
    36000, from = list(partner = "DSP A"), to = list(partner = "Video A")))
  expect_identical(s@data$planned_rate, a@data$planned_rate)
  expect_equal(s@data$planned_units,
               s@data$planned_spend * 1000 / s@data$planned_rate)
})

test_that("flights stay evenly paced, and compare as resized", {
  base <- flights_plan()
  s <- build_scenario(base, name = "Moved", nickname = "moved", edits = list(
    op_transfer(2600, from = list(channel = "TV"), to = list(channel = "OOH")),
    op_transfer(1000, from = list(channel = "TV"), to = list(channel = "Search"))))
  expect_true(all(flights(s)$pacing == "even"))

  cmp <- compare_scenarios(add_scenario(scenario_set(base), s), "flight")
  moved <- cmp[cmp$scenario == "moved", ]
  expect_true(all(moved$change == "resized"))
  expect_setequal(moved$flight_id, flights(base)$flight_id)
  expect_equal(moved$spend_vs_base[match(c("TV", "OOH", "Search"), moved$channel)],
               c(-3600, 2600, 1000))
})

test_that("an op that only moves money is checked to leave the total alone", {
  expect_silent(.stop_if_total_changed(c(1, 2), c(1.004, 1.9999), "transfer"))
  expect_error(.stop_if_total_changed(c(1, 2), c(1, 2.01), "transfer"),
               "internal.*bug in mediaplanr")
})
