# A subplan is a plan owned by the team planning one cell's detail. The
# contract worth pinning: attaching makes the parent's rows for that cell the
# subplan's rollup and locks them; the cell is a fact in the subplan's data;
# detaching unlocks without destroying; and the validator holds the invariant
# so the slot cannot be filled with something the parent's rows contradict.

# TV detail at channel + partner, refining std_plan()'s TV cell (80 -> 120).
tv_sub <- function(spend = c(70, 50), name = "TV detail") {
  media_plan_from_df(
    data.frame(channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = spend, stringsAsFactors = FALSE),
    grain = c("channel", "partner"), name = name
  )
}

# ---- attaching ---------------------------------------------------------------

test_that("attach replaces the cell with the rollup and leaves the rest alone", {
  top <- std_plan()
  p   <- attach_subplan(top, tv_sub())
  d   <- p@data
  expect_equal(d$planned_spend[d$channel == "TV"], 120)
  expect_equal(d$planned_spend[d$channel == "Search"], 40)
  expect_equal(d$planned_spend[d$channel == "Social"], 40)
  expect_equal(nrow(d), 3)
  expect_identical(names(p@subplans), "TV")
  expect_true(S7::S7_inherits(p@subplans$TV, MediaPlan))
  # attaching is not a derivation: same plan, same revision
  expect_identical(p@id, top@id)
  expect_identical(p@revision, top@revision)
  # the subplan itself is untouched
  expect_identical(p@subplans$TV@parent_id, character(0))
})

test_that("a same-grain subplan is allowed: ownership without refinement", {
  own <- media_plan_from_df(data.frame(channel = "TV", planned_spend = 95),
                            grain = "channel", name = "tv owner")
  p <- attach_subplan(std_plan(), own)
  expect_equal(p@data$planned_spend[p@data$channel == "TV"], 95)
})

test_that("attaching to a cell the parent lacks adds it", {
  audio <- media_plan_from_df(
    data.frame(channel = "Audio", partner = c("Spotify", "Pandora"),
               planned_spend = c(5, 7)),
    grain = c("channel", "partner"), name = "audio")
  p <- attach_subplan(std_plan(), audio)
  expect_equal(nrow(p@data), 4)
  expect_equal(p@data$planned_spend[p@data$channel == "Audio"], 12)
  expect_identical(names(p@subplans), "Audio")
})

test_that("re-attaching replaces the held subplan and the rows", {
  p <- attach_subplan(std_plan(), tv_sub())
  q <- attach_subplan(p, tv_sub(spend = c(10, 10), name = "TV v2"))
  expect_equal(q@data$planned_spend[q@data$channel == "TV"], 20)
  expect_identical(names(q@subplans), "TV")
  expect_identical(q@subplans$TV@name, "TV v2")
})

test_that("two subplans on different cells coexist", {
  se <- media_plan_from_df(
    data.frame(channel = "Search", engine = c("Google", "Bing"),
               planned_spend = c(30, 5)),
    grain = c("channel", "engine"), name = "search")
  p <- attach_subplan(attach_subplan(std_plan(), tv_sub()), se)
  expect_setequal(names(p@subplans), c("TV", "Search"))
  expect_equal(sum(p@data$planned_spend), 120 + 35 + 40)
})

# ---- the grain rule ------------------------------------------------------------

test_that("a coarser or sideways subplan is refused", {
  # parent channel + partner; subplan channel only -- coarser
  expect_error(attach_subplan(fine_plan(), std_plan()),
               "must contain the parent's.*lacks: partner")
  # parent channel; subplan partner only -- sideways
  side <- media_plan_from_df(data.frame(partner = c("A", "B"),
                                        planned_spend = c(1, 2)),
                             grain = "partner", name = "side")
  expect_error(attach_subplan(std_plan(), side), "lacks: channel")
})

test_that("a subplan spanning several parent cells is refused", {
  expect_error(attach_subplan(std_plan(), fine_plan()),
               "spans 3 cells.*refines one cell")
})

test_that("an empty subplan and a non-plan are refused", {
  empty <- media_plan_from_df(
    data.frame(channel = character(0), planned_spend = numeric(0)),
    grain = "channel", name = "empty")
  expect_error(attach_subplan(std_plan(), empty), "no rows")
  expect_error(attach_subplan(std_plan(), data.frame()), "must be a MediaPlan")
  expect_error(attach_subplan(data.frame(), tv_sub()), "must be a MediaPlan")
})

