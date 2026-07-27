# Verbs that take a plan are S7 generics dispatching on it.

# Apply manual edits to a plan's data, returning a new data frame.
.apply_edits <- function(plan, edits) {
  d <- plan@data
  g <- plan@grain
  base_key <- grain_key(d, g)

  if (is.data.frame(edits)) {
    miss <- setdiff(g, names(edits))
    if (length(miss)) {
      stop("`edits` data frame is missing grain column(s): ",
           paste(miss, collapse = ", "), call. = FALSE)
    }
    if (!"planned_spend" %in% names(edits)) {
      stop("`edits` data frame must contain a 'planned_spend' column.",
           call. = FALSE)
    }
    ek <- grain_key(edits, g)
    unknown <- setdiff(ek, base_key)
    if (length(unknown)) {
      stop("`edits` reference grain cell(s) not in the plan: ",
           paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
    }
    idx <- match(ek, base_key)
    d[["planned_spend"]][idx] <- as.numeric(edits[["planned_spend"]])
  } else if (is.numeric(edits) && !is.null(names(edits))) {
    unknown <- setdiff(names(edits), base_key)
    if (length(unknown)) {
      stop("`edits` reference grain cell(s) not in the plan: ",
           paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
    }
    idx <- match(names(edits), base_key)
    d[["planned_spend"]][idx] <- as.numeric(edits)
  } else {
    stop("`edits` must be a data frame (grain columns + planned_spend) or a ",
         "named numeric vector keyed by grain_key().", call. = FALSE)
  }
  d
}

#' Derive a new scenario plan from a base plan
#'
#' Produces a new [MediaPlan] by overriding `planned_spend` for the named grain
#' cells and leaving the rest untouched. The returned plan carries `@parent_id`
#' set to the base plan's id, so lineage is preserved through every derivation,
#' and the base plan is never mutated.
#'
#' `mediaplanr` deliberately does not forecast or optimize: it expresses *plan
#' intent*. To build a scenario from an optimizer, run the optimization
#' elsewhere (e.g. `mrmopt::opt_mix()`) and pass the resulting spend allocation
#' in as `edits`.
#'
#' @param plan The base [MediaPlan].
#' @param edits Either a data frame with the grain columns plus a
#'   `planned_spend` column (matched cells are overridden), or a named numeric
#'   vector keyed by [grain_key()].
#' @param name Human-facing name for the new scenario.
#' @param objective Human-facing objective / notes for the new scenario.
#' @param ... Unused; for method extension.
#' @return A new [MediaPlan] at the base plan's grain, with `@parent_id` set.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "base"
#' )
#'
#' # Override one cell
#' build_scenario(base, edits = c("Search" = 120), name = "Search boost")
#'
#' # Or hand in an allocation computed elsewhere (e.g. by mrmopt::opt_mix())
#' build_scenario(
#'   base,
#'   edits = data.frame(channel = c("TV", "Search"), planned_spend = c(50, 70)),
#'   name = "Optimized"
#' )
#' @export
build_scenario <- S7::new_generic("build_scenario", "plan",
  function(plan, edits, name = "", objective = "", ...) S7::S7_dispatch())

S7::method(build_scenario, MediaPlan) <- function(plan, edits, name = "", objective = "", ...) {
  if (missing(edits) || is.null(edits)) {
    stop("`edits` is required: supply a data frame (grain columns + ",
         "planned_spend) or a named numeric vector keyed by grain_key().",
         call. = FALSE)
  }
  MediaPlan(
    data      = .apply_edits(plan, edits),
    grain     = plan@grain,
    id        = new_id("plan"),
    parent_id = plan@id,
    name      = name,
    objective = objective
  )
}
