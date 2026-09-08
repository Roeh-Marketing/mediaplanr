# Subplans: a channel team's own plan, at its own grain and cadence, rolling up
# into ONE cell of the topline it backs.
#
# A subplan is an ordinary MediaPlan -- composition, not inheritance -- held in
# the parent's @subplans list under the key of the line item it backs. What
# changes is the parent's behaviour: its rows for that cell are the subplan's
# rollup, and they are read-only until the subplan is detached. So there is one
# number with one owner, and the only way to change TV's total is to change the
# TV plan and re-attach it.
#
# Reconciliation is not new machinery. The subplan's line item grain must
# CONTAIN the parent's (same or finer), and it carries the parent's key columns
# as constants -- channel == "TV" on every row -- so the cell it backs is a fact
# in its data, not a string to be trusted. That containment is exactly what
# roll_up() already requires of its target grain, so the rollup is
# .aggregate_to() as written; calendarize() bridges the cadence first when the
# parent is weekly. Re-attaching IS the reconcile, and the validator holds the
# invariant (parent rows == rollup) so the two cannot drift.

# ---- the cell a subplan backs ------------------------------------------------

# Which parent line item this subplan refines, derived from its data. Errors
# when the grain does not contain the parent's, or the data spans several cells.
.subplan_key <- function(parent, sub) {
  if (!S7::S7_inherits(sub, MediaPlan)) {
    stop("`subplan` must be a MediaPlan.", call. = FALSE)
  }
  pg <- line_item_grain(parent)
  sg <- line_item_grain(sub)
  lacks <- setdiff(pg, sg)
  if (length(lacks)) {
    stop("the subplan's line item grain (", paste(sg, collapse = ", "),
         ") must contain the parent's (", paste(pg, collapse = ", "),
         "); it lacks: ", paste(lacks, collapse = ", "), ". A subplan refines ",
         "one cell of its parent, so its grain is the parent's, or finer.",
         call. = FALSE)
  }
  if (!nrow(sub@data)) {
    stop("the subplan has no rows, so there is no cell for it to back.",
         call. = FALSE)
  }
  keys <- unique(line_item(sub@data, pg))
  if (length(keys) != 1L) {
    stop("the subplan spans ", length(keys), " cells of the parent (",
         paste(utils::head(keys, 3), collapse = "; "),
         if (length(keys) > 3) "; ..." else "",
         "); a subplan refines one cell, never several.", call. = FALSE)
  }
  keys
}

# "channel TV", "channel | partner TV | NBC" -- how a cell is named in errors.
.cell_label <- function(plan, key) {
  paste(paste(line_item_grain(plan), collapse = " | "), key)
}

# ---- rollup --------------------------------------------------------------------

# The subplan summed to the parent's grain: the rows the parent holds for that
# cell. Two axes. Dimensions collapse through .aggregate_to(), the same sum
# roll_up() uses. Cadence is bridged first when the parent is weekly:
# calendarize() re-cuts the subplan's days onto the parent's weeks, so a daily
# or a Sunday-start subplan lands on a Monday-start topline correctly.
.subplan_rollup <- function(parent, sub) {
  pw <- parent@week_col
  if (!length(pw)) {
    # A timeless parent: time collapses, as roll_up() would collapse it.
    return(.aggregate_to(sub@data, parent@grain))
  }
  if (!length(sub@week_col)) {
    stop("the parent is weekly, so a subplan needs a week column to place its ",
         "spend on the parent's calendar; this one has no time dimension.",
         call. = FALSE)
  }
  ws <- week_start(parent)
  if (is.na(ws)) {
    stop("cannot place the subplan on the parent's calendar: the parent's ",
         "weeks do not all start on one weekday (or it has no weeks yet).",
         call. = FALSE)
  }
  r <- calendarize(sub, "week", week_start = ws)
  names(r)[names(r) == "week"] <- pw
  .aggregate_to(r, parent@grain)
}

