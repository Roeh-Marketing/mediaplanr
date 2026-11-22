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
# One target is a named list of column -> value(s): `list(channel = "TV")`. A
# list of targets is a list of those, unnamed or named -- named is how a
# planner's sections are written, so `sections[c("TV", "Search")]` is a scope.
# The two cannot be confused: a target's values are vectors, or unnamed lists
# when parsed from a JSON array, never named lists. Empty or NULL is one empty
# target: the whole plan, exactly as an op with no target.
.as_targets <- function(x, what = "target") {
  if (is.null(x) || !length(x)) return(list(list()))
  is_named  <- function(v) !is.null(names(v)) && all(nzchar(names(v)))
  is_target <- function(v) is.list(v) && length(v) > 0 && is_named(v)
  if (is.list(x) && !is.data.frame(x)) {
    if (is.null(names(x)) &&
        all(vapply(x, function(v) is_target(v) || identical(v, list()),
                   logical(1)))) {
      return(x)
    }
    # Named: a list of targets only if every entry is a non-empty one, so a
    # JSON `{"channel": []}` is still refused as a target with no value
    # rather than read as an empty target that matches everything.
    if (is_named(x)) {
      return(if (all(vapply(x, is_target, logical(1)))) unname(x) else list(x))
    }
  }
  stop("`", what, "` must be a target -- a named list of grain column = ",
       "value(s), such as list(channel = \"TV\") -- or a list of them.",
       call. = FALSE)
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
#' @param target One target (`list(channel = "TV")`), or a list of targets
#'   (`list(list(channel = "TV"), list(partner = "DSP A"))`), named or not --
#'   so a planner's sections, `sections[c("Video", "Search")]`, are a scope.
#'   Empty or `NULL` is the whole plan, as for an op.
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

# Registered against base::print explicitly: a bare S3method(print, ...)
# would be registered against the namespace's own copy of `print`, which
# S7::method(print, ...) <- leaves there, and base::print would never find it.
#' @exportS3Method base::print
#' @noRd
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

# ---- rebase_check ------------------------------------------------------------------

#' Would these ops do the same on the current revision?
#'
#' A draft is a scenario under a base revision, and its ops are approved by
#' replaying them on the **current** revision, so approved revisions stay one
#' chain. That is safe when the rows the ops touch are the same on both
#' plans. This finds the rows where they are not.
#'
#' The ops are resolved on both plans, in order, as [build_scenario()] would
#' apply them. For each op side, the rows it selects on `base` are compared
#' with the rows it selects on `current`: a row selected on one and not the
#' other is reported, and so is a row selected on both whose `planned_spend`,
#' spend bounds ([bound_cols()]) or flight columns ([flight_cols()]) differ.
#' Those are the facts an op's arithmetic reads -- a `delta` spreads by the
#' group's spend, a transfer routes around its bounds, money moved into an
#' empty line spreads by its flight days -- so **zero rows means replaying
#' the ops on `current` does to those rows what it did on `base`**.
#'
#' Rows the ops do not touch may differ freely: a sibling section approved
#' in between is not a conflict. An `add` selects nothing, so it is compared
#' only through the ops after it. An op that cannot be applied to one of the
#' plans at all -- its target is gone -- is an error naming the plan, since
#' replaying it there would fail the same way.
#'
#' @param base The plan the ops were written against: the draft's parent.
#' @param current The plan they would be replayed on: normally the current
#'   approved revision. Must share `base`'s grain.
#' @param ops The ops, in any form [ops_within()] takes -- including the
#'   draft's own `@edits` record.
#' @return A data frame with one row per op side and row that differs:
#'   \describe{
#'     \item{`op`, `side`}{As in [ops_within()].}
#'     \item{`row`}{The row's key: [line_item()] at the full grain.}
#'     \item{`issue`}{`"changed"`, `"base only"` or `"current only"`.}
#'     \item{`columns`}{For `"changed"`, the columns that differ, joined
#'       with `", "`; `NA` otherwise.}
#'     \item{`base_spend`, `current_spend`}{The row's planned spend on each
#'       plan as the op finds it; `NA` where the op does not select it.}
#'   }
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "TV", "Search", "Social"),
#'              partner = c("NBC", "ESPN", "Google", "Meta"),
#'              planned_spend = c(50, 30, 40, 40)),
#'   grain = c("channel", "partner"), time = "week", name = "Rev 1"
#' )
#' draft <- op_transfer(10, from = list(partner = "NBC"),
#'                      to = list(partner = "ESPN"))
#'
#' # Search was cut in the meantime: no conflict with a TV draft
#' current <- build_scenario(base, op_scale(0.5, list(channel = "Search")),
#'                           name = "Rev 2")
#' rebase_check(base, current, draft)
#'
#' # NBC was cut: the draft's source is not what it was
#' current <- build_scenario(base, op_scale(0.5, list(partner = "NBC")),
#'                           name = "Rev 2")
#' rebase_check(base, current, draft)
#' @seealso [ops_within()], [current_approved()]
#' @export
rebase_check <- function(base, current, ops) {
  .stop_if_not_plan(base, "base")
  .stop_if_not_plan(current, "current")
  if (!identical(base@grain, current@grain)) {
    stop("`base` and `current` must share a grain; base is (",
         paste(base@grain, collapse = ", "), "), current is (",
         paste(current@grain, collapse = ", "), "). Regrain the older one ",
         "with regrain().", call. = FALSE)
  }
  ops <- .as_op_list(base, ops, "rebase_check()")

  # Starts with the empty table, so no differences still has the columns.
  found <- list(.rebase_diff(0L, "", base@data[0, ], current@data[0, ],
                             base@grain))
  db <- base@data
  dc <- current@data
  for (i in seq_along(ops)) {
    op  <- ops[[i]]
    key <- .op_key(op)
    if (!identical(key, "add")) {
      sides <- .op_sides(op, key)
      for (side in names(sides)) {
        s  <- sides[[side]]
        at <- .side_where(i, key, side)
        on_base    <- .find_rows(db, base, s$target, s$during, at, strict = FALSE)
        on_current <- .find_rows(dc, current, s$target, s$during, at,
                                 strict = FALSE)
        found <- c(found, list(.rebase_diff(
          i, side, db[on_base, , drop = FALSE], dc[on_current, , drop = FALSE],
          base@grain)))
      }
    }
    # Applied to both, so the next op finds each plan as the replay would.
    db <- .rebase_apply(db, base, op, i, "base")
    dc <- .rebase_apply(dc, current, op, i, "current")
  }

  out <- do.call(rbind, found)
  rownames(out) <- NULL
  out
}

