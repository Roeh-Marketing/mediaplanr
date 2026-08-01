# mediaplanr — end-to-end MVP flow
# =================================================================
# Mirrors the media-planning path the MVP app drives:
#   plan upload -> validate -> derive scenarios -> compare -> (export).
#
# Run with:  source(system.file("examples", "mvp-flow.R", package = "mediaplanr"))
#
# Note what is NOT here: no model fitting, no forecasting, no optimization.
# mediaplanr expresses plan intent. Predicted outcomes come from the mrmopt
# engine and are joined to compare_scenarios() output by scenario + grain.

library(mediaplanr)

# ---- 1. Upload -> validated plan --------------------------------------------
# A plan holds PLANNED values only -- including for weeks already past. Those
# rows are what was *intended*, not what happened; actuals live in the decomp.
# So a plan on its own is blind to past and future: those concepts only exist
# for a plan-decomp PAIRING (see step 2).
DECOMP_THROUGH <- as.Date("2026-03-15")

plan_df <- data.frame(
  week    = as.Date(c("2026-03-02", "2026-03-02",
                      "2026-04-06", "2026-04-06", "2026-04-06")),
  channel = c("TV", "Search", "TV", "TV", "Search"),
  partner = c("NBC", "Google", "NBC", "Hulu", "Google"),
  planned_spend   = c(30, 20, 35, 15, 25),
  stringsAsFactors = FALSE
)

base_plan <- media_plan_from_df(
  plan_df,
  grain = c("channel", "partner", "week"),
  week  = "week",
  name  = "Q2 base"
)
print(base_plan)

# @data is a plain, directly accessible data frame:
str(base_plan@data)

# The line item grain is the time-free identity -- what models attach to:
cat("\nline item grain:", paste(line_item_grain(base_plan), collapse = " + "), "\n")
cat("distinct line items:",
    paste(unique(line_item(base_plan@data, line_item_grain(base_plan))),
          collapse = " / "), "\n")

# ---- 2. Pair the plan with a decomp -----------------------------------------
# The one pairing operation the package provides: does the plan account for
# everything the model measured? Warns rather than errors -- both artifacts are
# valid, it is their pairing that disagrees -- and returns the missing items so
# a UI can render them. Re-run it whenever the decomp refreshes; no need to
# rebuild the plan.
decomp <- data.frame(
  channel = c("TV", "Search", "Audio"),
  partner = c("NBC", "Google", "Spotify"),
  stringsAsFactors = FALSE
)
missing <- check_coverage(base_plan, decomp, through = DECOMP_THROUGH)
cat("\nline items in the decomp but not the plan's history:",
    if (length(missing)) paste(missing, collapse = ", ") else "(none)", "\n")

# Note what is NOT reported: TV | Hulu, a new partner in the future portion.
# New line items after the through-date are expected, never flagged.

# ---- 3. Scenarios by edit ---------------------------------------------------
# Operations: state intent, the arithmetic happens in R. `target` may name any
# subset of the grain, so this reaches every line item in one week.
trim <- build_scenario(
  base_plan,
  edits = list(target = list(week = as.Date("2026-04-06")), scale = 0.8),
  name  = "Trim April 6 by 20%"
)
print(trim@data)

# "Set the total budget", holding the current mix:
resized <- build_scenario(base_plan, edits = list(total = 150),
                          name = "Budget 150")

# An allocation computed elsewhere (e.g. by mrmopt::opt_mix()) comes back in
# through the same door -- mediaplanr does not care how the numbers were chosen.
opt_plan <- build_scenario(
  base_plan,
  edits = data.frame(
    channel = c("TV", "TV", "Search"),
    partner = c("NBC", "Hulu", "Google"),
    week    = as.Date(c("2026-04-06", "2026-04-06", "2026-04-06")),
    planned_spend   = c(40, 20, 20)
  ),
  name = "Optimized (external)",
  objective = "max KPI @ 80 for w/c Apr 6, via mrmopt::opt_mix()"
)

# The base plan is untouched by any derivation, and lineage is preserved:
cat("\nbase unchanged:", identical(base_plan@data$planned_spend, plan_df$planned_spend), "\n")
cat("parent of 'Optimized' is the base plan:",
    identical(opt_plan@parent_id, base_plan@id), "\n")

# ---- 4. Roll up to find a model ---------------------------------------------
# TV | Hulu is new and has no fitted model. Roll up to the next coarsest level
# to find one; the app does the model lookup and any prior specification.
by_channel <- roll_up(base_plan, c("channel", "week"), name = "channel view")
print(by_channel@data)

# ---- 5. Collect into a comparable set ---------------------------------------
set <- scenario_set(base_plan, name = "Base")
set <- add_scenario(set, trim)
set <- add_scenario(set, resized)
set <- add_scenario(set, opt_plan)
print(set)

# ---- 6. Compare (what the app charts / exports) -----------------------------
cat("\n-- summary (one row per scenario, deltas vs base) --\n")
print(compare_scenarios(set, "summary"))

cat("\n-- cell (one row per scenario x plan row) --\n")
print(head(compare_scenarios(set, "cell"), 10))

invisible(set)
