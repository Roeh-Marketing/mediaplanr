# A derived plan records how it was derived (@edits) and why (@rationale).
# The contract worth pinning: the record is canonical and plain JSON;
# replaying it on the parent reproduces the scenario exactly, for every form of
# edit; it belongs to one derivation, so roots and rollups have none and
# nothing inherits it; and edit_log() reads it back as a change log.

oct <- list(from = "2026-10-01", to = "2026-10-31")
mar <- list(from = "2027-03-01", to = "2027-03-31")

flighted <- function() {
  media_plan_from_flights(
    data.frame(channel = c("TV", "OOH"),
               flight_start = as.Date(c("2026-04-06", "2026-04-08")),
               flight_end   = as.Date(c("2026-05-03", "2026-05-03")),
               planned_spend = c(10000, 4000)),
    grain = "channel", name = "flighted")
}

# A plan of spots on New York's clock.
timed <- function() {
  media_plan_from_flights(
    data.frame(channel = "TV", programme = c("Final", "Late"),
               flight_start = c("2026-02-08 20:00:00", "2026-02-08 23:30:00"),
               flight_end   = c("2026-02-08 20:00:30", "2026-02-08 23:59:00"),
               planned_spend = c(450000, 90000)),
    grain = c("channel", "programme"), basis = "instant",
    tz = "America/New_York", name = "spots")
}

round_trip <- function(x) plan_from_json(plan_to_json(x))

# ---- the canonical record ----------------------------------------------------

test_that("ops are recorded operation-first, with dates as text", {
  s <- build_scenario(flighted(), name = "s", edits = list(
    target = list(channel = "TV"), scale = 2L,
    during = list(from = as.Date("2026-04-01"), to = as.Date("2026-04-30"))))
  expect_identical(s@edits, list(form = "ops", ops = list(list(
    scale = 2, target = list(channel = "TV"),
    during = list(from = "2026-04-01", to = "2026-04-30")))))
})

test_that("an allocation is recorded as given, keyed by the plan's own rows", {
  base <- std_plan()
  as_df <- build_scenario(base, name = "df", edits = data.frame(
    week = fix_week(), channel = "Search", planned_spend = 60))
  as_vector <- build_scenario(base, name = "vec", edits = at_cell(Search = 60))

  want <- data.frame(channel = "Search", week = "2026-07-06",
                     planned_spend = 60, stringsAsFactors = FALSE)
  expect_identical(as_df@edits, list(form = "allocation", data = want))
  expect_identical(as_vector@edits, as_df@edits)
})

test_that("an added flight's id is minted into the record", {
  s <- build_scenario(flighted(), name = "s", edits = op_add(
    channel = "Audio", flight_start = "2026-04-13", flight_end = "2026-04-26",
    planned_spend = 2000))
  id <- s@edits$ops[[1]]$add$flight_id
  expect_match(id, "^fl_")
  expect_identical(unique(s@data$flight_id[s@data$channel == "Audio"]), id)
})

test_that("a flight_id given to a single-period add does not join a flight", {
  p <- flighted()
  tv_flight <- p@data$flight_id[p@data$channel == "TV"][1]
  s <- build_scenario(p, name = "s", edits = op_add(
    channel = "Radio", week = "2026-04-06", planned_spend = 5,
    flight_id = tv_flight))
  expect_true(is.na(s@data$flight_id[s@data$channel == "Radio"]))
})

# ---- replay ------------------------------------------------------------------

test_that("replaying @edits on the parent reproduces the scenario exactly", {
  a <- fix_agency_plan()
  f <- flighted()
  cases <- list(
    list(a, op_set(50000, target = list(partner = "DSP A"), during = oct)),
    list(a, op_scale(0.9, target = list(channel = "Programmatic"))),
    list(a, op_delta(-25000, target = list(channel = "Streaming"))),
    list(a, op_delta_each(500, target = list(partner = "Video B"))),
    list(a, op_total(500000, target = list(channel = "Programmatic"))),
    list(a, op_transfer(18000, from = list(partner = "Stream B"),
                        to = list(partner = "Video B"),
                        from_during = oct, to_during = mar)),
    list(a, op_rebound(min = 10000, max = NA,
                       target = list(partner = "Video A",
                                     tactic = "Prospecting"))),
    list(a, op_drop(target = list(tactic = "Added Value"))),
    list(f, op_add(channel = "Audio", flight_start = "2026-04-13",
                   flight_end = "2026-04-26", planned_spend = 2000,
                   min_spend = 1000)),
    list(f, op_add(channel = "Radio", week = "2026-04-06",
                   planned_spend = 300)),
    list(f, op_shift(7, target = list(channel = "OOH"))),
    list(f, op_restage("2026-05-04", "2026-05-31",
                       target = list(channel = "TV"))),
    list(a, data.frame(month = as.Date("2026-11-01"), channel = "Programmatic",
                       partner = "DSP A", campaign = "Brand",
                       tactic = "Prospecting", planned_spend = 1000)),
    list(std_plan(), at_cell(TV = 20, Social = 100))
  )
  for (case in cases) {
    parent <- case[[1]]
    s <- build_scenario(parent, edits = case[[2]], name = "s")
    label <- if (is.data.frame(case[[2]]) || is.numeric(case[[2]])) {
      "allocation"
    } else {
      .op_key(case[[2]])
    }
    expect_identical(.replay(parent, s@edits), s@data, label = label)
    # and again from the record as read back from JSON
    expect_identical(.replay(parent, round_trip(s)@edits), s@data,
                     label = paste(label, "after JSON"))
  }
})

