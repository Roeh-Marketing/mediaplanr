# Shared fixtures. The package depends on nothing but S7, so these are plain
# data frames — no model objects or sampler required.

# Base plan at channel grain (total planned spend = 160).
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
