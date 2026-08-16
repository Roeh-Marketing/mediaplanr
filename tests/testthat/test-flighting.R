# Flights are how a buy is authored; weeks are how the plan is held. The
# contract worth pinning: the expansion is exact to the cent, the inverse is
# exact rather than inferred, and a plan that records no flights says so instead
# of guessing.

flight_df <- function() {
  data.frame(
    channel       = c("OOH", "Search", "TV"),
    partner       = c("JCDecaux", "Google", "NBC"),
    flight_start  = as.Date(c("2026-04-06", "2026-04-08", "2026-04-06")),
    flight_end    = as.Date(c("2026-05-03", "2026-04-08", "2026-04-12")),
    planned_spend = c(120000, 3100, 33333),
    stringsAsFactors = FALSE
  )
}

flight_plan <- function(name = "flights") {
  media_plan_from_flights(flight_df(), grain = c("channel", "partner"),
                          name = name)
}

# ---- expansion ---------------------------------------------------------------

test_that("a flight expands to one row per week it touches", {
  d <- flight_plan()@data
  expect_identical(nrow(d), 6L)                      # 4 + 1 + 1
  ooh <- d[d$channel == "OOH", ]
  expect_identical(nrow(ooh), 4L)
  expect_identical(ooh$week, as.Date(c("2026-04-06", "2026-04-13",
                                       "2026-04-20", "2026-04-27")))
})

test_that("the weekly rows re-sum to the flight total, exactly to the cent", {
  p <- flight_plan()
  # 33333 over 7 days does not divide evenly; this is the case that fails with
  # naive proportional splitting
  expect_identical(sum(round(p@data$planned_spend * 100)),
                   sum(round(flight_df()$planned_spend * 100)))
  expect_equal(sum(p@data$planned_spend), sum(flight_df()$planned_spend))
})

test_that("a ragged flight splits by days, not evenly across weeks", {
  # Wed 2026-04-08 to Sun 2026-05-03: 5 days, then 7, 7, 7
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000),
    grain = "channel", name = "ragged")
  expect_identical(p@data$planned_spend,
                   c(19230.77, 26923.08, 26923.08, 26923.07))
  expect_equal(sum(p@data$planned_spend), 100000)
})

test_that("every allocated week is a whole number of cents", {
  d <- flight_plan()@data
  expect_identical(d$planned_spend, round(d$planned_spend, 2))
})

test_that("a row's span is clipped to its flight at both ragged ends", {
  p <- flight_plan()
  span <- .row_span(p)
  # the single-day Search buy sits in the week of 2026-04-06 but spans one day
  i <- which(p@data$channel == "Search")
  expect_identical(span$start[i], as.Date("2026-04-08"))
  expect_identical(span$end[i], as.Date("2026-04-08"))
  # the OOH flight's last week is clipped to the flight end
  j <- which(p@data$channel == "OOH" & p@data$week == as.Date("2026-04-27"))
  expect_identical(span$end[j], as.Date("2026-05-03"))
})

test_that("the flight window reflects the clipped spans", {
  p <- flight_plan()
  expect_identical(p@flight_start, as.Date("2026-04-06"))
  expect_identical(p@flight_end, as.Date("2026-05-03"))
})

test_that("the cadence of each flight is inferred when not supplied", {
  d <- flight_plan()@data
  expect_identical(unique(d$period_basis[d$channel == "OOH"]), "flight")
  expect_identical(unique(d$period_basis[d$channel == "Search"]), "day")
  expect_identical(unique(d$period_basis[d$channel == "TV"]), "week")
})

test_that("week_start controls where weeks break", {
  p <- media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-04-14"), planned_spend = 700),
    grain = "channel", name = "sunday", week_start = "Sunday")
  expect_identical(week_start(p), "Sunday")
  expect_identical(p@data$week, as.Date(c("2026-04-05", "2026-04-12")))
})

# ---- the inverse -------------------------------------------------------------

test_that("flights() recovers exactly what was authored", {
  fl <- flights(flight_plan())
  expect_identical(nrow(fl), 3L)
  ooh <- fl[fl$channel == "OOH", ]
  expect_identical(ooh$flight_start, as.Date("2026-04-06"))
  expect_identical(ooh$flight_end, as.Date("2026-05-03"))
  expect_identical(ooh$planned_spend, 120000)
  expect_identical(ooh$n_weeks, 4L)
})