# ---- set and reset -----------------------------------------------------------

test_that("roots and rollups record no provenance; scenarios record their own", {
  base <- fix_agency_plan()
  expect_identical(base@edits, list())
  expect_identical(base@rationale, list())
  expect_identical(flighted()@edits, list())

  s1 <- build_scenario(base, name = "s1",
                       edits = op_scale(1.1, target = list(partner = "Stream B")),
                       rationale = list(author = "agent", goal = "grow"))
  expect_identical(s1@rationale, list(author = "agent", goal = "grow"))

  # a scenario of a scenario has its own record, and inherits neither
  s2 <- build_scenario(s1, name = "s2", edits = op_delta(-100))
  expect_identical(s2@edits$ops, list(list(delta = -100)))
  expect_identical(s2@rationale, list())

  r <- roll_up(s1, "channel")
  expect_identical(r@edits, list())
  expect_identical(r@rationale, list())
})

test_that("revise() and subplans keep provenance, and revise can set rationale", {
  s <- build_scenario(std_plan(), name = "s", edits = op_scale(2),
                      rationale = list(author = "human"))
  r <- revise(s, status = "to review",
              rationale = list(author = "human", notes = "checked by finance"))
  expect_identical(r@edits, s@edits)
  expect_identical(r@rationale$notes, "checked by finance")

  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(100, 60)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  top <- attach_subplan(s, tv)
  expect_identical(top@edits, s@edits)
  expect_identical(detach_subplan(top, "TV")@rationale, s@rationale)
})

# ---- validation --------------------------------------------------------------

test_that("rationale holds only the known keys, each of its type", {
  build <- function(r) build_scenario(std_plan(), edits = op_scale(2),
                                      name = "s", rationale = r)
  expect_error(build(list(mood = "upbeat")), "may hold only author, goal")
  expect_error(build(list(author = "intern")), "author must be one of: human")
  expect_error(build(list(goal = c("a", "b"))), "goal must be a single string")
  expect_error(build(list(forecast = list(revenue = "lots"))),
               "forecast must be a named list of single numbers")
  expect_no_error(build(list(author = "optimizer", constraints_id = "c1",
                             forecast = list(revenue = 1.2e6, roas = 2.1))))
})

test_that("a plan can only record edits against a parent", {
  expect_error(
    .copy_plan(std_plan(), edits = list(form = "ops", ops = list(list(scale = 2)))),
    "@edits is set but @parent_id is empty")
  s <- build_scenario(std_plan(), edits = op_scale(2), name = "s")
  expect_error(.copy_plan(s, edits = list(form = "diff")),
               "form must be \"ops\" or \"allocation\"")
})

# ---- JSON --------------------------------------------------------------------

test_that("provenance round-trips through JSON, multi-value targets and all", {
  s <- build_scenario(fix_agency_plan(), name = "s", edits = list(
    op_scale(1.1, target = list(partner = c("Video A", "Stream B"))),
    op_scale(0.9, target = list(partner = "DSP A")),
    op_rebound(max = NA, target = list(partner = "Video A"))),
    rationale = list(author = "agent", forecast = list(revenue = 1200000)))
  back <- round_trip(s)
  expect_identical(back@edits, s@edits)
  expect_identical(back@rationale, s@rationale)
  # a one-value target stays a vector, not a one-element list
  expect_identical(back@edits$ops[[2]]$target$partner, "DSP A")
})

