# A plan crosses the app boundary as JSON. The contract worth pinning: the
# rebuilt plan is faithful (same data, grain, id, lineage) and clean
# (re-validated and unit-solved on the way in). Flighted and mixed plans travel
# through the same door as weekly ones, with no special casing.

rt <- function(p) plan_from_json(plan_to_json(p))

# JSON is row-wise, so column and row order may move; compare content only.
norm <- function(d) {
  d <- d[order(names(d))]
  d <- d[do.call(order, c(as.list(d), list(na.last = TRUE))), , drop = FALSE]
  rownames(d) <- NULL
  d
}

# ---- faithful round-trips ----------------------------------------------------

test_that("a weekly plan round-trips faithfully, keeping id and lineage", {
  p <- weekly_plan()
  q <- rt(p)
  expect_equal(norm(q@data), norm(p@data))
  expect_identical(q@grain, p@grain)
  expect_identical(q@week_col, p@week_col)
  expect_identical(q@id, p@id)
  expect_identical(q@parent_id, p@parent_id)
})

test_that("a length-1 grain survives auto_unbox", {
  p <- std_plan()
  q <- rt(p)
  expect_identical(q@grain, p@grain)
  expect_equal(norm(q@data), norm(p@data))
})

test_that("a geo plan (extra grain column) round-trips", {
  p <- media_plan_from_df(
    data.frame(region = c("NE", "NE", "W", "W"),
               channel = c("TV", "Search", "TV", "Search"),
               planned_spend = c(1000, 2000, 3000, 4000),
               stringsAsFactors = FALSE),
    grain = c("region", "channel"), name = "Geo"
  )
  q <- rt(p)
  expect_identical(q@grain, p@grain)
  expect_equal(norm(q@data), norm(p@data))
})

test_that("a units plan re-solves the identity on the way in", {
  p <- media_plan_from_df(
    data.frame(channel = "Social", unit_type = "impression",
               planned_spend = 140000, planned_rate = 5,
               stringsAsFactors = FALSE),
    grain = "channel", name = "Social"
  )
  q <- rt(p)
  expect_equal(norm(q@data), norm(p@data))
  expect_equal(q@data$planned_units, p@data$planned_units)
})

# ---- flights need no special path --------------------------------------------

test_that("a flighted plan round-trips and recovers its buys", {
  p <- media_plan_from_flights(
    data.frame(channel = c("OOH", "Search", "TV"),
               partner = c("JCDecaux", "Google", "NBC"),
               flight_start = as.Date(c("2026-04-06", "2026-04-08", "2026-04-06")),
               flight_end   = as.Date(c("2026-05-03", "2026-04-08", "2026-04-12")),
               planned_spend = c(120000, 3100, 33333),
               stringsAsFactors = FALSE),
    grain = c("channel", "partner"), name = "flights"
  )
  q <- rt(p)
  expect_equal(norm(q@data), norm(p@data))
  expect_equal(nrow(flights(q)), nrow(flights(p)))
  expect_equal(sort(flights(q)$planned_spend), sort(flights(p)$planned_spend))
})

test_that("a mixed plan (some rows flighted, some not) round-trips", {
  mixed <- build_scenario(
    weekly_plan(),
    edits = list(add = list(
      channel = "OOH", partner = "JCDecaux",
      flight_start = as.Date("2026-04-08"), flight_end = as.Date("2026-05-03"),
      planned_spend = 90000)),
    name = "mixed"
  )
  q <- rt(mixed)
  expect_equal(norm(q@data), norm(mixed@data))
  expect_equal(nrow(flights(q)), 1L)
  # the rows that were never a flight keep NA in the flight columns
  expect_true(any(is.na(q@data$flight_id)))
})

# ---- schema, files, and guards -----------------------------------------------

test_that("schema_version is written and a newer one warns", {
  js <- plan_to_json(std_plan(), pretty = FALSE)
  expect_match(js, "\"schema_version\":2")

  newer <- sub("\"schema_version\":2", "\"schema_version\":999", js, fixed = TRUE)
  expect_warning(plan_from_json(newer), "schema_version")
})

test_that("a v1 file, with neither revision nor subplans, still reads", {
  v1 <- '{"object":"MediaPlan","schema_version":1,
          "data":[{"channel":"TV","planned_spend":80},
                  {"channel":"Search","planned_spend":40}],
          "grain":"channel","week_col":[],"id":"plan_1_abc","parent_id":[],
          "name":"old","nickname":"","advertiser":"","planner":"",
          "status":"","objective":""}'
  p <- plan_from_json(v1)
  expect_identical(p@revision, 1L)
  expect_identical(p@subplans, list())
  expect_identical(p@id, "plan_1_abc")
  expect_equal(sum(p@data$planned_spend), 120)
})

test_that("plan_to_json and plan_from_json survive a file round-trip", {
  p <- weekly_plan()
  f <- withr::local_tempfile(fileext = ".json")
  expect_identical(plan_to_json(p, path = f), f)
  q <- plan_from_json(f)
  expect_equal(norm(q@data), norm(p@data))
  expect_identical(q@grain, p@grain)
})

test_that("non-plan JSON and non-plan input error clearly", {
  expect_error(plan_from_json('{"foo":1}'), "not a plan")
  expect_error(plan_to_json(list(a = 1)), "must be a MediaPlan")
})

# ---- revision and subplans ---------------------------------------------------

sub_tv <- function() {
  media_plan_from_df(
    data.frame(channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50), stringsAsFactors = FALSE),
    grain = c("channel", "partner"), name = "TV detail")
}

test_that("revision survives the trip", {
  q <- rt(revise(std_plan(), revision = 3))
  expect_identical(q@revision, 3L)
})

