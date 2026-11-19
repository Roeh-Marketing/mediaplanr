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
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", time = "week", name = "Q3 base"
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
#' @section Comparing flights:
#' `level = "flight"` compares the **buys** rather than the cells: one row per
#' scenario per flight, joined on `flight_id`, with what happened to it named in
#' a `change` column — `moved`, `resized`, `moved & resized`, `added`,
#' `dropped`, `repaced` or `unchanged`.
#'
#' This is the thing cell-level cannot say. A flight pushed a week later shows
#' at cell level as money leaving one week and arriving in another, which is
#' true but leaves the reader to infer that a single buy moved. Here it is one
#' row saying so.
#'
#' It works by **lineage**. `flight_id` is minted per import, so it identifies
#' the same buy across a plan and the scenarios derived from it, and does *not*
#' match across independently-authored plans — which would report one buy as two.
#' When the set shares no flight ids at all, this warns rather than returning a
#' table of spurious adds and drops. A set whose plans record no flights returns
#' no rows, the same way [flights()] does.
#'
#' @section What each scenario is compared against:
#' `against` chooses the reference every delta is measured from:
#'
#' - `"base"` (default) -- the set's baseline, for every scenario.
#' - `"parent"` -- each scenario's own parent in the set, the way [lineage()]
#'   reads it. A root has no parent here, so its deltas are `NA`.
#' - `"current_approved"` -- the plan the set is currently buying against;
#'   see [current_approved()]. It must be exactly one plan, or this errors:
#'   with none there is nothing to compare to, and with several the reference
#'   would be a guess.
#'
#' The delta columns are named for the reference: `spend_vs_base`,
#' `spend_vs_parent` or `spend_vs_current_approved` (and the matching
#' `spend_pct_vs_*` at summary level).
#'
#' @param set A [ScenarioSet].
#' @param level One of `"summary"`, `"cell"` or `"flight"`.
#' @param against What each scenario is compared against: `"base"`,
#'   `"parent"` or `"current_approved"`. See *What each scenario is compared
#'   against*.
#' @return A data frame.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", time = "week", name = "base"
#' )
#' set <- scenario_set(base)
#' set <- add_scenario(set, build_scenario(
#'   base, edits = list(target = list(channel = "Search"), total = 120),
#'   name = "Search boost"))
#' compare_scenarios(set)
#' compare_scenarios(set, "cell")
#' @export
compare_scenarios <- function(set, level = c("summary", "cell", "flight"),
                              against = c("base", "parent",
                                          "current_approved")) {
  level   <- match.arg(level)
  against <- match.arg(against)
  if (!S7::S7_inherits(set, ScenarioSet)) {
    stop("`set` must be a ScenarioSet.", call. = FALSE)
  }
  scen <- set@scenarios
  nms <- names(scen)
  g <- set@grain
  # The scenario each one is measured from, by name (NA: none).
  ref <- .reference_names(set, against)
  delta_col <- paste0("spend_vs_", against)

  if (level == "flight") return(.compare_flights(set, ref, delta_col))

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
    ref_spend <- out$total_planned_spend[match(ref, out$scenario)]
    out[[delta_col]] <- out$total_planned_spend - ref_spend
    out[[paste0("spend_pct_vs_", against)]] <-
      ifelse(!is.na(ref_spend) & ref_spend != 0, out[[delta_col]] / ref_spend,
             NA_real_)
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

  # A scenario's spend on every union cell, zero where it plans nothing.
  spend_on_cells <- function(nm) {
    d <- scen[[nm]]@data
    sp <- as.numeric(stats::setNames(d[["planned_spend"]], keys[[nm]])[all_keys])
    sp[is.na(sp)] <- 0
    sp
  }

  rows <- lapply(nms, function(nm) {
    sp  <- spend_on_cells(nm)
    tot <- sum(sp)
    out <- cbind(data.frame(scenario = nm, stringsAsFactors = FALSE), spine)
    out[["planned_spend"]] <- sp
    out$share_of_total <- if (isTRUE(tot != 0)) sp / tot else NA_real_
    out[[delta_col]] <- if (is.na(ref[[nm]])) NA_real_ else
      sp - spend_on_cells(ref[[nm]])
    out
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# The scenario each scenario is compared against, by name; NA where there is
# none (a root, compared against its parent).
.reference_names <- function(set, against) {
  nms <- names(set@scenarios)
  ref <- switch(
    against,
    base = rep(set@base_name, length(nms)),
    parent = lineage(set)$parent,
    current_approved = {
      current <- lineage(set)
      current <- current$scenario[current$current]
      if (length(current) != 1L) {
        stop("`against = \"current_approved\"` needs exactly one current ",
             "approved plan; the set has ",
             if (!length(current)) "none" else
               paste0(length(current), " (", paste(current, collapse = ", "),
                      ")"),
             ". See current_approved().", call. = FALSE)
      }
      rep(current, length(nms))
    }
  )
  stats::setNames(ref, nms)
}

# level = "flight": one row per scenario per flight, joined on flight_id.
#
# Cell-level comparison already reads a moved flight correctly -- money leaves
# one week and arrives in another -- but it cannot say that a single buy moved.
# This can, because flight_id survives a derivation.
#
# `ref` names the scenario each one is compared against (see
# .reference_names()); `delta_col` names the spend delta for it.
.compare_flights <- function(set, ref, delta_col) {
  scen <- set@scenarios
  nms  <- names(scen)
  base <- set@base_name

  fl <- lapply(scen, flights)
  lg <- setdiff(setdiff(set@grain, scen[[base]]@time_col), flight_cols())

  ids <- unique(unlist(lapply(fl, function(f) f[["flight_id"]]),
                       use.names = FALSE))
  ids <- ids[!is.na(ids)]
  if (!length(ids)) {
    return(.empty_flight_cmp(scen[[base]], lg, delta_col))
  }
  shared <- length(nms) < 2L ||
    any(vapply(ids, function(id) {
      sum(vapply(fl, function(f) id %in% f[["flight_id"]], logical(1))) > 1L
    }, logical(1)))
  if (!shared) {
    warning("no flight is shared between these scenarios, so every buy reads ",
            "as added or dropped. Flight ids identify a buy through a ",
            "derivation, not across independently authored plans -- compare ",
            "at level = \"cell\" instead.", call. = FALSE)
  }

  # The line item each flight belongs to, from whichever scenario defines it.
  spine <- do.call(rbind, lapply(fl, function(f) f[, c("flight_id", lg),
                                                   drop = FALSE]))
  spine <- spine[match(ids, spine[["flight_id"]]), , drop = FALSE]

  rows <- lapply(nms, function(nm) {
    f <- fl[[nm]]
    i <- match(ids, f[["flight_id"]])
    here <- !is.na(i)

    # The reference scenario's flights. With no reference (a root compared
    # against its parent) there is nothing to measure from, so every
    # comparison column is NA.
    r <- ref[[nm]]
    has_ref <- !is.na(r)
    b  <- if (has_ref) fl[[r]] else f[0, , drop = FALSE]
    bi <- match(ids, b[["flight_id"]])

    spend <- ifelse(here, f[["planned_spend"]][i], 0)
    b_spend <- ifelse(!is.na(bi), b[["planned_spend"]][bi], 0)
    # ifelse() drops the class, and a plan keyed by moments carries POSIXct
    # flight dates, so each of these is put back into the type it came from.
    start <- .as_time_like(ifelse(here, f[["flight_start"]][i], NA_real_),
                           f[["flight_start"]])
    end   <- .as_time_like(ifelse(here, f[["flight_end"]][i], NA_real_),
                           f[["flight_end"]])
    b_start <- .as_time_like(ifelse(!is.na(bi), b[["flight_start"]][bi], NA_real_),
                             b[["flight_start"]])

    out <- cbind(data.frame(scenario = nm, stringsAsFactors = FALSE), spine)
    out[["flight_start"]]  <- start
    out[["flight_end"]]    <- end
    out[["planned_spend"]] <- spend
    out[["n_periods"]]     <- ifelse(here, f[["n_periods"]][i], 0L)
    out[["pacing"]]        <- ifelse(here, f[["pacing"]][i], NA_character_)
    out[[delta_col]] <- if (has_ref) spend - b_spend else NA_real_
    out[["start_shift_days"]] <- as.integer(.to_date(start) - .to_date(b_start))
    out[["change"]] <- if (has_ref) {
      .flight_change(nm, r, here, !is.na(bi), f, b, i, bi)
    } else {
      NA_character_
    }
    out
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# What happened to this flight, in one word. `base` names the scenario this
# one is compared against -- the baseline, its parent, or the current approved
# plan -- and `b` / `bi` are that scenario's flights.
.flight_change <- function(nm, base, here, in_base, f, b, i, bi) {
  if (identical(nm, base)) {
    # A flight some other scenario adds is not "dropped" from the baseline's
    # point of view -- it was never there.
    return(ifelse(here, "base", "absent"))
  }
  moved <- here & in_base &
    (f[["flight_start"]][i] != b[["flight_start"]][bi] |
       f[["flight_end"]][i] != b[["flight_end"]][bi])
  resized <- here & in_base &
    (round(f[["planned_spend"]][i] * 100) != round(b[["planned_spend"]][bi] * 100))
  repaced <- here & in_base & (f[["pacing"]][i] != b[["pacing"]][bi])

  out <- rep("unchanged", length(here))
  out[repaced] <- "repaced"
  out[moved] <- "moved"
  out[resized] <- "resized"
  out[moved & resized] <- "moved & resized"
  out[!here & in_base] <- "dropped"
  out[here & !in_base] <- "added"
  out
}

.empty_flight_cmp <- function(plan, lg, delta_col = "spend_vs_base") {
  out <- plan@data[0, lg, drop = FALSE]
  out <- cbind(data.frame(scenario = character(0), stringsAsFactors = FALSE), out)
  out[["flight_id"]]     <- character(0)
  out[["flight_start"]]  <- plan@data[[plan@time_col]][0]
  out[["flight_end"]]    <- plan@data[[plan@time_col]][0]
  out[["planned_spend"]] <- numeric(0)
  out[["n_periods"]]     <- integer(0)
  out[["pacing"]]        <- character(0)
  out[[delta_col]]       <- numeric(0)
  out[["start_shift_days"]] <- integer(0)
  out[["change"]]        <- character(0)
  rownames(out) <- NULL
  out
}
