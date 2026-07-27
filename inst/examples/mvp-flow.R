# mediaplanr — end-to-end MVP flow
# =================================================================
# Mirrors the media-planning path the MVP app drives:
#   plan upload -> validate -> derive scenarios -> compare -> (export).
#
# Run with:  source(system.file("examples", "mvp-flow.R", package = "mediaplanr"))
#
# Note what is NOT here: no model fitting, no forecasting, no optimization.
# mediaplanr expresses plan *intent*. Predicted outcomes come from the mrmopt
# engine and are joined to compare_scenarios() output by scenario + grain cell.

library(mediaplanr)

# ---- 1. Upload -> validated plan --------------------------------------------
plan_df <- data.frame(
  channel       = c("TV", "Search", "Social"),
  planned_spend = c(80, 40, 40),
  stringsAsFactors = FALSE
)

# `valid_keys` is the coverage check: in the app, pass the decomp's distinct
# keys so a plan naming an unknown channel fails here, at upload, with a
# readable message — not silently, three steps later.
decomp_keys <- data.frame(channel = c("TV", "Search", "Social", "Radio"))

base_plan <- media_plan_from_df(
  plan_df,
  grain = "channel",
  name = "Q3 base",
  valid_keys = decomp_keys
)
print(base_plan)

# @data is a plain, directly accessible data frame — no ceremony to get at it:
str(base_plan@data)

# ---- 2. Scenarios by edit ---------------------------------------------------
# An analyst overrides one channel; everything else is held.
manual_plan <- build_scenario(
  base_plan,
  edits = data.frame(channel = "Search", planned_spend = 120),
  name = "Manual: +Search"
)
print(manual_plan@data)

# An allocation computed elsewhere (e.g. by mrmopt::opt_mix()) comes back in
# through the same door — mediaplanr does not care how the numbers were chosen.
optimized_alloc <- data.frame(
  channel       = c("TV", "Search", "Social"),
  planned_spend = c(55, 70, 35)
)
opt_plan <- build_scenario(
  base_plan,
  edits = optimized_alloc,
  name = "Optimized (external)",
  objective = "max volume @ 160 budget, via mrmopt::opt_mix()"
)
print(opt_plan@data)

# The base plan is untouched by either derivation:
stopifnot(identical(base_plan@data$planned_spend, c(80, 40, 40)))

# Lineage is preserved:
cat("\nparent of 'Optimized' is the base plan:",
    identical(opt_plan@parent_id, base_plan@id), "\n")

# ---- 3. Collect into a comparable set ---------------------------------------
set <- scenario_set(base_plan, name = "Base")
set <- add_scenario(set, manual_plan)
set <- add_scenario(set, opt_plan)
print(set)

# ---- 4. Compare (what the app charts / exports) -----------------------------
cat("\n-- summary (one row per scenario, deltas vs base) --\n")
print(compare_scenarios(set, "summary"))

cat("\n-- cell (one row per scenario x grain cell) --\n")
print(compare_scenarios(set, "cell"))

# To compare modeled outcomes, forecast each scenario with mrmopt and join the
# result onto the table above by `scenario` + the grain columns.

invisible(set)
