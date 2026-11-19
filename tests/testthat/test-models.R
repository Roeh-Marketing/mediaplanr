# model_map() and spend_by_model() decide which response model scores which
# spend. The contract worth pinning: the most specific matching model wins, a
# tie is an error rather than a guess, unmodeled spend is warned about and kept
# (never dropped), and every total reconciles to the plan, on any calendar.

map_of <- function(plan, models) {
  suppressWarnings(model_map(plan, models))
}

model_for <- function(map, line_item) map$model_id[map$line_item == line_item]

# ---- resolution ----------------------------------------------------------------

test_that("models at the plan's own grain map one to one", {
  a <- fix_agency_plan()
  roster <- line_item_summary(a)
  models <- roster[, c("channel", "partner", "campaign", "tactic")]
  models$model_id <- paste0("m", seq_len(nrow(models)))

  map <- model_map(a, models)
  expect_identical(map$model_id, models$model_id)
  expect_true(all(map$match_level == "channel + partner + campaign + tactic"))
})

test_that("the most specific matching model wins, the coarser one is the fallback", {
  map <- map_of(fix_agency_plan(), fix_agency_models())
  # DSP A has its own model; DSP B falls back to the channel's
  expect_identical(model_for(map, "Programmatic | DSP A | Brand | Prospecting"),
                   "dsp_a")
  expect_identical(model_for(map, "Programmatic | DSP B | Promo | Prospecting"),
                   "programmatic")
  # Video A prospecting's model names a tactic; its added value falls back
  expect_identical(model_for(map, "Online Video | Video A | Brand | Prospecting"),
                   "video_a_prospecting")
  expect_identical(model_for(map, "Online Video | Video A | Brand | Added Value"),
                   "online_video")
  expect_identical(map$match_level[map$model_id %in% "programmatic"], "channel")
  expect_identical(map$match_level[map$model_id %in% "video_a_prospecting"],
                   "channel + partner + tactic")
})

test_that("two equally specific matches are an error naming both", {
  models <- rbind(fix_agency_models(),
                  data.frame(model_id = "promo", channel = "", partner = "",
                             campaign = "Promo", tactic = ""))
  expect_error(model_map(fix_agency_plan(), models),
               "equally specific.*Programmatic \\| DSP B \\| Promo \\| Prospecting \\(programmatic, promo\\)")
})

test_that("a model with no line item columns covers the whole plan", {
  map <- model_map(std_plan(), data.frame(model_id = "total_media"))
  expect_true(all(map$model_id == "total_media"))
  expect_true(all(map$match_level == ""))
})

# ---- the models, checked -------------------------------------------------------

test_that("a malformed model list errors, naming the fix", {
  a <- fix_agency_plan()
  expect_error(model_map(a, data.frame(channel = "Streaming")),
               "needs* .*model_id|with a `model_id` column")
  expect_error(model_map(a, data.frame(model_id = "x", market = "US")),
               "do not have: market. It may use: channel, partner")
  expect_error(model_map(a, data.frame(model_id = c("x", "x"),
                                       channel = c("Streaming", "Programmatic"))),
               "must be unique; repeated: x")
  expect_error(model_map(a, data.frame(model_id = c("x", "y"),
                                       channel = "Streaming")),
               "x and y cover exactly the same line items")
})

# ---- what no model covers ----------------------------------------------------------

test_that("unmodeled spend is warned about, with its share", {
  expect_warning(
    map <- model_map(fix_agency_plan(), fix_agency_models()),
    paste0("1 line item\\(s\\) have no model: Streaming \\| Stream B \\| Promo \\| ",
           "Regional \\(60,000\\)\\. 60,000 of 1,320,600 planned spend \\(4.5%\\)"))
  expect_true(is.na(model_for(map, "Streaming | Stream B | Promo | Regional")))
  expect_true(is.na(map$match_level[is.na(map$model_id)]))
})

