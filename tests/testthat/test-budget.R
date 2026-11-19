# check_budget() pairs a plan with the envelope it was authorised under. The
# contract worth pinning: planned spend is measured day by day inside each
# window, whatever the plan is keyed by; rows may name any subset of the line
# item columns, or none; a value the plan lacks reads as absent, not as an
# underspend; and anything off by more than the tolerance is warned about,
# never refused.

q4 <- c(from = "2026-10-01", to = "2026-12-31")
q1 <- c(from = "2027-01-01", to = "2027-03-31")

envelope <- function(..., from, to, amount) {
  data.frame(..., from = from, to = to, amount = amount,
             stringsAsFactors = FALSE)
}

# The plan's own spend for a channel over some months, from @data directly.
spend_in <- function(plan, channel, months) {
  d <- plan@data
  sum(d$planned_spend[d$channel == channel &
                        format(d$month, "%Y-%m") %in% months])
}

# ---- measuring the plan inside a window ----------------------------------------

test_that("a quarterly channel envelope sums the plan's months", {
  a <- fix_agency_plan()
  q4_months <- c("2026-10", "2026-11", "2026-12")
  budget <- envelope(channel = c("Streaming", "Programmatic"),
                     from = q4[["from"]], to = q4[["to"]],
                     amount = c(350000, 260000))
  out <- suppressWarnings(check_budget(a, budget))
  expect_equal(out$planned, c(spend_in(a, "Streaming", q4_months),
                              spend_in(a, "Programmatic", q4_months)))
  expect_equal(out$variance, out$planned - budget$amount)
  expect_equal(out$variance_pct, out$variance / budget$amount)
  expect_identical(out$within, c(TRUE, FALSE))
  expect_s3_class(out$from, "Date")
})

test_that("a window that ends mid-week takes only the days inside it", {
  # The week of Monday 28 September runs four days into October.
  weekly <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-09-28", "2026-10-05")), channel = "TV",
               planned_spend = c(700, 700)),
    grain = "channel", time = "week", name = "weekly")
  out <- suppressWarnings(check_budget(weekly, envelope(
    channel = "TV", from = c("2026-09-01", "2026-10-01"),
    to = c("2026-09-30", "2026-10-31"), amount = c(300, 1100))))
  expect_equal(out$planned, c(300, 1100))
  expect_true(all(out$within))
})

test_that("an envelope with no line item columns covers the whole plan", {
  a <- fix_agency_plan()
  out <- check_budget(a, envelope(from = "2026-10-01", to = "2027-03-31",
                                  amount = sum(a@data$planned_spend)))
  expect_equal(out$variance, 0)
  # and NA in a line item column covers every value, beside named rows
  mixed <- suppressWarnings(check_budget(a, envelope(
    channel = c("Streaming", NA), from = q1[["from"]], to = q1[["to"]],
    amount = c(1, 1))))
  expect_equal(mixed$planned[2],
               sum(a@data$planned_spend[a@data$month >= as.Date("2027-01-01")]))
})

test_that("a plan keyed by moments is placed on the calendar by day", {
  spots <- media_plan_from_flights(
    data.frame(channel = "TV", programme = c("Final", "Late"),
               flight_start = c("2026-02-08 20:00:00", "2026-03-01 21:00:00"),
               flight_end   = c("2026-02-08 20:00:30", "2026-03-01 21:30:00"),
               planned_spend = c(450000, 90000)),
    grain = c("channel", "programme"), basis = "instant", name = "spots")
  out <- check_budget(spots, envelope(
    from = c("2026-02-01", "2026-03-01"), to = c("2026-02-28", "2026-03-31"),
    amount = c(450000, 90000)))
  expect_equal(out$planned, c(450000, 90000))
})

test_that("a topline is checked like any plan", {
  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  top <- attach_subplan(std_plan(), tv)
  out <- check_budget(top, envelope(channel = "TV", from = "2026-07-01",
                                    to = "2026-07-31", amount = 120))
  expect_true(out$within)
})

# ---- reporting ---------------------------------------------------------------

test_that("a budget for something the plan lacks is reported as absent", {
  expect_warning(
    out <- check_budget(fix_agency_plan(), envelope(
      channel = "Audio", from = q4[["from"]], to = q4[["to"]], amount = 5000)),
    "channel Audio, 2026-10-01..2026-12-31: planned 0 against 5,000 \\(-5,000\\) -- not in the plan")
  expect_equal(out$planned, 0)
  expect_false(out$in_plan)
})

test_that("only variance beyond the tolerance is warned about", {
  plan <- std_plan()                     # TV plans 80
  at <- function(amount, ...) {
    check_budget(plan, envelope(channel = "TV", from = "2026-07-01",
                                to = "2026-07-31", amount = amount), ...)
  }
  expect_silent(at(80.5))                # exactly at the default tolerance
  expect_warning(at(80.51), "1 budget row\\(s\\) off by more than 0.5")
  expect_silent(at(85, tolerance = 5))
  expect_warning(at(85), "planned 80 against 85 \\(-5\\)")
})

test_that("a malformed budget errors, naming the fix", {
  plan <- fine_plan()
  ok <- function(...) envelope(..., from = "2026-07-01", to = "2026-07-31",
                               amount = 1)
  expect_error(check_budget(plan, ok(tactic = "x")),
               "line items do not have: tactic. It may use: channel, partner")
  expect_error(check_budget(plan, data.frame(channel = "TV", amount = 1)),
               "missing column\\(s\\): from, to")
  expect_error(check_budget(plan, envelope(from = "soon", to = "2026-07-31",
                                           amount = 1)),
               "`budget\\$from` must be dates")
  expect_error(check_budget(plan, envelope(from = "2026-07-31",
                                           to = "2026-07-01", amount = 1)),
               "end before they start")
  expect_error(check_budget(plan, ok(), tolerance = -1), "0 or more")
})

# ---- in describe_plan() ------------------------------------------------------

test_that("describe_plan() summarises the variances, worst first", {
  budget <- envelope(channel = c("Streaming", "Programmatic", "Online Video"),
                     from = q4[["from"]], to = q4[["to"]],
                     amount = c(350000, 260000, 110000))
  b <- describe_plan(fix_agency_plan(), top_n = 1, budget = budget)$budget
  expect_identical(b$n_rows, 3L)
  expect_identical(b$n_within, 1L)
  expect_identical(b$off$envelope, "channel Programmatic, 2026-10-01..2026-12-31")
  expect_equal(b$off$variance, 37500)
  expect_identical(b$n_more_off, 1L)
  expect_null(describe_plan(fix_agency_plan())$budget)
})