# Replace the parent's rows at `key` with `rows`, aligned to the parent's
# columns. Rollup rows have no flight identity and none of the parent's
# pass-through columns, so those are NA -- a mixed plan, which the validator
# already accepts. Units the rollup carries that the parent lacks are added,
# NA on every other row, as .ensure_flight_cols() does for flights.
.splice_rows <- function(parent, key, rows) {
  d    <- parent@data
  keep <- d[!(line_item(d, line_item_grain(parent)) %in% key), , drop = FALSE]
  for (nm in intersect(unit_cols(), setdiff(names(rows), names(keep)))) {
    keep[[nm]] <- if (identical(nm, "unit_type")) NA_character_ else NA_real_
  }
  new <- .blank_rows(keep, nrow(rows))
  for (nm in intersect(names(rows), names(new))) new[[nm]] <- rows[[nm]]
  out <- rbind(keep, new)
  rownames(out) <- NULL
  out
}

# ---- what a topline knows ------------------------------------------------------

# Every id in the tree: the plan's own and, recursively, its subplans'.
.plan_ids <- function(plan) {
  c(plan@id, unlist(lapply(plan@subplans, .plan_ids), use.names = FALSE))
}

# Which rows of `d` (default the plan's own data) are owned by a subplan.
.backed_rows <- function(plan, d = plan@data) {
  if (!length(plan@subplans)) return(rep(FALSE, nrow(d)))
  line_item(d, line_item_grain(plan)) %in% names(plan@subplans)
}

# ---- validator ---------------------------------------------------------------

# The invariant: each subplan backs the cell it is keyed under, and the parent's
# rows for that cell are its rollup. Runs on every construction and on @<-, so
# assigning a mismatched subplan into the slot is refused, not merely
# discouraged. Recomputing a rollup per subplan on every construction is the
# cost of that guarantee; at one level of nesting it is negligible.
.validate_subplans <- function(self) {
  subs <- self@subplans
  if (!length(subs)) return(character(0))

  nms <- names(subs)
  if (is.null(nms) || any(is.na(nms) | !nzchar(nms))) {
    return("@subplans must be a named list, keyed by the parent line item each subplan backs.")
  }
  if (anyDuplicated(nms)) {
    return(paste0("@subplans has duplicate keys: ",
                  paste(unique(nms[duplicated(nms)]), collapse = ", "), "."))
  }

  errs <- character(0)
  for (key in nms) {
    sub <- subs[[key]]
    if (!S7::S7_inherits(sub, MediaPlan)) {
      errs <- c(errs, paste0("@subplans[[\"", key, "\"]] is not a MediaPlan."))
      next
    }
    msg <- tryCatch({
      k <- .subplan_key(self, sub)
      if (!identical(k, key)) {
        paste0("@subplans[[\"", key, "\"]] backs cell \"", k, "\", not \"",
               key, "\".")
      } else {
        .check_rollup(self, sub, key)
      }
    }, error = function(e) {
      paste0("@subplans[[\"", key, "\"]]: ", conditionMessage(e))
    })
    errs <- c(errs, msg)
  }
  errs
}

# Do the parent's rows at `key` equal the subplan's rollup?
.check_rollup <- function(self, sub, key, tol = 1e-6) {
  want <- .subplan_rollup(self, sub)
  d    <- self@data
  have <- d[line_item(d, line_item_grain(self)) == key, , drop = FALSE]
  wk   <- line_item(want, self@grain)
  hk   <- line_item(have, self@grain)
  stale <- paste0("rows for ", .cell_label(self, key),
                  " do not match the attached subplan's rollup; re-attach it ",
                  "with attach_subplan().")
  if (nrow(want) != nrow(have) || !setequal(wk, hk)) return(stale)
  diff <- abs(want[["planned_spend"]][match(hk, wk)] - have[["planned_spend"]])
  if (any(diff > tol)) return(stale)
  character(0)
}

# ---- the verbs ---------------------------------------------------------------

