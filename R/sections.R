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
# matcher. Errors start with `where`, plus the target's position when there is
# more than one.
.match_targets <- function(d, plan, targets, during = NULL, strict = TRUE,
                           where = "") {
  keep <- rep(FALSE, nrow(d))
  for (i in seq_along(targets)) {
    at <- if (length(targets) > 1L) paste0(where, "target ", i, ": ") else where
    keep <- keep | .find_rows(d, plan, targets[[i]], during, at,
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

# ---- assign_sections -------------------------------------------------------------

#' Which section each line item belongs to
#'
#' Places every line item of a plan in the sections of an organization tree:
#' brand and performance, lines of business, channels. `sections` holds the
#' tree's **leaves**, each a target -- the same named list of grain column =
#' value(s) an op uses -- or a list of targets. A line item is in a section
#' when the section matches any of its rows.
#'
#' A clean tree puts every line item in exactly one leaf. This reports where
#' the plan and the tree disagree -- line items in two leaves, line items in
#' none -- and **never errors** on either: whether an overlap is a mistake in
#' the tree or a shared line, and whether an unplaced line item belongs to
#' nobody or to a leaf not yet drawn, is the caller's decision.
#'
#' A section may name a value the plan does not have (an organization names
#' channels a plan has stopped buying), so values are matched leniently, as
#' [match_rows()] with `strict = FALSE`. A column that is not in the grain is
#' still an error: the organization's levels must be grain columns -- add a
#' missing level with [regrain()].
#'
#' @param plan A [MediaPlan].
#' @param sections A named list, one entry per leaf section: its target, or a
#'   list of targets. Names must be distinct.
#' @return A data frame with one row per line item ([line_item_grain()]):
#'   \describe{
#'     \item{`line_item`}{Its key, as [line_item()] writes it.}
#'     \item{`section`}{The one section it is in; `NA` when it is in none, or
#'       in more than one.}
#'     \item{`n_matches`}{How many sections it is in.}
#'   }
#'   Attributes `overlaps` (a data frame of `line_item` and `sections`, the
#'   sections' names joined with `", "`) and `unmatched` (the line items in no
#'   section) list the disagreements, which also print beneath the table.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "TV", "Search", "Social"),
#'              partner = c("NBC", "ESPN", "Google", "Meta"),
#'              planned_spend = c(50, 30, 40, 40)),
#'   grain = c("channel", "partner"), time = "week", name = "Q3"
#' )
#' assign_sections(plan, list(
#'   Video  = list(channel = "TV"),
#'   Search = list(channel = "Search"),
#'   Google = list(partner = "Google")   # overlaps Search
#' ))
#' @seealso [match_rows()]; [check_budget()] for a section's envelope.
#' @export
assign_sections <- function(plan, sections) {
  .stop_if_not_plan(plan)
  nm <- names(sections)
  if (!is.list(sections) || is.data.frame(sections) || !length(sections) ||
      is.null(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) {
    stop("`sections` must be a named list -- one entry per section, with ",
         "distinct names -- each a target or a list of targets.",
         call. = FALSE)
  }

  d     <- plan@data
  key   <- line_item(d, line_item_grain(plan))
  items <- unique(key)

  # hits[i, s]: line item i has a row section s matches.
  hits <- matrix(FALSE, nrow = length(items), ncol = length(sections),
                 dimnames = list(NULL, nm))
  for (s in nm) {
    where <- paste0("section '", s, "': ")
    rows  <- .match_targets(d, plan, .as_targets(sections[[s]], "section"),
                            strict = FALSE, where = where)
    hits[, s] <- items %in% key[rows]
  }

  n <- rowSums(hits)
  sections_of <- function(i) paste(nm[hits[i, ]], collapse = ", ")
  out <- data.frame(
    line_item = items,
    section   = ifelse(n == 1L, vapply(seq_along(items), sections_of, ""),
                       NA_character_),
    n_matches = as.integer(n),
    stringsAsFactors = FALSE
  )

  over <- which(n > 1L)
  attr(out, "overlaps") <- data.frame(
    line_item = items[over],
    sections  = vapply(over, sections_of, character(1)),
    stringsAsFactors = FALSE
  )
  attr(out, "unmatched") <- items[n == 0L]
  class(out) <- c("section_assignment", "data.frame")
  out
}

#' @rdname assign_sections
#' @param x A `section_assignment`, as returned by `assign_sections()`.
#' @param ... Passed to the data frame print method.
#' @export
print.section_assignment <- function(x, ...) {
  print.data.frame(x, ...)
  # Read off the columns, not the attributes, so a subset prints its own.
  if (all(c("line_item", "n_matches") %in% names(x))) {
    over <- x$line_item[x$n_matches > 1L]
    none <- x$line_item[x$n_matches == 0L]
    cat(if (!length(over) && !length(none)) {
      "Every line item is in exactly one section.\n"
    } else {
      paste0(paste(c(
        if (length(over)) paste0(length(over), " in more than one section (",
                                 .first_few(over), ")"),
        if (length(none)) paste0(length(none), " in none (", .first_few(none),
                                 ")")
      ), collapse = "; "), ".\n")
    })
  }
  invisible(x)
}

# ---- Ops, however written ----------------------------------------------------------

# `ops` as the canonical op list build_scenario() would apply: a list of ops, a
# single op, constructor-built or JSON-parsed -- or a stored `@edits` record,
# so a draft's own record can be checked. An allocation names its rows
# outright and is not an op list; `fn` names the caller in the refusal.
.as_op_list <- function(plan, ops, fn) {
  form <- if (is.list(ops) && !is.data.frame(ops)) ops[["form"]]
  if (identical(form, "ops")) ops <- ops[["ops"]]
  if (identical(form, "allocation") || is.data.frame(ops) ||
      (is.numeric(ops) && !is.null(names(ops)))) {
    stop(fn, " checks operations. An allocation names its rows outright: ",
         "read them with match_rows().", call. = FALSE)
  }
  .record_edits(plan, ops)$ops
}

# The row selections an op makes, each with the target and window that make
# it, named by side: `from` and `to` for a transfer, `target` otherwise. `add`
# selects nothing -- it creates rows -- and is handled by its callers.
.op_sides <- function(op, key) {
  if (identical(key, "transfer")) {
    return(list(
      from = list(target = op[["from"]], during = op[["from_during"]] %||% op[["during"]]),
      to   = list(target = op[["to"]],   during = op[["to_during"]]   %||% op[["during"]])
    ))
  }
  list(target = list(target = op[["target"]], during = op[["during"]]))
}

# The error prefix .apply_op() gives a side, so a selection made here fails
# with the words the edit itself would use.
.side_where <- function(i, key, side) {
  where <- paste0("edit op ", i, ": ")
  if (identical(key, "transfer")) paste0(where, "`", side, "`: ") else where
}

# Rows in `after` that are not in `before`, by their full grain key: what an
# `add` created.
.added_rows <- function(before, after, plan) {
  after[!line_item(after, plan@grain) %in% line_item(before, plan@grain), ,
        drop = FALSE]
}

# ---- ops_within ------------------------------------------------------------------

#' Do these ops stay inside a scope?
#'
#' Checks that every row a list of ops would touch lies inside a planner's
#' scope -- a list of targets, such as the sections they own. The answer is
#' one row per op side that reaches outside it, so zero rows means every op
#' stays inside.
#'
#' Rows are resolved exactly as [build_scenario()] resolves them, **in
#' order**: an `add` earlier in the list creates rows a later op may target,
#' and a `drop` removes rows a later op can no longer reach. `during`, and a
#' transfer's `from_during` / `to_during`, narrow each side as they do when
#' the op is applied. An `add` is outside when the line item it creates does
#' not match the scope.
#'
#' A target that does not exist is refused here with the error
#' [build_scenario()] gives. Ops that change which rows exist, when they run,
#' or how they are bound (`add`, `drop`, `shift`, `restage`, `rebound`) are
#' applied as they go, and refused as they would be there. Ops that only move
#' money are not applied: they cannot change what a later op selects, and
#' whether the money can move -- past a floor, say -- is [build_scenario()]'s
#' question, whose answer must not hide this one. The scope is read leniently
#' ([match_rows()] with `strict = FALSE`): it may name values the plan no
#' longer has.
#'
#' @param plan The [MediaPlan] the ops would be applied to.
#' @param ops The ops, in any form [build_scenario()] takes them: a list of
#'   ops or a single op -- plain lists, [op constructors][ops], or parsed from
#'   JSON -- or a scenario's `@edits` record.
#' @param scope The scope: a target, or a list of targets. Empty is the whole
#'   plan.
#' @return A data frame with one row per op side that selects rows outside
#'   `scope`:
#'   \describe{
#'     \item{`op`}{The op's position in `ops`.}
#'     \item{`side`}{`"target"`, `"from"`, `"to"` or `"add"`.}
#'     \item{`line_items`}{A list column: the line items ([line_item()] at
#'       [line_item_grain()]) that side reaches outside the scope.}
#'   }
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "TV", "Search", "Social"),
#'              partner = c("NBC", "ESPN", "Google", "Meta"),
#'              planned_spend = c(50, 30, 40, 40)),
#'   grain = c("channel", "partner"), time = "week", name = "Q3"
#' )
#' video <- list(channel = "TV")
#'
#' # inside: money moves between two TV partners
#' ops_within(plan, op_transfer(10, from = list(partner = "NBC"),
#'                              to = list(partner = "ESPN")), video)
#'
#' # outside: the money comes from Search
#' ops_within(plan, op_transfer(10, from = list(channel = "Search"),
#'                              to = list(partner = "ESPN")), video)
#' @seealso [match_rows()], [rebase_check()]
#' @export
ops_within <- function(plan, ops, scope) {
  .stop_if_not_plan(plan)
  if (missing(scope)) {
    stop("`scope` is required: a target, or a list of targets. Pass list() ",
         "for the whole plan.", call. = FALSE)
  }
  targets <- .as_targets(scope, "scope")
  ops     <- .as_op_list(plan, ops, "ops_within()")
  lg      <- line_item_grain(plan)

  in_scope <- function(rows) {
    .match_targets(rows, plan, targets, strict = FALSE, where = "`scope`: ")
  }
  found <- list()
  outside <- function(i, side, rows) {
    if (!nrow(rows)) return(NULL)
    list(list(op = i, side = side, line_items = unique(line_item(rows, lg))))
  }

  d <- plan@data
  for (i in seq_along(ops)) {
    op  <- ops[[i]]
    key <- .op_key(op)
    if (identical(key, "add")) {
      after <- .apply_op(d, plan, op, i)
      new   <- .added_rows(d, after, plan)
      found <- c(found, outside(i, "add", new[!in_scope(new), , drop = FALSE]))
    } else {
      inside <- in_scope(d)
      sides  <- .op_sides(op, key)
      for (side in names(sides)) {
        sel <- .find_rows(d, plan, sides[[side]]$target, sides[[side]]$during,
                          .side_where(i, key, side))
        found <- c(found, outside(i, side, d[sel & !inside, , drop = FALSE]))
      }
      # An op that only moves money cannot change which rows a later op
      # selects, so it is not applied: whether the money can move is
      # build_scenario()'s question, and its answer must not hide this one.
      # Ops that change which rows exist, when they run, or how they are
      # bound (a later drop may need an earlier rebound) are applied.
      after <- if (identical(.op_registry[[key]]$family, "value")) d else
        .apply_op(d, plan, op, i)
    }
    d <- after
  }

  out <- data.frame(
    op   = vapply(found, function(f) f$op, integer(1)),
    side = vapply(found, function(f) f$side, character(1)),
    stringsAsFactors = FALSE
  )
  out$line_items <- lapply(found, function(f) f$line_items)
  out
}
