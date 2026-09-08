# revise() is the metadata-only door. The contract: same plan (same id), only
# the named fields change, and it refuses anything that is not metadata --
# because a caller that rebuilds a plan by hand is the one that drops slots.

test_that("a plan starts at revision 1 with no subplans", {
  p <- std_plan()
  expect_identical(p@revision, 1L)
  expect_identical(p@subplans, list())
})

test_that("revise changes what it names and nothing else", {
  p <- media_plan_from_df(
    data.frame(channel = "TV", planned_spend = 10), grain = "channel",
    name = "Q2", advertiser = "Acme", status = "in development")
  q <- revise(p, status = "Approved", revision = 2, nickname = "final")
  expect_identical(q@id, p@id)
  expect_identical(q@parent_id, p@parent_id)
  expect_identical(q@data, p@data)
  expect_identical(q@advertiser, "Acme")
  expect_identical(q@name, "Q2")
  expect_identical(q@status, "approved")
  expect_identical(q@revision, 2L)
  expect_identical(q@nickname, "final")
})

test_that("revise keeps subplans", {
  tv <- media_plan_from_df(
    data.frame(channel = "TV", partner = c("A", "B"), planned_spend = c(1, 2)),
    grain = c("channel", "partner"), name = "tv")
  p <- attach_subplan(std_plan(), tv)
  q <- revise(p, revision = 3)
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
  expect_error(revise(p, revision = 0), "positive whole number")
  expect_error(revise(p, revision = 1.5), "positive whole number")
  expect_error(revise(p, status = "done"), "must be one of")
  expect_error(revise(1, name = "x"), "must be a MediaPlan")
})

test_that("media_plan_from_df takes a revision", {
  p <- media_plan_from_df(data.frame(channel = "TV", planned_spend = 1),
                          grain = "channel", name = "t", revision = 4)
  expect_identical(p@revision, 4L)
  expect_error(media_plan_from_df(data.frame(channel = "TV", planned_spend = 1),
                                  grain = "channel", name = "t", revision = -1),
               "positive whole number")
})

test_that("a new id starts the revision count over", {
  p <- revise(std_plan(), revision = 3)
  expect_identical(build_scenario(p, c(TV = 1), name = "s")@revision, 1L)
  expect_identical(roll_up(fine_plan(), "channel")@revision, 1L)
  expect_identical(revise(fine_plan(), revision = 2)@revision, 2L)
})