test_that("moments are recorded on the plan's clock and replay to the same instant", {
  p <- timed()
  # 01:00 UTC on the 9th is 20:00 on the 8th in New York
  utc <- as.POSIXct("2026-02-09 01:00:00", tz = "UTC")
  s <- build_scenario(p, name = "s", edits = list(
    op_scale(2, during = list(from = utc, to = utc)),
    op_add(channel = "TV", programme = "Encore",
           flight_start = as.POSIXct("2026-02-09 03:00:00", tz = "UTC"),
           flight_end   = as.POSIXct("2026-02-09 03:00:30", tz = "UTC"),
           planned_spend = 1000)))
  expect_identical(s@edits$ops[[1]]$during$from, "2026-02-08 20:00:00")
  expect_identical(s@edits$ops[[2]]$add$flight_start, "2026-02-08 22:00:00")
  expect_equal(s@data$planned_spend[s@data$programme == "Final"], 900000)

  back <- round_trip(s)
  expect_identical(back@edits, s@edits)
  expect_identical(.replay(p, back@edits), s@data)
})

test_that("a file from before provenance reads as a plan with none", {
  s <- build_scenario(std_plan(), edits = op_scale(2), name = "s")
  js <- jsonlite::fromJSON(plan_to_json(s), simplifyVector = FALSE)
  js$edits <- NULL
  js$rationale <- NULL
  js$schema_version <- 3L
  old <- plan_from_json(jsonlite::toJSON(js, auto_unbox = TRUE, null = "null"))
  expect_identical(old@edits, list())
  expect_equal(old@data$planned_spend, s@data$planned_spend)
})

# ---- edit_log() --------------------------------------------------------------

test_that("edit_log() lays out a three-generation chain, in lineage order", {
  base <- fix_agency_plan(name = "base")
  s1 <- build_scenario(base, name = "Move to regional", nickname = "s1",
    objective = "Shift programmatic to regional streaming",
    rationale = list(author = "agent"),
    edits = list(
      op_transfer(37419, from = list(partner = "DSP A"),
                  to = list(channel = "Streaming", tactic = "Regional"),
                  during = oct),
      op_scale(1.1, target = list(partner = c("Video A", "Stream B")))))
  s2 <- build_scenario(s1, name = "Add audio", nickname = "s2",
    rationale = list(author = "human"),
    edits = list(
      op_add(channel = "Audio", partner = "Audio A", campaign = "Brand",
             tactic = "Prospecting", month = "2026-12-01",
             planned_spend = 8000),
      op_rebound(min = 10000, target = list(partner = "Video A",
                                            tactic = "Prospecting"))))
  s3 <- build_scenario(s2, name = "Optimised", nickname = "s3",
    rationale = list(author = "optimizer"),
    edits = data.frame(month = as.Date("2026-11-01"), channel = "Programmatic",
                       partner = "DSP A", campaign = "Brand",
                       tactic = "Prospecting", planned_spend = 40000))

  # added out of order: the log still reads parent before child
  set <- add_scenario(add_scenario(add_scenario(scenario_set(base), s3), s1), s2)
  log <- edit_log(set)

  expect_identical(log$scenario, c("s1", "s1", "s2", "s2", "s3"))
  expect_identical(log$parent, c("base", "base", "s1", "s1", "s2"))
  expect_identical(log$author, c("agent", "agent", "human", "human", "optimizer"))
  expect_identical(log$op, c("transfer", "scale", "add", "rebound", "allocation"))

  move <- log[1, ]
  expect_identical(move$target, "partner DSP A")
  expect_identical(move$to, "channel | tactic Streaming | Regional")
  expect_equal(move$amount, 37419)
  expect_identical(move$window, "2026-10-01..2026-10-31")
  expect_identical(move$objective, "Shift programmatic to regional streaming")

  expect_identical(log$target[2], "partner Video A/Stream B")
  expect_identical(log$detail[2], "x1.1")
  expect_identical(log$target[3],
                   "channel | partner | campaign | tactic Audio | Audio A | Brand | Prospecting")
  expect_equal(log$amount[3], 8000)
  expect_identical(log$detail[4], "min 10,000")
  # an allocation's amount is the net change in the plan's total
  expect_equal(log$amount[5],
               sum(s3@data$planned_spend) - sum(s2@data$planned_spend))
})

test_that("edit_log() names a parent outside the set by its short id", {
  s <- build_scenario(std_plan(), edits = op_scale(2), name = "s")
  log <- edit_log(scenario_set(s))
  expect_identical(log$parent, short_id(s@parent_id))
  expect_true(is.na(log$author))
})

test_that("edit_log() of a set with no edits is empty, with its columns", {
  log <- edit_log(scenario_set(std_plan()))
  expect_identical(nrow(log), 0L)
  expect_identical(names(log), c("scenario", "parent", "author", "op", "target",
                                 "to", "amount", "detail", "window",
                                 "objective"))
})
