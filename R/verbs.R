# Verbs that take a plan are S7 generics dispatching on it.

# The operation keys recognised in an edit op. Exactly one per op.
.op_keys <- c("set", "scale", "delta", "total")

# Resolve an op's `target` to a logical row mask over `d`.
#
# `target` is a named list of grain column -> value(s), naming any SUBSET of the
# grain (a partial key). Missing/empty target matches every row. Unmatched
# values error rather than silently selecting nothing — a caller (or an LLM)
# that typos a channel name must hear about it, not get a no-op scenario back.
.match_target <- function(d, grain, target, where = "") {
  if (is.null(target) || length(target) == 0) return(rep(TRUE, nrow(d)))

  if (!is.list(target) || is.null(names(target)) || any(!nzchar(names(target)))) {
    stop(where, "`target` must be a named list of grain column = value(s).",
         call. = FALSE)
  }
  unknown <- setdiff(names(target), grain)
  if (length(unknown)) {
    stop(where, "`target` may only name grain columns (",
         paste(grain, collapse = ", "), "); got: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }

  # Per-column check first, so a typo names the offending value and the
  # alternatives instead of producing a bare "matched no rows".
  for (nm in names(target)) {
    have <- unique(as.character(d[[nm]]))
    bad <- setdiff(as.character(target[[nm]]), have)
    if (length(bad)) {
      stop(where, "no such value(s) in '", nm, "': ",
           paste(bad, collapse = ", "), ". Valid: ",
           paste(utils::head(have, 8), collapse = ", "),
           if (length(have) > 8) ", ..." else "", call. = FALSE)
    }
  }

  keep <- rep(TRUE, nrow(d))
  for (nm in names(target)) {
    keep <- keep & (as.character(d[[nm]]) %in% as.character(target[[nm]]))
  }
  if (!any(keep)) {
    stop(where, "target matched no rows: the values are individually valid but ",
         "do not co-occur in the plan.", call. = FALSE)
  }
  keep
}

# Apply one edit op to `d`, returning the updated data frame.
.apply_op <- function(d, grain, op, i) {
  where <- paste0("edit op ", i, ": ")
  if (!is.list(op)) {
    stop(where, "each op must be a list.", call. = FALSE)
  }

  present <- intersect(names(op), .op_keys)
  if (length(present) != 1L) {
    stop(where, "supply exactly one of ", paste(.op_keys, collapse = "/"),
         "; got ",
         if (!length(present)) "none" else paste(present, collapse = " + "),
         ".", call. = FALSE)
  }
  extra <- setdiff(names(op), c("target", .op_keys))
  if (length(extra)) {
    stop(where, "unknown field(s): ", paste(extra, collapse = ", "),
         ". Allowed: target, ", paste(.op_keys, collapse = ", "), ".",
         call. = FALSE)
  }

  v <- op[[present]]
  if (!is.numeric(v) || length(v) != 1L || is.na(v)) {
    stop(where, "`", present, "` must be a single non-missing number.",
         call. = FALSE)
  }

  keep <- .match_target(d, grain, op[["target"]], where)
  ps <- d[["planned_spend"]]

  d[["planned_spend"]][keep] <- switch(
    present,
    set   = v,
    scale = ps[keep] * v,
    delta = ps[keep] + v,
    total = {
      s <- sum(ps[keep])
      if (s == 0) {
        stop(where, "cannot apply `total` to a group whose current planned_spend is 0: ",
             "there is no mix to distribute by. Use `set` instead.",
             call. = FALSE)
      }
      ps[keep] / s * v
    }
  )
  d
}

# Apply edits to a plan's data, returning a new data frame. Accepts three
# shapes; see ?build_scenario.
.apply_edits <- function(plan, edits) {
  d <- plan@data
  g <- plan@grain
  base_key <- line_item(d, g)

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
    ek <- line_item(edits, g)
    unknown <- setdiff(ek, base_key)
    if (length(unknown)) {
      stop("`edits` reference row(s) not in the plan: ",
           paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
    }
    idx <- match(ek, base_key)
    d[["planned_spend"]][idx] <- as.numeric(edits[["planned_spend"]])

  } else if (is.numeric(edits) && !is.null(names(edits))) {
    unknown <- setdiff(names(edits), base_key)
    if (length(unknown)) {
      stop("`edits` reference row(s) not in the plan: ",
           paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
    }
    idx <- match(names(edits), base_key)
    d[["planned_spend"]][idx] <- as.numeric(edits)

  } else if (is.list(edits)) {
    # One op, or a list of ops applied in order.
    ops <- if (any(names(edits) %in% c("target", .op_keys))) list(edits) else edits
    if (!length(ops)) {
      stop("`edits` is an empty list; supply at least one operation.",
           call. = FALSE)
    }
    for (i in seq_along(ops)) d <- .apply_op(d, g, ops[[i]], i)

  } else {
    stop("`edits` must be one of: a list of operations (target + ",
         paste(.op_keys, collapse = "/"), "), a data frame (grain columns + ",
         "planned_spend), or a named numeric vector keyed by line_item().",
         call. = FALSE)
  }
  d
}

#' Derive a new scenario plan from a base plan
#'
#' Produces a new [MediaPlan] by changing `planned_spend` and leaving everything
#' else untouched. The returned plan carries `@parent_id` set to the base plan's
#' id, so lineage is preserved through every derivation, and the base plan is
#' never mutated.
#'
#' `mediaplanr` deliberately does not forecast or optimize: it expresses *plan
#' intent*. To build a scenario from an optimizer, run the optimization
#' elsewhere (e.g. `mrmopt::opt_mix()`) and pass the resulting planned_spend allocation
#' in as an absolute `edits` data frame.
#'
#' @section Edit forms:
#' `edits` accepts three shapes.
#'
#' **1. Operations** — a list of ops, or a single op, applied in order. This is
#' the form to drive from a UI or an LLM tool call: the caller states the
#' *operation* and the arithmetic happens here, exactly.
#'
#' Each op is `list(target = <named list>, <one of set/scale/delta/total>)`.
#'
#' \describe{
#'   \item{`target`}{Named list of grain column = value(s), naming any **subset**
#'     of the grain — so `list(week = "2026-03-09")` hits every channel in that
#'     week. Values may be vectors. Omit `target` to match the whole plan.
#'     Targeting a value that does not exist is an error, never a silent no-op.}
#'   \item{`set`}{Absolute planned_spend, applied to **each** matched cell.}
#'   \item{`scale`}{Multiply each matched cell (e.g. `1.2` = +20%).}
#'   \item{`delta`}{Add to each matched cell (may be negative).}
#'   \item{`total`}{Make the matched cells **sum** to this, holding their
#'     current mix. This is the "set the budget" operation.}
#' }
#'
#' Note the deliberate split: `set` is per-cell, `total` is across cells. So
#' `list(target = list(channel = "TV"), set = 50)` sets every TV row to 50,
#' while `list(target = list(channel = "TV"), total = 50)` makes TV's rows add
#' up to 50.
#'
#' **2. Data frame** — grain columns + `planned_spend`; matched cells are
#' overridden with those absolute values. Natural for optimizer output.
#'
#' **3. Named numeric vector** — keyed by [line_item()], e.g. `c("TV" = 100)`.
#' Terse for one or two cells at a simple grain.
#'
#' @param plan The base [MediaPlan].
#' @param edits The edits to apply; see *Edit forms*.
#' @param name Human-facing name for the new scenario.
#' @param objective Human-facing objective / notes for the new scenario.
#' @param ... Unused; for method extension.
#' @return A new [MediaPlan] at the base plan's grain, with `@parent_id` set.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search", "Social"),
#'              planned_spend = c(80, 40, 40)),
#'   grain = "channel", name = "base"
#' )
#'
#' # "Increase Search by 20%" — the caller states intent, R does the math
#' build_scenario(base, edits = list(target = list(channel = "Search"),
#'                                   scale = 1.2))
#'
#' # "Set the total budget to 200", holding the current mix
#' build_scenario(base, edits = list(total = 200))
#'
#' # "Move 10 from TV to Search" — ops apply in order
#' build_scenario(base, edits = list(
#'   list(target = list(channel = "TV"),     delta = -10),
#'   list(target = list(channel = "Search"), delta =  10)
#' ), name = "shift 10")
#'
#' # Absolute allocation (e.g. from mrmopt::opt_mix())
#' build_scenario(
#'   base,
#'   edits = data.frame(channel = c("TV", "Search"), planned_spend = c(50, 70)),
#'   name = "Optimized"
#' )
#'
#' # Terse single-cell override
#' build_scenario(base, edits = c("Search" = 120), name = "Search boost")
#' @export
build_scenario <- S7::new_generic("build_scenario", "plan",
  function(plan, edits, name = "", objective = "", ...) S7::S7_dispatch())

S7::method(build_scenario, MediaPlan) <- function(plan, edits, name = "", objective = "", ...) {
  if (missing(edits) || is.null(edits)) {
    stop("`edits` is required: supply a list of operations, a data frame ",
         "(grain columns + planned_spend), or a named numeric vector keyed ",
         "by line_item().", call. = FALSE)
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
