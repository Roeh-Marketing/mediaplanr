# revise() is the metadata-only door. The contract: same plan (same id), only
# the named fields change, and it refuses anything that is not metadata --
# because a caller that rebuilds a plan by hand is the one that drops slots.

test_that("a plan starts unapproved, with no subplans", {
  p <- std_plan()
  expect_identical(p@approved_on, as.Date(character(0)))
  expect_identical(p@subplans, list())
})

test_that("revise changes what it names and nothing else", {
  p <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", planned_spend = 10), grain = "channel", time = "week",
    name = "Q2", advertiser = "Acme", status = "in development")
  q <- revise(p, status = "Approved", approved_on = "2026-10-29",
              nickname = "final")
  expect_identical(q@id, p@id)
  expect_identical(q@parent_id, p@parent_id)
  expect_identical(q@data, p@data)
  expect_identical(q@advertiser, "Acme")
  expect_identical(q@name, "Q2")
  expect_identical(q@status, "approved")
  expect_identical(q@approved_on, as.Date("2026-10-29"))
  expect_identical(q@nickname, "final")
})

test_that("revise keeps subplans", {
  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("A", "B"), planned_spend = c(1, 2)),
    grain = c("channel", "partner"), time = "week", name = "tv")
  p <- attach_subplan(std_plan(), tv)
  q <- revise(p, status = "approved")
  expect_identical(names(q@subplans), "TV")
  expect_equal(q@data, p@data)
})

test_that("revise refuses non-metadata and bad values", {
  p <- std_plan()
  expect_error(revise(p), "nothing to revise")
  expect_error(revise(p, data = data.frame()), "metadata only; cannot set: data")
  expect_error(revise(p, grain = "x", id = "y"), "cannot set: grain, id")
  expect_error(revise(p, subplans = list()), "cannot set: subplans")
  expect_error(revise(p, "positional"), "named arguments only")
  expect_error(revise(p, status = "done"), "must be one of")
  expect_error(revise(1, name = "x"), "must be a MediaPlan")
})

test_that("a revision is no longer set by hand", {
  expect_error(revise(std_plan(), revision = 2),
               "revision.*is its place among the approved plans.*lineage\\(\\)")
})

# ---- approval ----------------------------------------------------------------

test_that("only an approved plan has an approval date, and it is optional", {
  p <- std_plan()
  expect_error(revise(p, approved_on = "2026-10-29"),
               "@approved_on is set but @status is \"\"")
  expect_error(revise(p, status = "approved", approved_on = "late October"),
               "must be a single date")
  # approved, with no date given: none is made up
  expect_identical(revise(p, status = "approved")@approved_on,
                   as.Date(character(0)))
})

test_that("moving the status off approved withdraws the date", {
  q <- revise(std_plan(), status = "approved", approved_on = as.Date("2026-10-29"))
  expect_identical(revise(q, status = "to review")@approved_on,
                   as.Date(character(0)))
  # other metadata leaves the approval alone
  expect_identical(revise(q, nickname = "final")@approved_on,
                   as.Date("2026-10-29"))
})

test_that("media_plan_from_df takes an approval date", {
  df <- data.frame(week = fix_week(), channel = "TV", planned_spend = 1)
  p <- media_plan_from_df(df, grain = "channel", time = "week", name = "t",
                          status = "approved", approved_on = "2026-10-29")
  expect_identical(p@approved_on, as.Date("2026-10-29"))
  expect_error(media_plan_from_df(df, grain = "channel", time = "week",
                                  name = "t", approved_on = "2026-10-29"),
               "only an approved plan has an approval date")
})

test_that("derived plans never inherit an approval", {
  p <- revise(fine_plan(), status = "approved", approved_on = "2026-10-29")
  s <- build_scenario(p, op_scale(2, target = list(channel = "TV")), name = "s")
  expect_identical(s@approved_on, as.Date(character(0)))
  expect_identical(s@status, "in development")
  expect_identical(roll_up(p, "channel")@approved_on, as.Date(character(0)))
})
