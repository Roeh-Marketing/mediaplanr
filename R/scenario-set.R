#' A base plan plus named scenarios derived from it
#'
#' `ScenarioSet` is the comparison registry: a base plan and the scenarios
#' derived from it, all at one grain. Each entry is a [MediaPlan]; the set adds
#' names, a designated baseline, and comparison over planned_spend.
#'
#' Build one with [scenario_set()] and grow it with [add_scenario()]; both
#' return new objects (value semantics — the set being compared against is never
#' mutated).
#'
#' The set holds **plan intent only**. Predicted outcomes come from a separate
#' modeling process (e.g. `mrmopt`); join them to [compare_scenarios()] output
#' by scenario name and grain columns.
#'
#' @param scenarios Named list of [MediaPlan] objects, all at the same grain.
#' @param grain Character vector; the common plan grain.
#' @param base_name Name of the baseline scenario (used for deltas).
#' @param id Opaque synthetic id.
#' @return A `ScenarioSet` S7 object.
#' @export
ScenarioSet <- S7::new_class(
  "ScenarioSet",
  properties = list(
    scenarios = S7::new_property(S7::class_list, default = quote(list())),
    grain     = S7::new_property(S7::class_character, default = character(0)),
    base_name = S7::new_property(S7::class_character, default = "base"),
    id        = S7::new_property(S7::class_character, default = quote(new_id("set")))
  ),
  validator = function(self) {
    s <- self@scenarios
    errs <- character(0)
    if (length(self@grain) < 1) {
      errs <- c(errs, "@grain must name at least one column.")
    }
    if (length(s) < 1) {
      errs <- c(errs, "@scenarios must contain at least the base scenario.")
    } else {
      nm <- names(s)
      if (is.null(nm) || any(!nzchar(nm))) {
        errs <- c(errs, "@scenarios must be a fully named list.")
      } else if (anyDuplicated(nm)) {
        errs <- c(errs, "@scenarios has duplicate names.")
      }
      is_plan <- vapply(s, function(e) S7::S7_inherits(e, MediaPlan), logical(1))
      if (any(!is_plan)) {
        errs <- c(errs, "every @scenarios entry must be a MediaPlan.")
      } else {
        same_grain <- vapply(s, function(e) identical(e@grain, self@grain),
                             logical(1))
        if (any(!same_grain)) {
          errs <- c(errs, "every scenario must share the set's @grain.")
        }
      }
      if (!is.null(nm) && !self@base_name %in% nm) {
        errs <- c(errs, paste0("@base_name '", self@base_name,
                               "' is not among the scenario names."))
      }
    }
    if (length(errs)) errs else NULL
  }
)

#' Start a scenario set from a base plan
#'
#' @param base A base [MediaPlan], registered as the baseline scenario.
#' @param name Label for the baseline scenario. Defaults to the plan's
#'   `@nickname` if set, otherwise its `@name`.
#' @return A [ScenarioSet] containing one (baseline) scenario.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "Q3 base"
#' )
#' scenario_set(base)
#' @export
scenario_set <- function(base, name = NULL) {
  if (!S7::S7_inherits(base, MediaPlan)) {
    stop("`base` must be a MediaPlan.", call. = FALSE)
  }
  nm <- name %||% .plan_label(base)
  ScenarioSet(
    scenarios = stats::setNames(list(base), nm),
    grain     = base@grain,
    base_name = nm,
    id        = new_id("set")
  )
}

#' Add a scenario to a set
#'
#' Appends `plan` as a named scenario and returns a **new** [ScenarioSet]; the
#' input set is not mutated.
#'
#' @param set A [ScenarioSet].
#' @param plan A [MediaPlan] at the same grain as the set.
#' @param name Optional scenario label; defaults to the plan's `@nickname` if
#'   set, otherwise its `@name`. A unique suffix is appended on collision.
#' @return A new [ScenarioSet] with the scenario appended.
#' @export
add_scenario <- function(set, plan, name = NULL) {
  if (!S7::S7_inherits(set, ScenarioSet)) {
    stop("`set` must be a ScenarioSet.", call. = FALSE)
  }
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!identical(plan@grain, set@grain)) {
    stop("scenario grain (", paste(plan@grain, collapse = ", "),
         ") must match the set grain (", paste(set@grain, collapse = ", "), ").",
         call. = FALSE)
  }

  existing <- names(set@scenarios)
  nm <- name %||% .plan_label(plan)
  if (nm %in% existing) {
    k <- 2L
    repeat {
      cand <- paste0(nm, "_", k)
      if (!cand %in% existing) { nm <- cand; break }
      k <- k + 1L
    }
  }

  scen <- set@scenarios
  scen[[nm]] <- plan

  ScenarioSet(
    scenarios = scen,
    grain     = set@grain,
    base_name = set@base_name,
    id        = set@id
  )
}