test_that("a plan cannot be attached beneath itself, directly or nested", {
  only_tv <- media_plan_from_df(data.frame(channel = "TV", planned_spend = 1),
                                grain = "channel", name = "only tv")
  expect_error(attach_subplan(only_tv, only_tv), "its own descendant")

  x <- media_plan_from_df(data.frame(channel = "TV", planned_spend = 2),
                          grain = "channel", name = "x")
  y <- attach_subplan(only_tv, x)      # y holds x
  expect_error(attach_subplan(x, y), "its own descendant")
})

# ---- cadence ---------------------------------------------------------------------

test_that("a weekly parent takes a weekly subplan and its weeks replace the cell's", {
  parent <- weekly_plan()             # TV|NBC on 03-02 and 04-06
  sub <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-03-02", "2026-03-02", "2026-03-09")),
               channel = "TV", partner = "NBC",
               daypart = c("prime", "day", "prime"),
               planned_spend = c(10, 5, 12)),
    grain = c("channel", "partner", "daypart", "week"), week = "week",
    name = "NBC detail")
  p <- attach_subplan(parent, sub)
  d <- p@data[p@data$channel == "TV" & p@data$partner == "NBC", ]
  expect_identical(names(p@subplans), "TV | NBC")
  expect_equal(sort(d$week), as.Date(c("2026-03-02", "2026-03-09")))
  expect_equal(d$planned_spend[order(d$week)], c(15, 12))
  # the other line items are untouched
  expect_equal(sum(p@data$planned_spend[p@data$partner != "NBC"]), 20 + 15 + 25)
})

test_that("a flighted subplan is re-cut onto the parent's weeks", {
  parent <- media_plan_from_df(
    data.frame(week = as.Date("2026-04-06"), channel = c("TV", "Search"),
               planned_spend = c(10, 20)),
    grain = c("channel", "week"), week = "week", name = "wk")
  fl <- media_plan_from_flights(
    data.frame(channel = "TV", partner = "NBC",
               flight_start = as.Date("2026-04-08"),
               flight_end   = as.Date("2026-04-21"),
               planned_spend = 1400),
    grain = c("channel", "partner"), name = "tv flight")
  p  <- attach_subplan(parent, fl)
  tv <- p@data[p@data$channel == "TV", ]
  tv <- tv[order(tv$week), ]
  expect_equal(tv$week, as.Date(c("2026-04-06", "2026-04-13", "2026-04-20")))
  expect_equal(tv$planned_spend, c(500, 700, 200))   # 5 + 7 + 2 days at 100
  # flight identity does not survive the rollup; those cells are NA on the parent
  expect_true(all(is.na(p@data$flight_id)) || !"flight_id" %in% names(p@data))
})

test_that("a Sunday-start subplan lands on a Monday-start parent by days", {
  parent <- media_plan_from_df(
    data.frame(week = as.Date("2026-04-06"), channel = "TV", planned_spend = 1),
    grain = c("channel", "week"), week = "week", name = "mon")
  sun <- media_plan_from_df(
    data.frame(week = as.Date("2026-04-05"), channel = "TV", partner = "NBC",
               planned_spend = 700),
    grain = c("channel", "partner", "week"), week = "week", name = "sun")
  p <- attach_subplan(parent, sun)
  d <- p@data[order(p@data$week), ]
  expect_equal(d$week, as.Date(c("2026-03-30", "2026-04-06")))
  expect_equal(d$planned_spend, c(100, 600))
})

test_that("a weekly parent refuses a timeless subplan", {
  expect_error(attach_subplan(weekly_plan(),
                              media_plan_from_df(
                                data.frame(channel = "TV", partner = "NBC",
                                           planned_spend = 1),
                                grain = c("channel", "partner"), name = "t")),
               "no time dimension")
})

test_that("a parent whose weeks do not share a weekday refuses", {
  mixed <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-04-06", "2026-04-12")),
               channel = c("TV", "Search"), planned_spend = c(1, 2)),
    grain = c("channel", "week"), week = "week", name = "mixed")
  sub <- media_plan_from_df(
    data.frame(week = as.Date("2026-04-06"), channel = "TV", partner = "NBC",
               planned_spend = 5),
    grain = c("channel", "partner", "week"), week = "week", name = "s")
  expect_error(attach_subplan(mixed, sub), "one weekday")
})

