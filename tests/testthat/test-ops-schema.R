# plan_ops_schema() is the contract an agent's ops are checked against before R
# sees them. These tests run it through the small checker in
# helper-json-schema.R over a corpus of ops: the good ones must pass, the bad
# ones must not, and on a plan the good ones must also build.

parse_json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)

# The schema as an agent receives it: through JSON text, so a one-element
# array that lost its brackets on the way out would show up here.
schema_for <- function(plan = NULL) parse_json(plan_ops_schema(plan, as_json = TRUE))

# The schema of one op, by its title.
op_schema <- function(schema, key) {
  Filter(function(op) identical(op$title, key), schema$items$oneOf)[[1]]
}

# Problems with one op, wrapped as the one-item edits array it would arrive in.
op_problems <- function(op_json, schema) {
  schema_problems(parse_json(paste0("[", op_json, "]")), schema)
}

# Weekly, flighted, channels TV / Search / Social, all starting 2026-07-06.
schema_plan <- function() {
  media_plan_from_flights(
    data.frame(channel = c("TV", "Search", "Social"),
               flight_start = as.Date("2026-07-06"),
               flight_end   = as.Date(c("2026-07-26", "2026-07-19", "2026-07-12")),
               planned_spend = c(300, 200, 100)),
    grain = "channel", name = "schema")
}

# One of every op, each legal on schema_plan().
good_ops <- c(
  '{"set": 50}',
  '{"scale": 1.2, "target": {"channel": "TV"}}',
  '{"scale": 1.2, "target": {"channel": ["TV", "Search"]}}',
  '{"delta": -10, "target": {"channel": "TV"},
    "during": {"from": "2026-07-01", "to": "2026-07-12"}}',
  '{"delta_each": -5, "target": {"week": "2026-07-13"}}',
  '{"total": 900}',
  '{"add": {"channel": "Audio", "week": "2026-07-06", "planned_spend": 25}}',
  '{"add": {"channel": "Audio", "flight_start": "2026-07-06",
            "flight_end": "2026-07-19", "planned_spend": 25}}',
  '{"drop": true, "target": {"channel": "Social"}}',
  '{"shift": 7, "target": {"channel": "Social"}}',
  '{"restage": {"from": "2026-08-03", "to": "2026-08-16"},
    "target": {"channel": "Search"}}'
)

# Wrong whatever the plan.
bad_ops <- c(
  no_operation   = '{"target": {"channel": "TV"}}',
  two_operations = '{"scale": 1.2, "delta": 5}',
  text_number    = '{"scale": "1.2"}',
  negative_set   = '{"set": -5}',
  part_days      = '{"shift": 2.5}',
  drop_false     = '{"drop": false}',
  stray_field    = '{"scale": 1, "channel": "TV"}',
  half_window    = '{"scale": 1, "during": {"from": "2026-07-01"}}',
  unread_date    = '{"scale": 1, "during": {"from": "July", "to": "2026-07-31"}}',
  add_no_spend   = '{"add": {"channel": "Audio", "week": "2026-07-06"}}',
  add_half_fl    = '{"add": {"channel": "Audio", "planned_spend": 5,
                             "flight_start": "2026-07-06"}}',
  add_target     = '{"add": {"channel": "Audio", "week": "2026-07-06",
                             "planned_spend": 5}, "target": {"channel": "TV"}}'
)

# Shaped right, but wrong on schema_plan() in particular.
bad_on_plan <- c(
  unknown_value  = '{"scale": 1, "target": {"channel": "Radio"}}',
  not_grain      = '{"scale": 1, "target": {"partner": "X"}}',
  clock_on_week  = '{"scale": 1, "during": {"from": "2026-07-01 08:00",
                                           "to": "2026-07-31"}}',
  add_no_channel = '{"add": {"week": "2026-07-06", "planned_spend": 5}}',
  add_no_when    = '{"add": {"channel": "Audio", "planned_spend": 5}}',
  add_both_whens = '{"add": {"channel": "Audio", "week": "2026-07-06",
                             "flight_start": "2026-07-06",
                             "flight_end": "2026-07-19", "planned_spend": 5}}',
  add_new_column = '{"add": {"channel": "Audio", "week": "2026-07-06",
                             "planned_spend": 5, "partner": "X"}}'
)

