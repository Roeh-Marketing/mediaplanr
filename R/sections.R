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