test_that("a flat plan writes no subplans key", {
  expect_false(grepl("subplans", plan_to_json(std_plan(), pretty = FALSE)))
})

test_that("a topline round-trips with its subplans attached and its rows reconciled", {
  p <- attach_subplan(std_plan(), sub_tv())
  js <- plan_to_json(p, pretty = FALSE)
  expect_match(js, "\"subplans\":\\{\"TV\":\\{")
  q <- rt(p)
  expect_identical(names(q@subplans), "TV")
  expect_identical(q@subplans$TV@id, p@subplans$TV@id)
  expect_equal(norm(q@subplans$TV@data), norm(p@subplans$TV@data))
  expect_equal(norm(q@data), norm(p@data))
  expect_identical(q@id, p@id)
  expect_true(is_topline(q))
})

test_that("a key with the separator in it survives", {
  p <- attach_subplan(fine_plan(), media_plan_from_df(
    data.frame(channel = "TV", partner = "A", tactic = c("brand", "promo"),
               planned_spend = c(20, 25)),
    grain = c("channel", "partner", "tactic"), name = "tv a"))
  q <- rt(p)
  expect_identical(names(q@subplans), "TV | A")
})

test_that("a hand-drifted parent row is corrected on read, not trusted", {
  p  <- attach_subplan(std_plan(), sub_tv())
  js <- plan_to_json(p, pretty = FALSE)
  # the TV row was written as 120; a hand edit changes it
  drifted <- sub("\"channel\":\"TV\",\"planned_spend\":120",
                 "\"channel\":\"TV\",\"planned_spend\":999", js, fixed = TRUE)
  expect_false(identical(drifted, js))
  q <- plan_from_json(drifted)
  expect_equal(q@data$planned_spend[q@data$channel == "TV"], 120)
})

test_that("a file describing an illegal tree is refused", {
  p  <- attach_subplan(std_plan(), sub_tv())
  js <- plan_to_json(p, pretty = FALSE)
  # make the subplan span two channels
  bad <- sub("\"channel\":\"TV\",\"partner\":\"ESPN\"",
             "\"channel\":\"Search\",\"partner\":\"ESPN\"", js, fixed = TRUE)
  expect_error(plan_from_json(bad), "spans 2 cells")
})

test_that("a file nested too deep is refused", {
  leaf <- '{"data":[{"channel":"TV","planned_spend":1}],"grain":"channel","name":"l"}'
  js <- leaf
  for (i in seq_len(33)) {
    js <- paste0('{"data":[{"channel":"TV","planned_spend":1}],"grain":"channel",',
                 '"name":"n', i, '","subplans":{"TV":', js, '}}')
  }
  expect_error(plan_from_json(js), "more than 32 levels deep")
})

test_that("a nested subplan (two levels) round-trips", {
  nbc <- media_plan_from_df(
    data.frame(channel = "TV", partner = "NBC", daypart = c("prime", "day"),
               planned_spend = c(60, 15)),
    grain = c("channel", "partner", "daypart"), name = "nbc")
  p <- attach_subplan(std_plan(), attach_subplan(sub_tv(), nbc))
  q <- rt(p)
  expect_identical(names(q@subplans$TV@subplans), "TV | NBC")
  expect_equal(q@data$planned_spend[q@data$channel == "TV"], 125)
})

test_that("a set containing a topline keeps its subplans", {
  p   <- attach_subplan(std_plan(), sub_tv())
  set <- add_scenario(scenario_set(p), build_scenario(p, c(Search = 1), name = "s"))
  q   <- plan_from_json(plan_to_json(set))
  expect_true(all(vapply(q@scenarios, is_topline, logical(1))))
})

# ---- scenario sets -----------------------------------------------------------

test_that("a scenario set round-trips: names, grain, baseline, id, and data", {
  base <- weekly_plan()
  set  <- scenario_set(base, name = "base")
  set  <- add_scenario(
    set, build_scenario(base, edits = list(scale = 0.8), name = "trim"),
    name = "trim"
  )

  q <- plan_from_json(plan_to_json(set))
  expect_true(S7::S7_inherits(q, ScenarioSet))
  expect_identical(names(q@scenarios), names(set@scenarios))
  expect_identical(q@grain, set@grain)
  expect_identical(q@base_name, set@base_name)
  expect_identical(q@id, set@id)
  expect_equal(
    lapply(q@scenarios, function(p) norm(p@data)),
    lapply(set@scenarios, function(p) norm(p@data))
  )
  expect_equal(compare_scenarios(q), compare_scenarios(set))
  expect_equal(compare_scenarios(q, "cell"), compare_scenarios(set, "cell"))
})

test_that("a set containing a flighted scenario keeps its buys", {
  base  <- weekly_plan()
  moved <- build_scenario(
    base,
    edits = list(add = list(
      channel = "OOH", partner = "JCDecaux",
      flight_start = as.Date("2026-04-08"), flight_end = as.Date("2026-05-03"),
      planned_spend = 90000)),
    name = "with flight"
  )
  set <- add_scenario(scenario_set(base, name = "base"), moved, name = "flighted")

  q <- plan_from_json(plan_to_json(set))
  expect_equal(norm(q@scenarios[["flighted"]]@data), norm(moved@data))
  expect_equal(nrow(flights(q@scenarios[["flighted"]])), 1L)
  expect_true(any(is.na(q@scenarios[["flighted"]]@data$flight_id)))
})

test_that("the object tag distinguishes a set from a plan", {
  expect_match(plan_to_json(std_plan(), pretty = FALSE),
               "\"object\":\"MediaPlan\"")
  expect_match(plan_to_json(scenario_set(std_plan()), pretty = FALSE),
               "\"object\":\"ScenarioSet\"")
})
