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

# The key line_item() gives a flat-fixture cell, e.g. cell("TV").
cell <- function(...) paste(c(..., format(fix_week())), collapse = " | ")

# A named-vector edit keyed the way line_item() keys a flat fixture:
#   at_cell(TV = 200)  ->  c("TV | 2026-07-06" = 200)
at_cell <- function(...) {
  v <- c(...)
  stats::setNames(v, vapply(names(v), cell, character(1)))
}
