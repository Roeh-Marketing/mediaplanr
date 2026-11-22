# regrain(): an organization level added as a grain column. The contract: the
# same plan, re-keyed -- totals, identity and lineage unchanged, and stored
# edits still replay.

funnel <- function() {
  list(Brand = c("Streaming", "Online Video"), Performance = "Programmatic")
}
by_funnel <- function(p) regrain(p, "funnel", from = "channel", groups = funnel())

q1 <- function() list(from = "2027-01-01", to = "2027-03-31")

test_that("keys change and totals do not", {
  p <- fix_agency_plan()
  r <- by_funnel(p)
  expect_identical(r@grain, c("funnel", "channel", "partner", "campaign",
                              "tactic", "month"))
  expect_equal(names(r@data)[1:3], c("month", "funnel", "channel"))
  expect_equal(nrow(r@data), nrow(p@data))
  expect_equal(r@data$planned_spend, p@data$planned_spend)
  expect_equal(r@data$funnel[p@data$channel == "Programmatic"],
               rep("Performance", 18))
  expect_equal(line_item(r@data, line_item_grain(r))[1],
               "Brand | Online Video | Video A | Brand | Added Value")
  expect_equal(sum(r@data$planned_spend), sum(p@data$planned_spend))
  # and the funnel is a target now
  expect_equal(match_rows(r, list(funnel = "Brand")),
               p@data$channel != "Programmatic")
})

test_that("every other slot is carried, as revise() carries it", {
  p <- revise(fix_agency_plan(), status = "approved", approved_on = "2026-09-15",
              spend_basis = "media_net", rationale = list(author = "human"))
  s <- build_scenario(p, op_scale(0.9, list(partner = "DSP A")), name = "s",
                      rationale = list(author = "agent", goal = "trim"))
  for (plan in list(p, s)) {
    r <- by_funnel(plan)
    same <- setdiff(mediaplanr:::.settable_props(MediaPlan),
                    c("data", "grain", "edits"))
    for (slot in same) {
      expect_identical(S7::prop(r, slot), S7::prop(plan, slot), info = slot)
    }
  }
  expect_identical(by_funnel(s)@edits, s@edits)   # ops with targets only
})

test_that("before places the column elsewhere in the grain", {
  r <- regrain(fix_agency_plan(), "line", from = "tactic",
               groups = list(Upper = c("Upfront", "Prospecting", "Added Value"),
                             Lower = c("Retargeting", "Regional")),
               before = "campaign")
  expect_identical(r@grain, c("channel", "partner", "line", "campaign",
                              "tactic", "month"))
})

test_that("a value with no group is refused, naming it", {
  expect_error(
    regrain(fix_agency_plan(), "funnel", from = "channel",
            groups = list(Brand = "Streaming", Performance = "Programmatic")),
    "places no group on channel value\\(s\\): Online Video")
})

test_that("a value in two groups is refused, naming it", {
  expect_error(
    regrain(fix_agency_plan(), "funnel", from = "channel",
            groups = list(Brand = c("Streaming", "Online Video"),
                          Performance = c("Programmatic", "Online Video"))),
    "more than one group: Online Video \\(Brand, Performance\\)")
})

test_that("a group may name a value the plan lacks", {
  g <- funnel()
  g$Performance <- c("Programmatic", "Search")
  expect_no_error(regrain(fix_agency_plan(), "funnel", "channel", g))
})

test_that("regrain refuses a bad name, column, groups or a topline", {
  p <- fix_agency_plan()
  expect_error(regrain(p, "channel", "channel", funnel()), "already a column")
  expect_error(regrain(p, "min_spend", "channel", funnel()), "reserves")
  expect_error(regrain(p, "flight_id", "channel", funnel()), "reserves")
  expect_error(regrain(p, "funnel", "month", funnel()),
               "`from` must name one of the plan's line item columns")
  expect_error(regrain(p, "funnel", "channel", funnel(), before = "market"),
               "`before` must name")
  expect_error(regrain(p, "funnel", "channel", c("Streaming")), "named list")
  expect_error(regrain(p, "", "channel", funnel()), "single column name")

  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  topline <- attach_subplan(std_plan(), tv)
  expect_error(regrain(topline, "funnel", "channel",
                       list(Brand = "TV", Performance = c("Search", "Social"))),
               "holds subplans")
})