.rebase_apply <- function(d, plan, op, i, which) {
  tryCatch(.apply_op(d, plan, op, i), error = function(e) {
    stop("`ops` cannot be replayed on `", which, "`: ", conditionMessage(e),
         call. = FALSE)
  })
}

# One op side's selections on the two plans, compared row by row.
.rebase_diff <- function(i, side, on_base, on_current, grain) {
  kb <- line_item(on_base, grain)
  kc <- line_item(on_current, grain)
  both <- intersect(kb, kc)
  rb <- on_base[match(both, kb), , drop = FALSE]
  rc <- on_current[match(both, kc), , drop = FALSE]

  # The facts an op's arithmetic reads. A column only one plan carries reads
  # as NA (no bound, no flight) on the other.
  cols <- intersect(c("planned_spend", bound_cols(), flight_cols()),
                    union(names(on_base), names(on_current)))
  differs <- matrix(FALSE, nrow = length(both), ncol = length(cols),
                    dimnames = list(NULL, cols))
  for (col in cols) {
    differs[, col] <- !.same_values(rb[[col]], rc[[col]], length(both))
  }
  changed <- which(rowSums(differs) > 0)
  only_b  <- setdiff(kb, kc)
  only_c  <- setdiff(kc, kb)

  spend_of <- function(d, k, keys) d[["planned_spend"]][match(keys, k)]
  n_only <- length(only_b) + length(only_c)
  n <- length(changed) + n_only
  data.frame(
    op      = rep(as.integer(i), n),
    side    = rep(side, n),
    row     = c(both[changed], only_b, only_c),
    issue   = c(rep("changed", length(changed)),
                rep("base only", length(only_b)),
                rep("current only", length(only_c))),
    columns = c(vapply(changed, function(r) {
                  paste(cols[differs[r, ]], collapse = ", ")
                }, character(1)), rep(NA_character_, n_only)),
    base_spend    = c(spend_of(on_base, kb, both[changed]),
                      spend_of(on_base, kb, only_b),
                      rep(NA_real_, length(only_c))),
    current_spend = c(spend_of(on_current, kc, both[changed]),
                      rep(NA_real_, length(only_b)),
                      spend_of(on_current, kc, only_c)),
    stringsAsFactors = FALSE
  )
}

# Equal row by row: numbers to the cent, anything else as text, NA equal to
# NA. A column one side lacks (NULL) is all NA.
.same_values <- function(x, y, n) {
  if (is.null(x)) x <- rep(NA, n)
  if (is.null(y)) y <- rep(NA, n)
  if (is.numeric(x) && is.numeric(y)) {
    same <- abs(x - y) < 0.005
  } else {
    same <- as.character(x) == as.character(y)
  }
  same[is.na(x) & is.na(y)] <- TRUE
  same[is.na(same)] <- FALSE
  same
}
