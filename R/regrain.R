# regrain(): give a plan a grain column it should have had.
#
# Targets may only name grain columns, so every level of a client's
# organization has to BE one. A grouping the plan does not carry -- funnel,
# Brand / Performance over `channel` -- is added as a column, read off an
# existing one through a mapping, and becomes part of every line item's key.
#
# It is the same plan, re-keyed: @id, lineage, status, approval, provenance
# and everything else are carried through .copy_plan(), as revise() carries
# them. What has to change with the key changes with it: a stored `add` and a
# stored allocation name every grain column, so they gain the new one, and
# the plan's @edits still replay on a parent regrained the same way.

#' Add an organization level to a plan's grain
#'
#' Inserts a new grain column `name`, before the column `before`, whose value
#' on each row is read from another grain column through `groups`: for
#' instance a `funnel` column grouping `channel` into Brand and Performance.
#' Every value of `from` in the plan must sit in exactly one group; anything
#' else is refused, naming the values.
#'
#' Line item keys change -- [line_item()] gains the new column -- and nothing
#' else does: the rows, their spend, and the plan's `@id`, `@parent_id`,
#' `@status`, `@approved_on`, `@rationale` and every other slot are carried
#' as [revise()] carries them. A target that names the old columns selects
#' the same rows after, so a stored op still replays. A stored `add` or
#' allocation names every grain column, so it gains the new one too, and the
#' plan's `@edits` replay on a parent regrained with the same `groups`.
#'
#' To regrain a set of revisions and drafts, regrain each plan with the same
#' arguments: the ids, and so [lineage()] and [current_approved()], are
#' unchanged.
#'
#' A plan holding subplans is refused: a subplan's grain must contain its
#' parent's, so the column would have to be added beneath it too.
#'
#' @param plan A [MediaPlan], without subplans.
#' @param name The new column's name, such as `"funnel"`. Not a column the
#'   plan already has, nor one the package reserves.
#' @param from The line item column the new one is read from, such as
#'   `"channel"`.
#' @param groups A named list: each group's name, and the values of `from` in
#'   it -- `list(Brand = c("TV", "Streaming"), Performance = "Search")`. A
#'   group may name values the plan does not have.
#' @param before The line item column the new one goes in front of; by
#'   default `from`, since a grouping is coarser than what it groups and the
#'   grain is ordered coarsest-first.
#' @return The same plan (same `@id`) with `name` in its grain and data.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Streaming", "Search"),
#'              planned_spend = c(50, 30, 40)),
#'   grain = "channel", time = "week", name = "Q3"
#' )
#' by_funnel <- regrain(plan, "funnel", from = "channel",
#'                      groups = list(Brand = c("TV", "Streaming"),
#'                                    Performance = "Search"))
#' by_funnel@grain
#' line_item(by_funnel@data, line_item_grain(by_funnel))
#' @seealso [assign_sections()], which needs every organization level to be
#'   a grain column.
#' @export
regrain <- function(plan, name, from, groups, before = from) {
  .stop_if_not_plan(plan)
  if (length(plan@subplans)) {
    stop("`plan` holds subplans, which regrain() does not reach into: a ",
         "subplan's grain must contain its parent's. Detach them first ",
         "with detach_subplan().", call. = FALSE)
  }
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(name)) {
    stop("`name` must be a single column name, such as \"funnel\".",
         call. = FALSE)
  }
  reserved <- c("planned_spend", bound_cols(), flight_cols(), unit_cols())
  if (name %in% c(names(plan@data), reserved)) {
    stop("`name` '", name, "' is already a column of the plan, or one the ",
         "package reserves; choose another.", call. = FALSE)
  }
  .check_line_item_col(from, "from", plan)
  .check_line_item_col(before, "before", plan)

  # Every value of `from` the plan holds -- or that its stored edits name --
  # must have exactly one group.
  needed <- unique(c(as.character(plan@data[[from]]),
                     .edits_values(plan@edits, from)))
  group_of <- .group_lookup(groups, needed, from)

  .copy_plan(
    plan,
    data  = .add_column(plan@data, name, group_of, from, before),
    grain = .insert_before(plan@grain, name, before),
    edits = .regrain_edits(plan@edits, name, group_of, from, before)
  )
}

.check_line_item_col <- function(x, arg, plan) {
  lg <- line_item_grain(plan)
  if (!is.character(x) || length(x) != 1L || !x %in% lg) {
    stop("`", arg, "` must name one of the plan's line item columns (",
         paste(lg, collapse = ", "), ").", call. = FALSE)
  }
}

# value of `from` -> its group, for each of `values`; refused unless each is in
# exactly one group.
.group_lookup <- function(groups, values, from) {
  gn <- names(groups)
  if (!is.list(groups) || is.data.frame(groups) || !length(groups) ||
      is.null(gn) || any(!nzchar(gn)) || anyDuplicated(gn)) {
    stop("`groups` must be a named list -- one entry per group, with ",
         "distinct names -- of the values of '", from, "' in each.",
         call. = FALSE)
  }
  members <- lapply(groups, function(v) as.character(unlist(v)))
  owners  <- lapply(values, function(v) {
    gn[vapply(members, function(m) v %in% m, logical(1))]
  })
  n <- lengths(owners)
  if (any(n == 0L)) {
    stop("`groups` places no group on ", from, " value(s): ",
         paste(values[n == 0L], collapse = ", "), ". Every value of '", from,
         "' the plan holds, or its stored edits add, must be in exactly one ",
         "group.", call. = FALSE)
  }
  if (any(n > 1L)) {
    twice <- which(n > 1L)
    stop("`groups` puts ", from, " value(s) in more than one group: ",
         paste0(values[twice], " (",
                vapply(owners[twice], paste, character(1), collapse = ", "),
                ")", collapse = "; "),
         ". Each must be in exactly one.", call. = FALSE)
  }
  stats::setNames(unlist(owners), values)
}

# `x` with `new` inserted in front of `before`.
.insert_before <- function(x, new, before) {
  append(x, new, after = match(before, x) - 1L)
}

# A data frame with the group column inserted in front of `before`.
.add_column <- function(d, name, group_of, from, before) {
  d[[name]] <- unname(group_of[as.character(d[[from]])])
  d[, .insert_before(setdiff(names(d), name), name, before), drop = FALSE]
}

# The values of `from` a stored edits record names in full -- in an `add`, or
# an allocation's rows -- and so would need a group.
.edits_values <- function(edits, from) {
  if (identical(edits$form, "allocation")) {
    return(as.character(edits$data[[from]]))
  }
  adds <- Filter(function(op) !is.null(op[["add"]]), edits$ops)
  as.character(unlist(lapply(adds, function(op) op$add[[from]])))
}

# A stored edits record re-keyed with the plan. Targets need nothing: they
# name columns that are still there and select the same rows. An `add` and an
# allocation name every grain column, so they gain the new one.
.regrain_edits <- function(edits, name, group_of, from, before) {
  if (identical(edits$form, "allocation")) {
    edits$data <- .add_column(edits$data, name, group_of, from, before)
  } else if (identical(edits$form, "ops")) {
    edits$ops <- lapply(edits$ops, function(op) {
      if (is.null(op[["add"]])) return(op)
      spec <- op$add
      spec[[name]] <- unname(group_of[[as.character(spec[[from]])]])
      op$add <- spec[.insert_before(setdiff(names(spec), name), name, before)]
      op
    })
  }
  edits
}