#' Compare the scenarios in a set
#'
#' Collects the scenarios into a comparison table over **planned planned_spend** at one
#' of two levels:
#'
#' * `"summary"` (default): one row per scenario — total planned_spend and the
#'   delta versus the baseline.
#' * `"cell"`: one row per scenario x grain cell, over the **union** of grain
#'   cells across the whole set — planned spend, that cell's share of the
#'   scenario total, and the delta versus the same cell in the baseline.
#'
#' The union matters when scenarios are authored independently rather than
#' derived — one plan per tab of a workbook, say — because their row sets need
#' not match. A cell absent from a scenario means it plans no spend there, so it
#' is zero-filled rather than omitted. Without that, a scenario that *drops* a
#' line item would simply have no row for it and the cut would be invisible,
#' while one that *adds* a line item would report `NA` instead of the full
#' amount. Scenarios built with [build_scenario()] always share their parent's
#' row set, so for those the result is unchanged.
#'
#' Predicted outcomes are not computed here. To compare modeled volume, forecast
#' the scenarios with `mrmopt` and join the result on `scenario` + the grain
#' columns.
#'
#' @param set A [ScenarioSet].
#' @param level One of `"summary"` or `"cell"`.
#' @return A data frame.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "base"
#' )
#' set <- scenario_set(base)
#' set <- add_scenario(set, build_scenario(base, edits = c("Search" = 120),
#'                                         name = "Search boost"))
#' compare_scenarios(set)
#' compare_scenarios(set, "cell")
#' @export
compare_scenarios <- function(set, level = c("summary", "cell")) {
  level <- match.arg(level)
  if (!S7::S7_inherits(set, ScenarioSet)) {
    stop("`set` must be a ScenarioSet.", call. = FALSE)
  }
  scen <- set@scenarios
  nms <- names(scen)
  g <- set@grain

  if (level == "summary") {
    rows <- lapply(nms, function(nm) {
      p <- scen[[nm]]
      data.frame(
        scenario = nm,
        plan_id = p@id,
        parent_id = if (length(p@parent_id)) p@parent_id else NA_character_,
        total_planned_spend = sum(p@data[["planned_spend"]]),
        stringsAsFactors = FALSE
      )
    })
    out <- do.call(rbind, rows)
    base_spd <- out$total_planned_spend[out$scenario == set@base_name][1]
    out$spend_vs_base <- out$total_planned_spend - base_spd
    out$spend_pct_vs_base <- if (isTRUE(base_spd != 0)) {
      out$spend_vs_base / base_spd
    } else {
      rep(NA_real_, nrow(out))
    }
    rownames(out) <- NULL
    return(out)
  }

  # level == "cell" -- compared over the UNION of grain cells across the set.
  #
  # Scenarios built with build_scenario() always share their parent's row set,
  # but scenarios authored independently (e.g. one per tab of a workbook) need
  # not: one may add a line item, another may drop one. Comparing only each
  # scenario's own rows made an addition report NA and made a drop vanish from
  # the table altogether -- so a cut read as money appearing from nowhere.
  # Absent means zero spend, so the union is zero-filled and every delta is
  # meaningful.
  frames <- lapply(scen, function(p) p@data)
  keys <- lapply(frames, function(d) line_item(d, g))
  all_keys <- unique(unlist(keys, use.names = FALSE))

  # One row per union cell, carrying the grain values (taken from whichever
  # scenario first defines that cell).
  spine <- do.call(rbind, lapply(seq_along(frames), function(i) {
    d <- frames[[i]]
    d[!duplicated(keys[[i]]), g, drop = FALSE]
  }))
  spine_keys <- line_item(spine, g)
  spine <- spine[match(all_keys, spine_keys), , drop = FALSE]
  rownames(spine) <- NULL

  base_by_cell <- stats::setNames(
    scen[[set@base_name]]@data[["planned_spend"]], keys[[set@base_name]]
  )
  base_vec <- as.numeric(base_by_cell[all_keys])
  base_vec[is.na(base_vec)] <- 0

  rows <- lapply(nms, function(nm) {
    d <- scen[[nm]]@data
    sp <- as.numeric(stats::setNames(d[["planned_spend"]], keys[[nm]])[all_keys])
    sp[is.na(sp)] <- 0
    tot <- sum(sp)
    out <- cbind(data.frame(scenario = nm, stringsAsFactors = FALSE), spine)
    out[["planned_spend"]] <- sp
    out$share_of_total <- if (isTRUE(tot != 0)) sp / tot else NA_real_
    out$spend_vs_base <- sp - base_vec
    out
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
