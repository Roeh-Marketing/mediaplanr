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
#
# 9 line items x 6 months = 54 rows; total planned spend 1,320,600.
fix_agency_lines <- function() {
  data.frame(
    channel  = c("Streaming", "Streaming", "Streaming",
                 "Programmatic", "Programmatic", "Programmatic",
                 "Online Video", "Online Video", "Online Video"),
    partner  = c("Stream A", "Stream B", "Stream B",
                 "DSP A", "DSP A", "DSP B",
                 "Video A", "Video A", "Video B"),
    campaign = c("Brand", "Brand", "Promo",
                 "Brand", "Promo", "Promo",
                 "Brand", "Brand", "Promo"),
    tactic   = c("Upfront", "Prospecting", "Regional",
                 "Prospecting", "Retargeting", "Prospecting",
                 "Prospecting", "Added Value", "Regional"),
    monthly  = c(60000, 30000, 10000, 40000, 20000, 25000, 35000, 100, 0),
    planned_rate = c(30, 28, 22, 8, 6, 7, 15, 0.05, 12),
    stringsAsFactors = FALSE
  )
}

fix_agency_df <- function() {
  months <- seq(as.Date("2026-10-01"), by = "month", length.out = 6)
  # Heavier into the holidays, lighter after.
  shape  <- c(1.2, 1.3, 1.0, 0.7, 0.8, 1.0)
  lines  <- fix_agency_lines()

  rows <- merge(lines, data.frame(month = months, shape = shape))
  rows$planned_spend <- rows$monthly * rows$shape
  rows$unit_type <- "impression"
  out <- rows[order(rows$channel, rows$partner, rows$campaign, rows$tactic,
                    rows$month),
              c("month", "channel", "partner", "campaign", "tactic",
                "unit_type", "planned_spend", "planned_rate")]
  rownames(out) <- NULL
  out
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
