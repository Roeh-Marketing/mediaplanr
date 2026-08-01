# Shared fixtures. The package depends on nothing but S7, so these are plain
# data frames — no model objects or sampler required.

# Base plan at channel grain (total planned_spend = 160).
std_plan <- function(name = "base") {
  media_plan_from_df(
    data.frame(
      channel = c("TV", "Search", "Social"),
      planned_spend = c(80, 40, 40),
      stringsAsFactors = FALSE
    ),
    grain = "channel", name = name
  )
}

# Plan at a finer grain (channel + partner).
fine_plan <- function(name = "fine") {
  media_plan_from_df(
    data.frame(
      channel = c("TV", "TV", "Search", "Social"),
      partner = c("A", "B", "X", "Y"),
      planned_spend = c(50, 30, 40, 40),
      stringsAsFactors = FALSE
    ),
    grain = c("channel", "partner"), name = name
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
  media_plan_from_df(weekly_df(), grain = c("channel", "partner", "week"),
                     week = "week", name = name)
}