# ---- the plan-free schema ----------------------------------------------------

test_that("the plan-free schema accepts one of every op", {
  schema <- schema_for()
  for (op in good_ops) expect_identical(op_problems(op, schema), character(0),
                                        info = op)
})

test_that("the plan-free schema refuses malformed ops", {
  schema <- schema_for()
  for (nm in names(bad_ops)) {
    expect_gt(length(op_problems(bad_ops[[nm]], schema)), 0, label = nm)
  }
  expect_gt(length(schema_problems(list(), schema)), 0, label = "empty edits")
})

test_that("the plan-free schema has one shape per registered op", {
  titles <- vapply(schema_for()$items$oneOf, function(op) op$title, "")
  expect_identical(titles, .op_keys)
})

test_that("constructor-built ops satisfy the schema once serialized", {
  ops <- list(
    op_scale(1.2, target = list(channel = c("TV", "Search"))),
    op_add(channel = "Audio", week = "2026-07-06", planned_spend = 25),
    op_drop(target = list(channel = "Social")),
    op_restage(as.Date("2026-08-03"), as.Date("2026-08-16"))
  )
  json <- jsonlite::toJSON(ops, auto_unbox = TRUE)
  expect_identical(schema_problems(parse_json(json), schema_for()), character(0))
})

# ---- the schema for one plan -------------------------------------------------

test_that("on a plan, every good op passes the schema and builds", {
  plan <- schema_plan()
  schema <- schema_for(plan)
  for (op in good_ops) {
    expect_identical(op_problems(op, schema), character(0), info = op)
    expect_no_error(build_scenario(plan, edits = parse_json(paste0("[", op, "]")),
                                   name = "s"))
  }
})

test_that("on a plan, the schema refuses what the plan cannot take", {
  schema <- schema_for(schema_plan())
  for (nm in names(c(bad_ops, bad_on_plan))) {
    expect_gt(length(op_problems(c(bad_ops, bad_on_plan)[[nm]], schema)), 0,
              label = nm)
  }
})

test_that("what only the plan forbids passes the plan-free schema", {
  # The narrowing is the point: these are well-formed ops, wrong for this plan.
  schema <- schema_for()
  for (nm in c("unknown_value", "not_grain", "clock_on_week")) {
    expect_identical(op_problems(bad_on_plan[[nm]], schema), character(0),
                     info = nm)
  }
})

test_that("a plan's target lists its grain columns and their values", {
  target <- op_schema(schema_for(schema_plan()), "scale")$properties$target
  expect_identical(names(target$properties), c("channel", "week"))
  expect_setequal(unlist(target$properties$channel$anyOf[[1]]$enum),
                  c("TV", "Search", "Social"))
  expect_setequal(unlist(target$properties$week$anyOf[[1]]$enum),
                  c("2026-07-06", "2026-07-13", "2026-07-20"))
  expect_false(target$additionalProperties)
})

test_that("dates take the shape of the plan's time basis", {
  date_only <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
  weekly <- op_schema(schema_for(schema_plan()), "scale")
  expect_identical(weekly$properties$during$properties$from$pattern, date_only)

  spots <- media_plan_from_flights(
    data.frame(channel = "TV",
               flight_start = as.POSIXct("2026-04-06 20:00:00", tz = "UTC"),
               flight_end   = as.POSIXct("2026-04-06 20:00:30", tz = "UTC"),
               planned_spend = 1000),
    grain = "channel", basis = "instant", name = "spots")
  timed <- op_schema(schema_for(spots), "scale")$properties$during
  expect_false(identical(timed$properties$from$pattern, date_only))
  window <- '{"scale": 1, "during": {"from": "2026-04-06 19:00", "to": "2026-04-06"}}'
  expect_identical(op_problems(window, schema_for(spots)), character(0))
})

test_that("plan_ops_schema() refuses something that is not a plan", {
  expect_error(plan_ops_schema(data.frame()), "must be a MediaPlan")
})
