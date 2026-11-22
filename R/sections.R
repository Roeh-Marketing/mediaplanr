# Sections and scopes: reading a plan the way an organization divides it.
#
# A client's organization -- brand and performance, lines of business,
# channels -- is a tree of SECTIONS, and each planner is SCOPED to some of
# them. Neither needs a new object:
#
#   a section   is a target: the named list of grain column -> value(s) an op,
#               a check_budget() row and a PlanConstraints rule already use
#   a scope     is a list of targets: the rows matching any of them
#   an envelope is a check_budget() row
#
# Every function here resolves rows through the matcher the edit path uses
# (.find_rows() in verbs.R), so a scope check can never disagree with what an
# edit would touch. The app must not match rows itself: a second matcher
# drifts from this one.
#
# These READ. They never refuse subplan-owned rows the way an edit does --
# saying which rows a target names is not editing them.

# ---- Targets and lists of targets ----------------------------------------------

# One target, or a list of them, as a list of targets.
#
# One target is a NAMED list (`list(channel = "TV")`); a list of targets is an
# UNNAMED list of those. Empty or NULL is one empty target: the whole plan,
# exactly as an op with no target.
.as_targets <- function(x, what = "target") {
  if (is.null(x) || !length(x)) return(list(list()))
  if (is.list(x) && !is.data.frame(x)) {
    nm <- names(x)
    if (!is.null(nm) && all(nzchar(nm))) return(list(x))
    is_target <- vapply(x, is.list, logical(1))
    if (is.null(nm) && all(is_target)) return(x)
  }
  stop("`", what, "` must be a target -- a named list of grain column = ",
       "value(s), such as list(channel = \"TV\") -- or an unnamed list of ",
       "them.", call. = FALSE)
}

# Rows matching ANY of `targets` (each narrowed by `during`), through the one
# matcher. Errors carry the target's position when there is more than one.
.match_targets <- function(d, plan, targets, during = NULL, strict = TRUE,
                           what = "target") {
  keep <- rep(FALSE, nrow(d))
  for (i in seq_along(targets)) {
    where <- if (length(targets) > 1L) paste0(what, " ", i, ": ") else ""
    keep <- keep | .find_rows(d, plan, targets[[i]], during, where,
                              strict = strict)
  }
  keep
}

.stop_if_not_plan <- function(x, arg = "plan") {
  if (!S7::S7_inherits(x, MediaPlan)) {
    stop("`", arg, "` must be a MediaPlan.", call. = FALSE)
  }
}

# ---- match_rows ------------------------------------------------------------------

#' The rows a target selects
#'
#' Resolves a target -- or a list of them -- to the plan's rows, exactly as
#' [build_scenario()] resolves an op's `target` and `during`. It is the one
#' matcher: a caller that needs to know which rows a section, a scope or an
#' op names asks here rather than matching rows itself, so the answer can
#' never disagree with what an edit would touch.
#'
#' A target is a named list of grain column = value(s), naming any subset of
#' the grain: every named column must match (AND), and a column given several
#' values matches any of them. A **list of targets** matches the rows any one
#' of them matches (OR) -- which is what a planner's scope is.
#'
#' Unlike an edit, this does not refuse rows a subplan owns: it reads, it does
#' not edit.
#'
#' @param plan A [MediaPlan].
#' @param target One target (`list(channel = "TV")`), or an unnamed list of
#'   targets (`list(list(channel = "TV"), list(partner = "DSP A"))`). Empty or
#'   `NULL` is the whole plan, as for an op.
#' @param during Optional `list(from =, to =)`: narrows to rows whose period
#'   **overlaps** the window, as an op's `during` does.
#' @param strict With `TRUE` (the default), a value the plan does not have, a
#'   target whose values never occur together, or a window with nothing in
#'   market is an error naming the alternatives -- exactly what an op's target
#'   gives. With `FALSE`, those match nothing instead: a scope may name a
#'   value the plan no longer has. A column that is not in the grain is an
#'   error either way.
#' @return A logical vector over the rows of `plan@data`.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "TV", "Search", "Social"),
#'              partner = c("NBC", "ESPN", "Google", "Meta"),
#'              planned_spend = c(50, 30, 40, 40)),
#'   grain = c("channel", "partner"), time = "week", name = "Q3"
#' )
#' match_rows(plan, list(channel = "TV"))
#'
#' # a scope: TV, or anything on Google
#' match_rows(plan, list(list(channel = "TV"), list(partner = "Google")))
#'
#' # a scope may name a channel the plan no longer buys
#' match_rows(plan, list(channel = c("Search", "Audio")), strict = FALSE)
#' @seealso [assign_sections()], [ops_within()], [rebase_check()]
#' @export
match_rows <- function(plan, target, during = NULL, strict = TRUE) {
  .stop_if_not_plan(plan)
  if (!isTRUE(strict) && !isFALSE(strict)) {
    stop("`strict` must be TRUE or FALSE.", call. = FALSE)
  }
  .match_targets(plan@data, plan, .as_targets(target), during, strict)
}