test_that("flights() totals reconcile with the plan", {
  p <- flight_plan()
  expect_equal(sum(flights(p)$planned_spend), sum(p@data$planned_spend))
})

test_that("a plan with no recorded flights reports none rather than guessing", {
  # four equal weeks are indistinguishable from one flight; do not infer
  p <- media_plan_from_df(
    data.frame(week = seq(as.Date("2026-04-06"), by = "week", length.out = 4),
               channel = "TV", planned_spend = rep(30000, 4)),
    grain = c("channel", "week"), week = "week", name = "weekly")
  fl <- flights(p)
  expect_identical(nrow(fl), 0L)
  expect_true("planned_spend" %in% names(fl))
})

test_that("flights survive a scenario derivation", {
  p <- flight_plan()
  s <- build_scenario(p, edits = list(target = list(channel = "OOH"),
                                      scale = 0.5), name = "OOH -50%")
  expect_identical(nrow(flights(s)), 3L)
  expect_equal(flights(s)$planned_spend[flights(s)$channel == "OOH"], 60000)
})

# ---- pacing ------------------------------------------------------------------

test_that("an imported flight is evenly paced", {
  expect_identical(unique(flights(flight_plan())$pacing), "even")
})

test_that("scaling a whole flight keeps it even -- only the amount changed", {
  p <- flight_plan()
  s <- build_scenario(p, edits = list(target = list(channel = "OOH"),
                                      scale = 0.5), name = "half")
  fl <- flights(s)
  expect_identical(fl$pacing[fl$channel == "OOH"], "even")
  expect_equal(fl$planned_spend[fl$channel == "OOH"], 60000)
})

test_that("setting a flight's total keeps it even", {
  p <- flight_plan()
  s <- build_scenario(p, edits = list(target = list(channel = "OOH"),
                                      total = 90000), name = "retotal")
  fl <- flights(s)
  expect_identical(fl$pacing[fl$channel == "OOH"], "even")
  expect_equal(fl$planned_spend[fl$channel == "OOH"], 90000)
})

test_that("editing one week of a flight makes it custom but keeps the flight", {
  p <- flight_plan()
  key <- line_item(p@data, p@grain)[1]          # first OOH week
  s <- build_scenario(p, edits = stats::setNames(50000, key), name = "hand shaped")
  fl <- flights(s)
  expect_identical(fl$pacing[fl$channel == "OOH"], "custom")
  # the buy is still one buy, with its dates and its new total intact
  expect_identical(fl$n_weeks[fl$channel == "OOH"], 4L)
  expect_identical(fl$flight_end[fl$channel == "OOH"], as.Date("2026-05-03"))
  expect_equal(fl$planned_spend[fl$channel == "OOH"], 50000 + 30000 * 3)
})

test_that("a flat delta across unequal weeks makes it custom", {
  # 5+7+7+7 days: a flat per-row delta cannot stay proportional to days
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000),
    grain = "channel", name = "ragged")
  expect_identical(flights(p)$pacing, "even")
  s <- build_scenario(p, edits = list(delta = 1000), name = "flat add")
  expect_identical(flights(s)$pacing, "custom")
})

test_that("pacing is derived, so shaping a flight back to even reports even", {
  p <- flight_plan()
  key <- line_item(p@data, p@grain)[1]
  bent <- build_scenario(p, edits = stats::setNames(50000, key), name = "bent")
  expect_identical(flights(bent)$pacing[flights(bent)$channel == "OOH"], "custom")
  back <- build_scenario(bent, edits = stats::setNames(30000, key), name = "back")
  expect_identical(flights(back)$pacing[flights(back)$channel == "OOH"], "even")
})

test_that("editing one flight does not repace another", {
  p <- flight_plan()
  key <- line_item(p@data, p@grain)[1]
  s <- build_scenario(p, edits = stats::setNames(50000, key), name = "one")
  fl <- flights(s)
  expect_identical(fl$pacing[fl$channel == "TV"], "even")
  expect_identical(fl$pacing[fl$channel == "Search"], "even")
})