test_that("unmodeled spend is kept under model_id NA, never dropped", {
  s <- suppressWarnings(spend_by_model(fix_agency_plan(), fix_agency_models(),
                                       basis = "month"))
  expect_equal(sum(s$planned_spend[is.na(s$model_id)]), 60000)
  expect_true(all(is.na(utils::tail(s$model_id, 6))))   # unmodeled last
})

# ---- totals reconcile --------------------------------------------------------------

test_that("spend by model reconciles to the plan on every calendar", {
  a <- fix_agency_plan()
  map <- map_of(a, fix_agency_models())
  # NA cannot index by name, so the unmodeled bucket gets a label here.
  label <- function(id) ifelse(is.na(id), "(unmodeled)", id)
  want  <- tapply(map$planned_spend, label(map$model_id), sum)
  for (basis in c("day", "week", "month")) {
    s <- suppressWarnings(spend_by_model(a, fix_agency_models(), basis = basis))
    expect_equal(sum(s$planned_spend), sum(a@data$planned_spend), info = basis)
    by_model <- tapply(s$planned_spend, label(s$model_id), sum)
    expect_equal(by_model[names(want)], want, info = basis)
    expect_true(basis %in% names(s))
  }
})

test_that("units ride along where a model's rows share one unit type", {
  s <- suppressWarnings(spend_by_model(fix_agency_plan(), fix_agency_models(),
                                       basis = "month"))
  dsp_a <- s[s$model_id %in% "dsp_a", ]
  expect_true(all(dsp_a$unit_type == "impression"))
  expect_equal(dsp_a$planned_units, dsp_a$planned_spend * 1000 / dsp_a$planned_rate)

  mixed <- media_plan_from_df(
    data.frame(week = fix_week(), channel = c("Social", "Search"),
               unit_type = c("impression", "click"),
               planned_spend = c(100, 50), planned_rate = c(5, 2)),
    grain = "channel", time = "week", name = "mixed")
  s <- spend_by_model(mixed, data.frame(model_id = "digital"))
  expect_true(is.na(s$planned_units))               # clicks and impressions
  expect_equal(s$planned_spend, 150)
})

test_that("a flighted plan and a plan of moments land on the calendar", {
  flighted <- media_plan_from_flights(
    data.frame(channel = c("TV", "OOH"),
               flight_start = as.Date(c("2026-04-08", "2026-04-06")),
               flight_end   = as.Date(c("2026-05-03", "2026-04-19")),
               planned_spend = c(2600, 1400)),
    grain = "channel", name = "flighted")
  s <- spend_by_model(flighted, data.frame(model_id = c("tv", "ooh"),
                                           channel = c("TV", "OOH")))
  expect_equal(s$planned_spend[s$model_id == "tv"], c(500, 700, 700, 700))
  expect_equal(sum(s$planned_spend), 4000)

  spots <- media_plan_from_flights(
    data.frame(channel = "TV", programme = c("Final", "Late"),
               flight_start = c("2026-02-08 20:00:00", "2026-02-09 21:00:00"),
               flight_end   = c("2026-02-08 20:00:30", "2026-02-09 21:30:00"),
               planned_spend = c(450000, 90000)),
    grain = c("channel", "programme"), basis = "instant", name = "spots")
  s <- spend_by_model(spots, data.frame(model_id = "tv", channel = "TV"),
                      basis = "day")
  expect_equal(s$planned_spend, c(450000, 90000))
  expect_identical(format(s$day), c("2026-02-08", "2026-02-09"))
})

# ---- in describe_plan() ------------------------------------------------------------

test_that("describe_plan() reports coverage and the largest gaps", {
  m <- describe_plan(fix_agency_plan(), models = fix_agency_models())$models
  expect_equal(m$modeled_share, round(1 - 60000 / 1320600, 4))
  expect_equal(m$unmodeled_spend, 60000)
  expect_identical(m$n_models_used, 6L)
  expect_identical(m$unmodeled$line_item, "Streaming | Stream B | Promo | Regional")
  expect_identical(m$n_more_unmodeled, 0L)
})
