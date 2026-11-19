# Shared fixtures. The package depends on nothing but S7, so these are plain
# data frames — no model objects or sampler required.
#
# Every plan is keyed by time, so the flat fixtures are single-week plans: one
# week keeps their totals and row counts simple while still being a real
# calendar. `line_item()` keys therefore read "TV | 2026-07-06".

# The week the flat fixtures are planned for.
fix_week <- function() as.Date("2026-07-06")

# Base plan at channel grain (total planned_spend = 160).
std_plan <- function(name = "base") {
  media_plan_from_df(
    data.frame(
      week = fix_week(),
      channel = c("TV", "Search", "Social"),
      planned_spend = c(80, 40, 40),
      stringsAsFactors = FALSE
    ),
    grain = "channel", time = "week", name = name
  )
}

# Plan at a finer grain (channel + partner).
fine_plan <- function(name = "fine") {
  media_plan_from_df(
    data.frame(
      week = fix_week(),
      channel = c("TV", "TV", "Search", "Social"),
      partner = c("A", "B", "X", "Y"),
      planned_spend = c(50, 30, 40, 40),
      stringsAsFactors = FALSE
    ),
    grain = c("channel", "partner"), time = "week", name = name
  )
}

# A weekly plan spanning history and future, relative to a decomp through-date
# of 2026-03-15. The historical portion holds TV|NBC and Search|Google; the
# future portion adds the new partner TV|Hulu.
weekly_df <- function() {
  data.frame(
    week = as.Date(c("2026-03-02", "2026-03-02",
                     "2026-04-06", "2026-04-06", "2026-04-06")),
    channel = c("TV", "Search", "TV", "TV", "Search"),
    partner = c("NBC", "Google", "NBC", "Hulu", "Google"),
    planned_spend = c(30, 20, 35, 15, 25),
    stringsAsFactors = FALSE
  )
}

weekly_plan <- function(name = "weekly") {
  media_plan_from_df(weekly_df(), grain = c("channel", "partner"),
                     time = "week", name = name)
}

# A synthetic agency plan, shaped like a real national digital plan but with
# no client in it. Monthly across two quarters (Q4 2026, Q1 2027), three
# channels, keyed channel + partner + campaign + tactic, and bought in
# impressions at CPM rates. It carries the awkward cases real plans have:
#
#   - Online Video | Video B | Promo | Regional plans nothing: a slot held open.
#   - Online Video | Video A | Brand | Added Value is bonus inventory at a
#     token rate.
#   - Streaming | Stream A | Brand | Upfront is committed: min = max = spend
#     in every month, so no edit can move it.
#   - Programmatic | DSP B is a partner with a floor of 15,000 a month.
#   - Online Video | Video A | Brand | Prospecting is capped at 60,000 a month.
#
# 9 line items x 6 months = 54 rows; total planned spend 1,320,600, of which
# 360,000 is committed and 90,000 is floor. Spend is heavier into the holidays
# and lighter after (x1.2, 1.3, 1.0, 0.7, 0.8, 1.0 by month).
#
# The table ships with the package as inst/extdata/agency_plan.csv, which the
# getting-started vignette imports, so the tests and the docs use one plan.
fix_agency_df <- function() {
  utils::read.csv(
    system.file("extdata", "agency_plan.csv", package = "mediaplanr"),
    stringsAsFactors = FALSE,
    # Whole-number spends would otherwise read as integers.
    colClasses = c(planned_spend = "numeric", planned_rate = "numeric",
                   min_spend = "numeric", max_spend = "numeric"))
}

# Response models for the agency plan, fitted at mixed grains -- shipped as
# inst/extdata/agency_models.csv, blank cells meaning "any value":
#
#   Streaming      one model per partner; Stream B's covers its Brand campaign
#                  only, so Stream B | Promo | Regional (60,000) has none
#   Programmatic   a channel model, and a partner model for DSP A that takes
#                  precedence over it; DSP B falls back to the channel's
#   Online Video   a channel model, and one for Video A prospecting
fix_agency_models <- function() {
  utils::read.csv(
    system.file("extdata", "agency_models.csv", package = "mediaplanr"),
    stringsAsFactors = FALSE)
}

fix_agency_plan <- function(name = "agency") {
  media_plan_from_df(fix_agency_df(),
                     grain = c("channel", "partner", "campaign", "tactic"),
                     time = "month", name = name)
}

# The key line_item() gives a flat-fixture cell, e.g. cell("TV").
cell <- function(...) paste(c(..., format(fix_week())), collapse = " | ")

# A named-vector edit keyed the way line_item() keys a flat fixture:
#   at_cell(TV = 200)  ->  c("TV | 2026-07-06" = 200)
at_cell <- function(...) {
  v <- c(...)
  stats::setNames(v, vapply(names(v), cell, character(1)))
}
