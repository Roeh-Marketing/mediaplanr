# The op constructors build the same plain list a hand-written op is, and
# check it where it is written. The registry in ops.R is the one description of
# which ops exist; these tests pin that the constructors, the apply path and the
# key list that used to be maintained by hand all agree with it.

tv    <- list(channel = "TV")
april <- list(from = "2026-04-01", to = "2026-04-30")

# A flighted plan, so shift and restage have flights to move.
flighted_plan <- function() {
  media_plan_from_flights(
    data.frame(channel = c("TV", "Search", "Social"),
               flight_start = as.Date("2026-07-06"),
               flight_end   = as.Date(c("2026-07-26", "2026-07-19", "2026-07-12")),
               planned_spend = c(300, 200, 100)),
    grain = "channel", name = "flighted")
}

# ---- same object as a hand-written op ----------------------------------------

test_that("each constructor builds exactly the hand-written op", {
  expect_identical(op_set(50), list(set = 50))
  expect_identical(op_set(50, target = tv), list(set = 50, target = tv))
  expect_identical(op_scale(1.2, target = tv, during = april),
                   list(scale = 1.2, target = tv, during = april))
  expect_identical(op_delta(-10, target = tv), list(delta = -10, target = tv))
  expect_identical(op_delta_each(5), list(delta_each = 5))
  expect_identical(op_total(200, during = april),
                   list(total = 200, during = april))
  expect_identical(
    op_transfer(500, from = tv, to = list(channel = "Search"),
                to_during = april),
    list(transfer = 500, from = tv, to = list(channel = "Search"),
         to_during = april))
  expect_identical(
    op_add(channel = "Audio", week = "2026-07-06", planned_spend = 25),
    list(add = list(channel = "Audio", week = "2026-07-06", planned_spend = 25)))
  expect_identical(op_drop(target = tv), list(drop = TRUE, target = tv))
  expect_identical(op_shift(7, target = tv), list(shift = 7, target = tv))
  expect_identical(
    op_restage("2026-05-04", "2026-05-31", target = tv),
    list(restage = list(from = "2026-05-04", to = "2026-05-31"), target = tv))
  expect_identical(op_rebound(min = 100, max = NA, target = tv),
                   list(rebound = list(min = 100, max = NA), target = tv))
  expect_identical(op_rebound(max = 500), list(rebound = list(max = 500)))
})

test_that("a constructor-built op applies exactly as the hand-written one", {
  base <- flighted_plan()    # one base, so both scenarios share flight ids
  by_hand <- build_scenario(base, name = "x", edits = list(
    list(delta = -100, target = list(channel = "TV")),
    list(shift = 7, target = list(channel = "Social"))))
  built <- build_scenario(base, name = "x", edits = list(
    op_delta(-100, target = list(channel = "TV")),
    op_shift(7, target = list(channel = "Social"))))
  expect_identical(built@data, by_hand@data)
})

test_that("an op parsed from JSON applies like the constructor-built one", {
  parsed <- jsonlite::fromJSON(
    '[{"scale": 1.5, "target": {"channel": ["TV", "Search"]}}]',
    simplifyVector = FALSE)
  base <- std_plan()
  expect_identical(
    build_scenario(base, edits = parsed, name = "s")@data,
    build_scenario(base, name = "s", edits = list(
      op_scale(1.5, target = list(channel = c("TV", "Search")))))@data)
})

# ---- the registry is the source of truth -------------------------------------

test_that("the registry reproduces the op keys that were maintained by hand", {
  # transfer and rebound are new in the registry; the rest are the hand-kept
  # list, in order
  expect_identical(setdiff(.op_keys, c("transfer", "rebound")),
                   c("set", "scale", "delta", "delta_each", "total",
                     "add", "drop", "shift", "restage"))
})

test_that("every op in the registry has a constructor", {
  for (key in .op_keys) {
    expect_true(exists(paste0("op_", key), mode = "function"), info = key)
  }
})

# ---- checked where it is written ---------------------------------------------

test_that("a malformed value errors at construction, naming the constructor", {
  expect_error(op_scale("2"),
               "op_scale\\(\\): `scale` must be a single non-missing number")
  expect_error(op_delta(c(1, 2)), "single non-missing number")
  expect_error(op_total(NA_real_), "single non-missing number")
  expect_error(op_set(-1), "`set` must be 0 or more")
  expect_error(op_shift(2.5), "whole number of days")
  expect_error(op_transfer(0, from = tv, to = list(channel = "Search")),
               "`transfer` must be more than 0")
  expect_error(op_transfer(10, from = tv, to = "Search"), "`to` must be a named list")
})

test_that("a malformed target or window errors at construction", {
  expect_error(op_scale(1, target = list("TV")), "named list")
  expect_error(op_scale(1, target = list(channel = character(0))),
               "names no value for: channel")
  expect_error(op_scale(1, during = list(from = "2026-04-01")),
               "`from` and `to`")
  expect_error(op_scale(1, during = c(april, by = "week")),
               "only `from` and `to`; got also: by")
  expect_error(op_scale(1, during = list(from = "April", to = "2026-04-30")),
               "during\\$from.*ISO-8601")
  expect_error(op_restage("2026-05-31", "2026-05-01"),
               "`restage` ends .* before it starts")
})

test_that("a malformed line item errors at construction", {
  expect_error(op_add(channel = "Audio", week = "2026-07-06"),
               "needs a `planned_spend`")
  expect_error(op_add(channel = "Audio", week = "2026-07-06", planned_spend = -1),
               "single non-negative number")
  expect_error(op_add("Audio", planned_spend = 5), "named list")
  expect_error(op_add(channel = c("Audio", "Radio"), week = "2026-07-06",
                      planned_spend = 5), "single value; not: channel")
  expect_error(op_add(channel = "Audio", planned_spend = 5,
                      flight_start = "2026-07-06"),
               "both flight_start and flight_end, or neither")
  expect_error(op_add(channel = "Audio", planned_spend = 5,
                      flight_start = "2026-07-20", flight_end = "2026-07-06"),
               "the added flight ends .* before it starts")
})

test_that("a hand-written op gets the same checks when it is applied", {
  expect_error(build_scenario(std_plan(), edits = list(set = -1), name = "s"),
               "edit op 1: `set` must be 0 or more")
  expect_error(build_scenario(std_plan(), name = "s",
                              edits = list(scale = 1, during = c(april, by = 1))),
               "only `from` and `to`")
})

test_that("each op accepts only its own fields", {
  # `add` names the line item it creates; a window on it used to be ignored
  # without a word, so it is refused.
  expect_error(
    build_scenario(std_plan(), name = "s", edits = list(
      add = list(channel = "Audio", week = "2026-07-06", planned_spend = 5),
      during = list(from = "2026-07-01", to = "2026-07-31"))),
    "unknown field\\(s\\): during. `add` takes: add")
})