test_that("a timeless parent collapses a weekly subplan's time", {
  sub <- media_plan_from_df(
    data.frame(week = as.Date(c("2026-04-06", "2026-04-13")), channel = "TV",
               planned_spend = c(30, 45)),
    grain = c("channel", "week"), week = "week", name = "tv weeks")
  p <- attach_subplan(std_plan(), sub)
  expect_equal(p@data$planned_spend[p@data$channel == "TV"], 75)
  expect_equal(nrow(p@data), 3)
})

# ---- units -----------------------------------------------------------------------

test_that("units roll up with the spend and the parent gains the unit columns", {
  sub <- media_plan_from_df(
    data.frame(channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50), impressions = c(7000, 5000),
               unit = "impression"),
    grain = c("channel", "partner"), planned_units = "impressions",
    unit_type = "unit", name = "tv units")
  p  <- attach_subplan(std_plan(), sub)
  tv <- p@data[p@data$channel == "TV", ]
  expect_equal(tv$planned_units, 12000)
  expect_equal(tv$unit_type, "impression")
  expect_equal(tv$planned_rate, 120 / 12000 * 1000)
  expect_true(all(is.na(p@data$planned_units[p@data$channel != "TV"])))
})

# ---- detaching and the predicate -------------------------------------------------

test_that("detach keeps the reconciled rows and makes them editable", {
  p <- attach_subplan(std_plan(), tv_sub())
  q <- detach_subplan(p, "TV")
  expect_identical(q@subplans, list())
  expect_false(is_topline(q))
  expect_equal(q@data, p@data)
  expect_identical(q@id, p@id)
  s <- build_scenario(q, list(target = list(channel = "TV"), scale = 2),
                      name = "now editable")
  expect_equal(s@data$planned_spend[s@data$channel == "TV"], 240)
})

test_that("detach names what is attached when the key is wrong", {
  expect_error(detach_subplan(std_plan(), "TV"), "no subplans to detach")
  p <- attach_subplan(std_plan(), tv_sub())
  expect_error(detach_subplan(p, "Search"), 'no subplan at "Search".*Attached: TV')
  expect_error(detach_subplan(p, 1), "Attached: TV")
})

test_that("is_topline is a derived predicate", {
  expect_false(is_topline(std_plan()))
  expect_true(is_topline(attach_subplan(std_plan(), tv_sub())))
  expect_error(is_topline(1), "must be a MediaPlan")
})

# ---- the validator invariant -----------------------------------------------------

test_that("assigning a subplan the rows contradict is refused", {
  top <- std_plan()                     # TV is 80; the subplan says 120
  expect_error({ top@subplans <- list(TV = tv_sub()) },
               "rows for channel TV do not match")
})

test_that("editing a backed row behind the verbs' back is refused", {
  p <- attach_subplan(std_plan(), tv_sub())
  d <- p@data
  d$planned_spend[d$channel == "TV"] <- 1
  expect_error({ p@data <- d }, "do not match the attached subplan's rollup")
})

test_that("a subplan keyed under the wrong cell is refused", {
  p <- attach_subplan(std_plan(), tv_sub())
  expect_error({ p@subplans <- list(Search = tv_sub()) },
               'backs cell "TV", not "Search"')
})

test_that("a malformed subplans slot is refused", {
  p <- std_plan()
  expect_error({ p@subplans <- list(tv_sub()) }, "named list")
  expect_error({ p@subplans <- list(TV = 1) }, "not a MediaPlan")
})

# ---- read-only rows: every edit door --------------------------------------------

backed_msg <- "channel TV is planned in a subplan; edit the subplan and re-attach"

test_that("value ops on a backed cell error and name the door", {
  p <- attach_subplan(std_plan(), tv_sub())
  for (op in list(list(set = 1), list(scale = 2), list(delta = -1),
                  list(delta_each = 1), list(total = 5))) {
    expect_error(build_scenario(p, c(list(target = list(channel = "TV")), op),
                                name = "x"), backed_msg)
  }
})