test_that("a regrained plan round-trips through JSON", {
  s <- build_scenario(fix_agency_plan(), list(
    op_add(channel = "Streaming", partner = "Stream C", campaign = "Brand",
           tactic = "Prospecting", month = "2027-01-01", planned_spend = 0),
    op_transfer(5000, from = list(partner = "Stream B"),
                to = list(partner = "Stream C"), during = q1())
  ), name = "with add")
  r <- by_funnel(s)
  q <- plan_from_json(plan_to_json(r))
  expect_identical(q@grain, r@grain)
  expect_identical(q@id, r@id)
  expect_identical(q@parent_id, r@parent_id)
  expect_identical(q@edits, r@edits)
  ord <- function(d) d[do.call(order, d[r@grain]), names(r@data)]
  expect_equal(ord(q@data), ord(r@data), ignore_attr = TRUE)
})

test_that("a scenario's @edits replay on its regrained parent", {
  p <- fix_agency_plan()
  s <- build_scenario(p, list(
    op_transfer(10000, from = list(partner = "Stream B"),
                to = list(partner = "Video A", tactic = "Prospecting"),
                during = q1()),
    op_scale(0.9, list(channel = "Programmatic"))
  ), name = "draft")
  rp <- by_funnel(p)
  # the record replays as stored...
  expect_equal(mediaplanr:::.replay(rp, s@edits), by_funnel(s)@data)
  # ...and through the front door
  expect_equal(build_scenario(rp, s@edits$ops, name = "again")@data,
               by_funnel(s)@data)
})

test_that("a stored add and a stored allocation gain the new column", {
  p <- fix_agency_plan()
  with_add <- build_scenario(p, op_add(
    channel = "Programmatic", partner = "DSP C", campaign = "Promo",
    tactic = "Retargeting", month = "2027-02-01", planned_spend = 4000),
    name = "add")
  r <- by_funnel(with_add)
  expect_equal(r@edits$ops[[1]]$add$funnel, "Performance")
  expect_equal(mediaplanr:::.replay(by_funnel(p), r@edits), r@data)
  # a value only the stored edits name -- added, then dropped -- needs a
  # group too, or the edits would not replay on the regrained parent
  gone <- build_scenario(p, list(
    op_add(channel = "Audio", partner = "Pod A", campaign = "Brand",
           tactic = "Prospecting", month = "2027-02-01", planned_spend = 0),
    op_drop(list(channel = "Audio"))), name = "add and drop")
  expect_error(by_funnel(gone), "places no group on channel value\\(s\\): Audio")
  g <- c(funnel(), list(Other = "Audio"))
  rg <- regrain(gone, "funnel", "channel", g)
  expect_equal(mediaplanr:::.replay(regrain(p, "funnel", "channel", g), rg@edits),
               rg@data)

  alloc <- p@data[1:2, c(p@grain, "planned_spend")]
  alloc$planned_spend <- alloc$planned_spend + 10
  a <- build_scenario(p, alloc, name = "alloc")
  ra <- by_funnel(a)
  expect_equal(names(ra@edits$data)[1:2], c("funnel", "channel"))
  expect_equal(mediaplanr:::.replay(by_funnel(p), ra@edits), ra@data)
})

test_that("lineage() and current_approved() are unchanged on a regrained set", {
  rev1 <- revise(fix_agency_plan("Rev 1"), status = "approved")
  rev2 <- revise(build_scenario(rev1, op_scale(0.95, list(partner = "DSP A")),
                                name = "Rev 2"), status = "approved")
  draft <- build_scenario(rev2, op_scale(1.1, list(partner = "Stream B")),
                          name = "draft")
  set <- add_scenario(add_scenario(scenario_set(rev1), rev2), draft)
  plans <- list(rev1, rev2, draft)
  rset <- Reduce(add_scenario, lapply(plans[-1], by_funnel),
                 scenario_set(by_funnel(rev1)))
  expect_identical(rset@grain, by_funnel(rev1)@grain)
  expect_identical(lineage(rset), lineage(set))
  expect_identical(current_approved(rset), current_approved(set))
  expect_identical(current_approved(rset), "Rev 2")
})