test_that("proportional edits stay even at any magnitude", {
  # cent-rounding drift must not be mistaken for hand shaping: scaling changes
  # a flight's size, not its shape
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000),
    grain = "channel", name = "ragged")
  for (f in c(0.5, 2, 1000, 1/3)) {
    s <- build_scenario(p, edits = list(scale = f), name = paste0("x", f))
    expect_identical(flights(s)$pacing, "even")
  }
  expect_identical(
    flights(build_scenario(p, edits = list(total = 200000), name = "t"))$pacing,
    "even")
})

test_that("an even flight is snapped to canonical figures, so drift cannot accumulate", {
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000),
    grain = "channel", name = "ragged")
  chain <- p
  for (i in 1:12) {
    chain <- build_scenario(chain, edits = list(scale = 1.37),
                            name = paste0("s", i))
  }
  back <- build_scenario(chain, edits = list(total = 100000), name = "back")
  expect_identical(back@data$planned_spend, p@data$planned_spend)
  expect_identical(flights(back)$pacing, "even")
})

test_that("snapping never changes a flight's total", {
  p <- media_plan_from_flights(
    data.frame(channel = "OOH", flight_start = as.Date("2026-04-08"),
               flight_end = as.Date("2026-05-03"), planned_spend = 100000),
    grain = "channel", name = "ragged")
  s <- build_scenario(p, edits = list(scale = 1.37), name = "odd")
  expect_equal(sum(s@data$planned_spend), 137000)
})

test_that("a plan with no flights is unaffected by repacing", {
  p <- weekly_plan()
  expect_silent(build_scenario(p, edits = list(scale = 2), name = "x"))
  expect_identical(build_scenario(p, edits = list(scale = 2), name = "y")@data$planned_spend,
                   weekly_plan()@data$planned_spend * 2)
})

# ---- refusals ----------------------------------------------------------------

test_that("two flights of one line item overlapping a week is an error", {
  df <- data.frame(
    channel = c("TV", "TV"),
    flight_start = as.Date(c("2026-04-06", "2026-04-08")),
    flight_end   = as.Date(c("2026-04-12", "2026-04-09")),
    planned_spend = c(100, 50))
  expect_error(media_plan_from_flights(df, grain = "channel", name = "clash"),
               "overlap the same week")
})

test_that("a flight that ends before it starts is an error", {
  df <- data.frame(channel = "TV",
                   flight_start = as.Date("2026-04-12"),
                   flight_end   = as.Date("2026-04-06"),
                   planned_spend = 100)
  expect_error(media_plan_from_flights(df, grain = "channel", name = "backwards"),
               "ends .* before it starts")
})

test_that("an existing week column is rejected rather than overwritten", {
  df <- cbind(flight_df(), week = as.Date("2026-04-06"))
  expect_error(
    media_plan_from_flights(df, grain = c("channel", "partner"), name = "dup"),
    "already exists")
})

test_that("an unknown weekday is an error naming the valid ones", {
  expect_error(media_plan_from_flights(flight_df(), grain = "channel",
                                       name = "x", week_start = "Funday"),
               "must name a weekday")
})

# ---- validator ---------------------------------------------------------------

test_that("rows sharing a flight_id must agree on that flight's dates", {
  p <- flight_plan()
  d <- p@data
  d$flight_end[1] <- as.Date("2026-04-30")     # one row of the OOH flight differs
  expect_error(
    MediaPlan(data = d, grain = p@grain, week_col = p@week_col, name = "bad"),
    "disagree on 'flight_end'")
})

test_that("a bad cadence or pacing value is rejected", {
  p <- flight_plan()
  d <- p@data; d$period_basis[1] <- "fortnight"
  expect_error(MediaPlan(data = d, grain = p@grain, week_col = p@week_col,
                         name = "bad"), "period_basis")

  d2 <- p@data; d2$pacing[1] <- "frontloaded"
  expect_error(MediaPlan(data = d2, grain = p@grain, week_col = p@week_col,
                         name = "bad"), "pacing")
})

test_that("flight_end before flight_start is rejected by the validator", {
  p <- flight_plan()
  d <- p@data; d$flight_end <- d$flight_start - 1L
  expect_error(MediaPlan(data = d, grain = p@grain, week_col = p@week_col,
                         name = "bad"), "before flight_start")
})

test_that("a plan with no flight columns is unaffected by any of this", {
  expect_silent(weekly_plan())
  expect_identical(nrow(flights(weekly_plan())), 0L)
})