test_that("a whole-plan op errors on a topline, because it reaches backed rows", {
  p <- attach_subplan(std_plan(), tv_sub())
  expect_error(build_scenario(p, list(total = 200), name = "x"), backed_msg)
})

test_that("drop, add, shift and restage refuse a backed cell", {
  p <- attach_subplan(std_plan(), tv_sub())
  expect_error(build_scenario(p, list(target = list(channel = "TV"), drop = TRUE),
                              name = "x"), backed_msg)
  expect_error(build_scenario(p, list(add = list(channel = "TV",
                                                 planned_spend = 1)),
                              name = "x"), backed_msg)

  wk <- attach_subplan(
    media_plan_from_df(
      data.frame(week = as.Date("2026-04-06"), channel = c("TV", "Search"),
                 planned_spend = c(10, 20)),
      grain = c("channel", "week"), week = "week", name = "wk"),
    media_plan_from_df(
      data.frame(week = as.Date("2026-04-06"), channel = "TV", partner = "NBC",
                 planned_spend = 30),
      grain = c("channel", "partner", "week"), week = "week", name = "s"))
  expect_error(build_scenario(wk, list(target = list(channel = "TV"), shift = 7),
                              name = "x"), backed_msg)
  expect_error(build_scenario(wk, list(target = list(channel = "TV"),
                                       restage = list(from = "2026-05-04",
                                                      to = "2026-05-10")),
                              name = "x"), backed_msg)
  # adding TV in a new week is still adding into TV's cell
  expect_error(build_scenario(wk, list(add = list(channel = "TV",
                                                  week = "2026-04-13",
                                                  planned_spend = 1)),
                              name = "x"), backed_msg)
})

test_that("the data frame and named-vector forms refuse a backed cell", {
  p <- attach_subplan(std_plan(), tv_sub())
  expect_error(build_scenario(p, data.frame(channel = "TV", planned_spend = 1),
                              name = "x"), backed_msg)
  expect_error(build_scenario(p, c(TV = 1), name = "x"), backed_msg)
})

test_that("edits that avoid backed rows work and the scenario carries the subplans", {
  p <- attach_subplan(std_plan(), tv_sub())
  s <- build_scenario(p, list(target = list(channel = "Search"), scale = 2),
                      name = "search x2")
  expect_equal(s@data$planned_spend[s@data$channel == "Search"], 80)
  expect_equal(s@data$planned_spend[s@data$channel == "TV"], 120)
  expect_identical(names(s@subplans), "TV")
  expect_true(is_topline(s))
  expect_identical(s@parent_id, p@id)

  s2 <- build_scenario(p, data.frame(channel = "Social", planned_spend = 1),
                       name = "df form")
  expect_equal(s2@data$planned_spend[s2@data$channel == "Social"], 1)
  s3 <- build_scenario(p, c(Social = 2), name = "vector form")
  expect_equal(s3@data$planned_spend[s3@data$channel == "Social"], 2)
})

# ---- what carries and what drops ------------------------------------------------

test_that("roll_up drops subplans; build_scenario carries them", {
  p <- attach_subplan(fine_plan(), media_plan_from_df(
    data.frame(channel = "TV", partner = "A", tactic = c("brand", "promo"),
               planned_spend = c(20, 25)),
    grain = c("channel", "partner", "tactic"), name = "tv a"))
  expect_identical(names(p@subplans), "TV | A")
  r <- roll_up(p, "channel")
  expect_identical(r@subplans, list())
  expect_equal(r@data$planned_spend[r@data$channel == "TV"], 45 + 30)
  s <- build_scenario(p, c("Search | X" = 1), name = "s")
  expect_identical(names(s@subplans), "TV | A")
})

test_that("a subplan can itself hold a subplan", {
  nbc <- media_plan_from_df(
    data.frame(channel = "TV", partner = "NBC", daypart = c("prime", "day"),
               planned_spend = c(60, 15)),
    grain = c("channel", "partner", "daypart"), name = "nbc")
  tv  <- attach_subplan(tv_sub(), nbc)             # TV|NBC 70 -> 75
  p   <- attach_subplan(std_plan(), tv)             # TV 80 -> 125
  expect_equal(p@data$planned_spend[p@data$channel == "TV"], 125)
  expect_identical(names(p@subplans$TV@subplans), "TV | NBC")
})