#' Attach a subplan to the cell of the plan it refines
#'
#' A **subplan** is a full [MediaPlan] owned by the team that plans one line
#' item's detail — the TV plan by partner and daypart, daily, beneath a
#' `channel + week` topline. Attaching it makes the parent's rows for that cell
#' *derived from* the subplan: they are replaced by the subplan's rollup and
#' become read-only, so there is one number with one owner. To change TV's
#' total, change the TV plan and attach it again; re-attaching **is** the
#' reconcile.
#'
#' @section Which cell:
#' The subplan says which cell it backs through its **data**, not through an
#' argument. Its [line_item_grain()] must *contain* the parent's — the same
#' columns or more — and across the parent's columns its rows must hold exactly
#' one combination: `channel == "TV"` on every row. That is the cell. A subplan
#' whose rows span two channels is refused; it would be a plan, not a
#' refinement.
#'
#' @section Cadence:
#' A weekly parent needs a subplan with a week column; its spend is re-cut onto
#' the parent's weeks with [calendarize()] before the rollup, so daily flights
#' or a different week start land correctly. A parent with no time dimension
#' accepts any subplan and collapses time as [roll_up()] would.
#'
#' @section What attaching changes:
#' Only the parent. It keeps its `@id` and `@revision`; its rows at the cell
#' are replaced — weeks the subplan does not plan disappear, weeks it adds
#' appear — and the subplan is held in `@subplans` under the cell's key. The
#' subplan itself is untouched, `@parent_id` included: lineage records what a
#' plan was *derived from*, and a subplan is authored, not derived. Attaching
#' to a cell the parent does not yet have simply adds it.
#'
#' The parent's backed rows refuse every edit — [build_scenario()] errors
#' *"channel TV is planned in a subplan; edit the subplan and re-attach"* —
#' which means a whole-plan op like `list(total = 200)` errors on a topline.
#' Ops that avoid backed rows work, and the scenario carries the subplans.
#' [roll_up()] drops them, since a rollup is a coarser view.
#'
#' A subplan is a `MediaPlan`, so it may hold subplans of its own. A plan
#' cannot be attached beneath itself.
#'
#' @param parent The topline [MediaPlan].
#' @param subplan The [MediaPlan] refining one of its cells.
#' @param key For `detach_subplan()`, the cell to release — a name from
#'   `names(parent@subplans)`, e.g. `"TV"` or `"TV | NBC"`.
#' @return `attach_subplan()` and `detach_subplan()` return the parent with
#'   its `@subplans` and rows updated. `is_topline()` returns `TRUE` when the
#'   plan holds any subplan.
#' @examples
#' topline <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(100, 40)),
#'   grain = "channel", name = "Q3 topline"
#' )
#' tv <- media_plan_from_df(
#'   data.frame(channel = "TV", partner = c("NBC", "ESPN"),
#'              planned_spend = c(70, 50)),
#'   grain = c("channel", "partner"), name = "TV detail"
#' )
#' p <- attach_subplan(topline, tv)
#' p@data                      # TV is now 120, from the subplan
#' is_topline(p)
#'
#' # TV is owned by its subplan
#' try(build_scenario(p, list(target = list(channel = "TV"), scale = 2),
#'                    name = "double TV"))
#'
#' detach_subplan(p, "TV")@subplans
#' @export
attach_subplan <- function(parent, subplan) {
  if (!S7::S7_inherits(parent, MediaPlan)) {
    stop("`parent` must be a MediaPlan.", call. = FALSE)
  }
  if (!S7::S7_inherits(subplan, MediaPlan)) {
    stop("`subplan` must be a MediaPlan.", call. = FALSE)
  }
  if (parent@id %in% .plan_ids(subplan)) {
    stop("cannot attach: the subplan contains this plan (",
         short_id(parent@id), "), which would make the plan its own ",
         "descendant.", call. = FALSE)
  }
  key  <- .subplan_key(parent, subplan)
  rows <- .subplan_rollup(parent, subplan)
  subs <- parent@subplans
  subs[[key]] <- subplan
  .copy_plan(parent, data = .splice_rows(parent, key, rows), subplans = subs)
}

#' @rdname attach_subplan
#' @export
detach_subplan <- function(parent, key) {
  if (!S7::S7_inherits(parent, MediaPlan)) {
    stop("`parent` must be a MediaPlan.", call. = FALSE)
  }
  have <- names(parent@subplans)
  if (!length(have)) {
    stop("the plan has no subplans to detach.", call. = FALSE)
  }
  if (!is.character(key) || length(key) != 1L || !key %in% have) {
    stop("no subplan at ", if (is.character(key) && length(key) == 1L)
      paste0("\"", key, "\"") else "that key", ". Attached: ",
      paste(have, collapse = ", "), ".", call. = FALSE)
  }
  subs <- parent@subplans
  subs[[key]] <- NULL
  if (!length(subs)) subs <- list()
  # The rows stay exactly as last reconciled -- now ordinary, editable rows.
  .copy_plan(parent, subplans = subs)
}

#' @rdname attach_subplan
#' @param plan A [MediaPlan].
#' @export
is_topline <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  length(plan@subplans) > 0L
}
