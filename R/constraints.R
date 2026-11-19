# PlanConstraints: one definition of "allowed".
#
# Spend bounds (bounds.R) say what one row may hold. Plans also live under
# rules about GROUPS of rows: Streaming holds at least 40% of the plan, the
# upfront totals exactly 360k however it is phased, no channel swings more
# than 25% from the approved plan. Those are written down here, once, as a
# PlanConstraints object, so that the agent checking its own proposal and the
# optimizer (mrmopt, later) read the same rules rather than two copies that
# drift.
#
# A rule is a plain list, like an op:
#
#   list(type = "min_share", value = 0.4, target = list(channel = "Streaming"),
#        during = list(from = "2026-10-01", to = "2026-12-31"), note = "...")
#
# and the object keeps its rules as a data frame, one row per rule, with
# `target` and `during` as list columns. Checking a plan against them is a
# pairing, like check_budget(): a violation is warned about, never refused.

# ---- rule types ----------------------------------------------------------------

# What each rule type measures, which way its limit binds, and the range its
# value may take. `measure` is one of:
#
#   "spend"       the target rows' spend in the window
#   "share"       that spend as a share of the whole plan's in the window
#   "change_abs"  how far that spend moved from a reference plan's, in money
#   "change_pct"  ... as a fraction of the reference plan's
#
# `bound` is "min", "max" or "equal".
.rule_type <- function(measure, bound, description, max = Inf) {
  list(measure = measure, bound = bound, description = description,
       min = 0, max = max)
}

.rule_types <- list(
  min_spend = .rule_type(
    "spend", "min", "The target rows spend at least this much in the window."),
  max_spend = .rule_type(
    "spend", "max", "The target rows spend at most this much in the window."),
  fixed_total = .rule_type(
    "spend", "equal",
    "The target rows spend exactly this in total over the window, phased
    however the plan likes -- a commitment on a line or a flight's total."),
  min_share = .rule_type(
    "share", "min",
    "The target rows hold at least this share (0 to 1) of the plan's spend
    in the window.", max = 1),
  max_share = .rule_type(
    "share", "max",
    "The target rows hold at most this share (0 to 1) of the plan's spend
    in the window.", max = 1),
  max_change_abs = .rule_type(
    "change_abs", "max",
    "The target rows' spend in the window moves by at most this amount from
    the reference plan's."),
  max_change_pct = .rule_type(
    "change_pct", "max",
    "The target rows' spend in the window moves by at most this fraction
    (0.25 = 25%) of the reference plan's.")
)

# Change rules are measured against another plan, which must be given.
.needs_reference <- function(type) {
  .rule_types[[type]]$measure %in% c("change_abs", "change_pct")
}

# ---- one rule, checked and made canonical ----------------------------------------

# Check a rule (a plain list) for everything that needs no plan. `where`
# prefixes any error.
.check_rule <- function(rule, where = "") {
  if (!is.list(rule) || is.null(names(rule))) {
    stop(where, "a rule must be a named list with a `type` and a `value`.",
         call. = FALSE)
  }
  extra <- setdiff(names(rule), c("type", "value", "target", "during", "note"))
  if (length(extra)) {
    stop(where, "unknown field(s): ", paste(extra, collapse = ", "), ". A rule ",
         "takes: type, value, target, during, note.", call. = FALSE)
  }
  type <- rule[["type"]]
  if (!is.character(type) || length(type) != 1L || !type %in% names(.rule_types)) {
    stop(where, "`type` must be one of: ",
         paste(names(.rule_types), collapse = ", "), ".", call. = FALSE)
  }
  spec <- .rule_types[[type]]
  .check_number(rule[["value"]], "value", min = spec$min, where = where)
  if (rule[["value"]] > spec$max) {
    stop(where, "`value` of a ", type, " rule is a share, from 0 to 1; got ",
         rule[["value"]], ".", call. = FALSE)
  }
  .check_target_shape(rule[["target"]], "target", where)
  if (!is.null(rule[["during"]])) .check_rule_window(rule[["during"]], where)
  note <- rule[["note"]]
  if (!is.null(note) && (!is.character(note) || length(note) != 1L)) {
    stop(where, "`note` must be a single string.", call. = FALSE)
  }
  invisible(rule)
}

# A rule's window is whole days: rules measure spend day by day, so a moment
# would be cut to its day anyway, and saying so is better than doing it quietly.
.check_rule_window <- function(during, where) {
  .check_window(during, "during", where)
  for (end in c("from", "to")) {
    v <- during[[end]]
    is_date <- inherits(v, "Date") ||
      (is.character(v) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", v))
    if (!is_date) {
      stop(where, "`during$", end, "` must be a date (a rule measures whole ",
           "days); got: ", format(v), ".", call. = FALSE)
    }
  }
}

# A rule in canonical form: fields in a fixed order, the value a double,
# target values as text, the window as ISO dates, and an empty note rather
# than none -- so a rule written by hand, built by rule_*() or read from JSON
# is the same object.
.canonical_rule <- function(rule) {
  during <- rule[["during"]]
  list(
    type   = rule[["type"]],
    value  = as.numeric(rule[["value"]]),
    target = .canonical_target(rule[["target"]]),
    during = if (is.null(during)) NULL else
      list(from = format(as.Date(during[["from"]])),
           to   = format(as.Date(during[["to"]]))),
    note   = rule[["note"]] %||% ""
  )
}

# ---- the rules as a table ------------------------------------------------------

# Canonical rules -> the @rules data frame, `target` and `during` list columns.
.rules_frame <- function(rules) {
  frame <- data.frame(
    type  = vapply(rules, function(r) r$type, character(1)),
    value = vapply(rules, function(r) r$value, numeric(1)),
    stringsAsFactors = FALSE
  )
  frame$target <- lapply(rules, function(r) r$target)
  frame$during <- lapply(rules, function(r) r$during)
  frame$note   <- vapply(rules, function(r) r$note, character(1))
  frame
}

# Row i of the @rules data frame, back as a rule list.
.rule_at <- function(frame, i) {
  list(type = frame$type[i], value = frame$value[i],
       target = frame$target[[i]], during = frame$during[[i]],
       note = frame$note[i])
}

# A rules table as a spreadsheet holds it -- type, value, optional from, to
# and note, and line item columns where a blank means any value -- read into
# rule lists.
.rules_from_table <- function(table) {
  need <- setdiff(c("type", "value"), names(table))
  if (length(need)) {
    stop("a rules table needs column(s): ", paste(need, collapse = ", "), ".",
         call. = FALSE)
  }
  target_cols <- setdiff(names(table), c("type", "value", "from", "to", "note"))
  blank <- function(v) is.null(v) || is.na(v) || !nzchar(trimws(v))

  lapply(seq_len(nrow(table)), function(i) {
    row <- table[i, , drop = FALSE]
    target <- list()
    for (col in target_cols) {
      if (!blank(row[[col]])) target[[col]] <- as.character(row[[col]])
    }
    window <- c(from = !blank(row$from), to = !blank(row$to))
    if (sum(window) == 1L) {
      stop("rules row ", i, ": give both `from` and `to`, or neither.",
           call. = FALSE)
    }
    list(type = as.character(row$type), value = row$value, target = target,
         during = if (all(window)) list(from = as.character(row$from),
                                        to = as.character(row$to)),
         note = if (blank(row$note)) "" else as.character(row$note))
  })
}

# ---- the class -----------------------------------------------------------------

#' A set of rules a plan must keep
#'
#' The group rules a plan lives under -- Streaming holds at least 40% of the
#' plan, the upfront totals exactly 360,000 however it is phased, Online Video
#' moves no more than 25% from the approved plan -- written down once, so the
#' agent checking its own proposal and the optimizer read the same definition
#' of "allowed". Build one with [plan_constraints()]; check a plan against it
#' with [check_constraints()].
#'
#' Rules about **one row** -- a commitment, a floor, a cap on a line item in a
#' month -- are not here: they are spend bounds on the plan itself
#' ([bound_cols()]), which every edit respects. A `PlanConstraints` holds the
#' rules about **groups** of rows, which a single edit cannot enforce row by
#' row but a plan can be checked against.
#'
#' @param id Opaque id; a scenario's `rationale$constraints_id` refers to it.
#' @param name A name for the rule set.
#' @param rules A data frame, one row per rule: `type`, `value`, `target` (a
#'   list column of named lists), `during` (a list column; `NULL` for no
#'   window) and `note`. Build it with [plan_constraints()] rather than by
#'   hand.
#' @return A `PlanConstraints` S7 object.
#' @seealso [plan_constraints()], [rules], [check_constraints()].
#' @export
PlanConstraints <- S7::new_class(
  "PlanConstraints",
  properties = list(
    id    = S7::new_property(S7::class_character,
                             default = quote(new_id("constraints"))),
    name  = S7::new_property(S7::class_character, default = ""),
    rules = S7::new_property(S7::class_data.frame,
                             default = quote(.rules_frame(list())))
  ),
  validator = function(self) {
    errs <- character(0)
    if (length(self@id) != 1 || is.na(self@id) || !nzchar(self@id)) {
      errs <- c(errs, "@id must be a single non-empty string.")
    }
    if (length(self@name) != 1 || is.na(self@name)) {
      errs <- c(errs, "@name must be a single string.")
    }
    want <- c("type", "value", "target", "during", "note")
    if (!identical(names(self@rules), want)) {
      return(c(errs, paste0("@rules must have the columns ",
                            paste(want, collapse = ", "),
                            "; build it with plan_constraints().")))
    }
    for (i in seq_len(nrow(self@rules))) {
      msg <- tryCatch({
        .check_rule(.rule_at(self@rules, i), paste0("rule ", i, ": "))
        NULL
      }, error = conditionMessage)
      errs <- c(errs, msg)
    }
    if (length(errs)) errs else NULL
  }
)

#' Build a set of plan rules
#'
#' Collects rules into a [PlanConstraints] object. Rules come either as a list
#' of rules, built with the [rule constructors][rules] or written by hand as
#' plain lists, or as a table -- the shape a rules sheet takes:
#'
#' - `type` and `value`, required;
#' - `from` and `to`, an optional window (both or neither);
#' - `note`, optional;
#' - any of the plan's line item columns, naming the rows a rule covers. A
#'   blank or `NA` means any value; a row naming none covers the whole plan.
#'
#' Either way every rule is checked where it is written, and stored in one
#' canonical form, so the same rules built either way are the same object.
#'
#' @param rules A list of rules, or a rules table as described above.
#' @param name A name for the rule set.
#' @param id Optional explicit id; generated when `NULL`. A scenario's
#'   `rationale$constraints_id` refers to it.
#' @return A [PlanConstraints].
#' @seealso [check_constraints()] to check a plan against them;
#'   [constraints_schema()] for the JSON Schema an agent's rules are checked
#'   against.
#' @examples
#' rules <- plan_constraints(name = "Q4 guardrails", rules = list(
#'   rule_min_share(0.4, target = list(channel = "Streaming")),
#'   rule_max_spend(320000, target = list(channel = "Programmatic"),
#'                  during = list(from = "2026-10-01", to = "2026-12-31")),
#'   rule_fixed_total(360000, target = list(partner = "Stream A"),
#'                    note = "upfront: total fixed, phasing free")
#' ))
#' rules
#'
#' # The same rules as a sheet would hold them
#' sheet <- data.frame(
#'   type    = c("min_share", "max_spend", "fixed_total"),
#'   value   = c(0.4, 320000, 360000),
#'   from    = c(NA, "2026-10-01", NA),
#'   to      = c(NA, "2026-12-31", NA),
#'   note    = c("", "", "upfront: total fixed, phasing free"),
#'   channel = c("Streaming", "Programmatic", NA),
#'   partner = c(NA, NA, "Stream A")
#' )
#' identical(plan_constraints(sheet, name = "Q4 guardrails")@rules, rules@rules)
#' @export
plan_constraints <- function(rules, name = "", id = NULL) {
  if (is.data.frame(rules)) {
    # Already the @rules shape (list columns), or a sheet to read.
    rules <- if (is.list(rules[["target"]])) {
      lapply(seq_len(nrow(rules)), function(i) .rule_at(rules, i))
    } else {
      .rules_from_table(rules)
    }
  }
  if (!is.list(rules)) {
    stop("`rules` must be a list of rules or a rules table.", call. = FALSE)
  }
  canonical <- lapply(seq_along(rules), function(i) {
    rule <- Filter(Negate(is.null), rules[[i]])
    .check_rule(rule, where = paste0("rule ", i, ": "))
    .canonical_rule(rule)
  })
  PlanConstraints(id = id %||% new_id("constraints"), name = name,
                  rules = .rules_frame(canonical))
}

S7::method(print, PlanConstraints) <- function(x, ...) {
  n <- nrow(x@rules)
  cat("<PlanConstraints> ", if (nzchar(x@name)) x@name else short_id(x@id),
      "  (", n, " rule", if (n == 1L) "" else "s", ")\n", sep = "")
  for (i in seq_len(n)) cat("  ", .rule_text(.rule_at(x@rules, i)), "\n", sep = "")
  invisible(x)
}

# A rule in words: "min_share 0.4 on channel Streaming, 2026-10-01..2026-12-31
# -- note".
.rule_text <- function(rule) {
  measure <- .rule_types[[rule$type]]$measure
  value <- if (measure %in% c("share", "change_pct")) format(rule$value) else
    .money(rule$value)
  paste0(rule$type, " ", value, " on ", .target_label(rule$target),
         if (!is.null(rule$during)) paste0(", ", .window_text(rule$during)),
         if (nzchar(rule$note)) paste0(" -- ", rule$note))
}

# ---- rule constructors -----------------------------------------------------------

.new_rule <- function(type, value, target, during, note) {
  rule <- Filter(Negate(is.null), list(type = type, value = value,
                                        target = target, during = during,
                                        note = note))
  .check_rule(rule, where = paste0("rule_", type, "(): "))
  rule
}

#' Build a plan rule
#'
#' Constructors for the rules a [PlanConstraints] holds, in the pattern of the
#' [op constructors][ops]: each returns the plain list you could write by hand
#' -- `rule_min_share(0.4, target = list(channel = "Streaming"))` is
#' `list(type = "min_share", value = 0.4, target = list(channel = "Streaming"))`
#' -- and checks it where it is written.
#'
#' Every rule measures the spend on its `target` rows inside its `during`
#' window, day by day (as [check_budget()] does), and compares it with
#' `value`:
#'
#' \describe{
#'   \item{`rule_min_spend()`, `rule_max_spend()`}{That spend is at least, or
#'     at most, `value`.}
#'   \item{`rule_fixed_total()`}{That spend is exactly `value` -- a commitment
#'     on a line's or a flight's total that leaves its phasing free. (A
#'     commitment month by month is a spend bound on the plan instead; see
#'     [bound_cols()].)}
#'   \item{`rule_min_share()`, `rule_max_share()`}{That spend, as a share of
#'     the whole plan's spend in the same window, is at least or at most
#'     `value`, from 0 to 1.}
#'   \item{`rule_max_change_abs()`, `rule_max_change_pct()`}{That spend moves
#'     by at most `value` -- an amount, or a fraction of the reference's --
#'     from a reference plan, normally the parent or the current approved
#'     plan. [check_constraints()] needs the reference for these.}
#' }
#'
#' @param value The rule's limit: an amount of money, or a share or fraction
#'   from 0 to 1 for the share rules (`max_change_pct` may exceed 1).
#' @param target Optional named list of line item column = value(s), as in an
#'   op; omit for the whole plan. Rules measure whole days, so time is given
#'   by `during`, not by naming the time column.
#' @param during Optional `list(from =, to =)` of dates.
#' @param note Optional text saying why the rule exists.
#' @return A plain list: one rule, for [plan_constraints()].
#' @seealso [plan_constraints()], [check_constraints()].
#' @examples
#' rule_min_share(0.4, target = list(channel = "Streaming"))
#' rule_max_change_pct(0.25, target = list(channel = "Online Video"),
#'                     note = "no channel swings more than 25%")
#' @name rules
NULL

#' @rdname rules
#' @export
rule_min_spend <- function(value, target = NULL, during = NULL, note = NULL) {
  .new_rule("min_spend", value, target, during, note)
}

#' @rdname rules
#' @export
rule_max_spend <- function(value, target = NULL, during = NULL, note = NULL) {
  .new_rule("max_spend", value, target, during, note)
}

#' @rdname rules
#' @export
rule_fixed_total <- function(value, target = NULL, during = NULL, note = NULL) {
  .new_rule("fixed_total", value, target, during, note)
}

#' @rdname rules
#' @export
rule_min_share <- function(value, target = NULL, during = NULL, note = NULL) {
  .new_rule("min_share", value, target, during, note)
}

#' @rdname rules
#' @export
rule_max_share <- function(value, target = NULL, during = NULL, note = NULL) {
  .new_rule("max_share", value, target, during, note)
}

#' @rdname rules
#' @export
rule_max_change_abs <- function(value, target = NULL, during = NULL,
                                note = NULL) {
  .new_rule("max_change_abs", value, target, during, note)
}

#' @rdname rules
#' @export
rule_max_change_pct <- function(value, target = NULL, during = NULL,
                                note = NULL) {
  .new_rule("max_change_pct", value, target, during, note)
}

# ---- checking a plan -------------------------------------------------------------

#' Check a plan against its rules
#'
#' Measures each rule of a [PlanConstraints] on a plan and reports how it
#' stands: the `actual` measure, the rule's `limit`, the `slack` between them,
#' and whether the rule is `ok`. Rules are measured day by day, through
#' [calendarize()], so a rule's window may cut a week or a month anywhere.
#'
#' Like [check_budget()], this **warns rather than errors** on a violation:
#' the plan and its rules are each valid, and an agent or a planner checking a
#' proposal needs to see what it breaks, not be refused. It does error on a
#' rule it cannot measure -- a target naming a value the plan does not have,
#' or a change rule with no `reference` to change from.
#'
#' Rules about groups of rows live here; rules about single rows are the
#' plan's own spend bounds, which the plan's validator already guarantees.
#' They are reported anyway, as one `row_bounds` row, so the report is
#' complete.
#'
#' @param plan A [MediaPlan].
#' @param constraints A [PlanConstraints].
#' @param reference The plan change rules are measured against -- normally
#'   the plan's parent, or the current approved plan ([current_approved()]).
#'   Required when `constraints` has a `max_change_*` rule.
#' @return A data frame, one row per rule:
#'   \describe{
#'     \item{`rule`}{Its position in `constraints`; `NA` for `row_bounds`.}
#'     \item{`type`, `target`, `window`, `note`}{The rule, in words.}
#'     \item{`limit`}{The rule's value.}
#'     \item{`actual`}{What the plan measures: the target's spend, its share
#'       of the plan, or how far it moved from the reference.}
#'     \item{`slack`}{How far inside its limit the rule is; negative is how
#'       far outside. Always 0 or less for `fixed_total`.}
#'     \item{`ok`}{Whether the rule holds.}
#'   }
#' @seealso [plan_constraints()]; [describe_plan()], which summarises the
#'   check when given `constraints`.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(month = as.Date("2026-10-01"),
#'              channel = c("Streaming", "Programmatic", "Online Video"),
#'              planned_spend = c(500, 300, 200)),
#'   grain = "channel", time = "month", name = "Q4"
#' )
#' rules <- plan_constraints(list(
#'   rule_min_share(0.4, target = list(channel = "Streaming")),
#'   rule_max_change_pct(0.25, target = list(channel = "Online Video"))
#' ), name = "guardrails")
#'
#' check_constraints(plan, rules, reference = plan)
#'
#' moved <- build_scenario(plan, name = "more video", edits = op_transfer(
#'   150, from = list(channel = "Streaming"), to = list(channel = "Online Video")))
#' check_constraints(moved, rules, reference = plan)
#' @export
check_constraints <- function(plan, constraints, reference = NULL) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!S7::S7_inherits(constraints, PlanConstraints)) {
    stop("`constraints` must be a PlanConstraints; build one with ",
         "plan_constraints().", call. = FALSE)
  }
  rules <- constraints@rules
  .check_reference(rules, plan, reference)

  # Both plans by line item and day, so every window measures the same way.
  daily     <- calendarize(plan, "day")
  ref_daily <- if (!is.null(reference)) calendarize(reference, "day")

  out <- do.call(rbind, lapply(seq_len(nrow(rules)), function(i) {
    .check_one_rule(.rule_at(rules, i), i, plan, reference, daily, ref_daily)
  }))
  if (any(bound_cols() %in% names(plan@data))) {
    out <- rbind(out, .row_bounds_report(plan@data))
  }
  if (is.null(out)) out <- .empty_constraint_report()
  rownames(out) <- NULL

  if (!all(out$ok)) .warn_violations(out)
  out
}

# A change rule needs a plan to change from, at the same line item grain.
.check_reference <- function(rules, plan, reference) {
  needs <- vapply(rules$type, .needs_reference, logical(1))
  if (any(needs) && is.null(reference)) {
    stop("`reference` is required: rule(s) ",
         paste(which(needs), collapse = ", "), " measure change against ",
         "another plan -- normally the parent, or the current approved plan.",
         call. = FALSE)
  }
  if (is.null(reference)) return(invisible(NULL))
  if (!S7::S7_inherits(reference, MediaPlan)) {
    stop("`reference` must be a MediaPlan.", call. = FALSE)
  }
  if (!identical(line_item_grain(reference), line_item_grain(plan))) {
    stop("`reference` must have the plan's line item columns (",
         paste(line_item_grain(plan), collapse = ", "), "); it has ",
         paste(line_item_grain(reference), collapse = ", "), ".", call. = FALSE)
  }
}

# Measure one rule on the plan, and say how it stands.
.check_one_rule <- function(rule, i, plan, reference, daily, ref_daily) {
  where <- paste0("rule ", i, ": ")
  .check_rule_target(rule$target, plan, reference, where)
  spec <- .rule_types[[rule$type]]

  spend <- .spend_on(daily, rule$target, rule$during)
  actual <- switch(
    spec$measure,
    spend      = spend,
    share      = .ratio(spend, .spend_on(daily, list(), rule$during)),
    change_abs = abs(spend - .spend_on(ref_daily, rule$target, rule$during)),
    change_pct = {
      before <- .spend_on(ref_daily, rule$target, rule$during)
      if (before > 0) abs(spend - before) / before else
        if (spend > 0) Inf else 0
    }
  )

  # Money is met to the cent; a share or a fraction exactly.
  tol <- if (spec$measure %in% c("spend", "change_abs")) .cent_tol else 1e-9
  slack <- switch(spec$bound,
                  min   = actual - rule$value,
                  max   = rule$value - actual,
                  equal = -abs(actual - rule$value))
  digits <- if (spec$measure %in% c("spend", "change_abs")) 2 else 4
  ok <- slack >= -tol
  # -abs(0) is negative zero, which JSON writes as -0.
  slack <- round(slack, digits) + 0

  data.frame(
    rule   = i,
    type   = rule$type,
    target = .target_label(rule$target),
    window = if (is.null(rule$during)) NA_character_ else
      .window_text(rule$during),
    limit  = rule$value,
    actual = round(actual, digits),
    slack  = slack,
    ok     = ok,
    note   = rule$note,
    stringsAsFactors = FALSE
  )
}

# A rule's target is checked against the plan the way an op's is: a column
# the line items do not have, or a value no row holds, is an error naming the
# alternatives. A value only the reference holds -- a line the plan dropped --
# is fair game for a change rule, so the reference's rows count too.
.check_rule_target <- function(target, plan, reference, where) {
  if (!length(target)) return(invisible(NULL))
  lg <- line_item_grain(plan)
  rows <- plan@data[, lg, drop = FALSE]
  if (!is.null(reference)) rows <- rbind(rows, reference@data[, lg, drop = FALSE])
  .match_target(rows, lg, target, where)
  invisible(NULL)
}

# The spend on a target's rows inside a window, from a daily calendar.
.spend_on <- function(daily, target, during) {
  keep <- rep(TRUE, nrow(daily))
  for (col in names(target)) {
    keep <- keep & as.character(daily[[col]]) %in% target[[col]]
  }
  if (!is.null(during)) {
    keep <- keep & daily$day >= as.Date(during$from) &
      daily$day <= as.Date(during$to)
  }
  sum(daily$planned_spend[keep])
}

.ratio <- function(part, whole) if (whole > 0) part / whole else 0

# The per-row bounds, reported as one rule so the report is complete. The
# validator holds them, so this is a backstop that should always be ok.
.row_bounds_report <- function(d) {
  outside <- sum(d$planned_spend < .lower_bounds(d) - .cent_tol |
                   d$planned_spend > .upper_bounds(d) + .cent_tol)
  data.frame(rule = NA_integer_, type = "row_bounds", target = "(every row)",
             window = NA_character_, limit = 0, actual = outside,
             slack = -outside, ok = outside == 0,
             note = "rows outside their own min_spend / max_spend",
             stringsAsFactors = FALSE)
}

.empty_constraint_report <- function() {
  data.frame(rule = integer(0), type = character(0), target = character(0),
             window = character(0), limit = numeric(0), actual = numeric(0),
             slack = numeric(0), ok = logical(0), note = character(0),
             stringsAsFactors = FALSE)
}

.warn_violations <- function(report) {
  bad <- report[!report$ok, , drop = FALSE]
  lines <- paste0(bad$type, " ", bad$limit, " on ", bad$target,
                  ifelse(is.na(bad$window), "", paste0(", ", bad$window)),
                  ": actual ", bad$actual, " (slack ", bad$slack, ")")
  warning(nrow(bad), " of ", nrow(report), " rule(s) violated: ",
          .first_few(lines, 5), ".", call. = FALSE)
}

# ---- JSON Schema ---------------------------------------------------------------

#' JSON Schema for the rules an agent may write
#'
#' Describes a list of plan rules -- what [plan_constraints()] takes -- as a
#' JSON Schema, draft 2020-12, in the way [plan_ops_schema()] describes ops:
#' an array of rules, each exactly one of the rule types, with that type's
#' value range (a share is 0 to 1) and fields. With a plan, a rule's `target`
#' may name only the plan's line item columns, each limited to the values
#' present.
#'
#' @param plan Optional [MediaPlan] to narrow the schema to.
#' @param as_json `FALSE` (default) returns the schema as a nested list;
#'   `TRUE` returns it as JSON text.
#' @return A nested list, or a `json` string when `as_json = TRUE`.
#' @seealso [rules] for the constructors that build each shape.
#' @examples
#' schema <- constraints_schema()
#' vapply(schema$items$oneOf, function(rule) rule$title, character(1))
#' @export
constraints_schema <- function(plan = NULL, as_json = FALSE) {
  if (!is.null(plan) && !S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan, or NULL for the plan-free schema.",
         call. = FALSE)
  }
  schema <- list(
    `$schema`   = "https://json-schema.org/draft/2020-12/schema",
    title       = "mediaplanr plan rules",
    description = paste(
      "Rules a plan must keep. Each measures the spend on its target rows",
      "inside its window, day by day, and compares it with its value."
    ),
    type  = "array",
    items = list(oneOf = lapply(names(.rule_types), .rule_schema, plan = plan))
  )
  if (!as_json) return(schema)
  jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE)
}

# The schema for one rule type: its type as a constant, its value's range,
# and the fields every rule shares. Arrays are I()'d, as in plan_ops_schema().
.rule_schema <- function(type, plan = NULL) {
  spec  <- .rule_types[[type]]
  value <- list(type = "number", minimum = spec$min)
  if (is.finite(spec$max)) value$maximum <- spec$max
  date  <- list(type = "string", pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
  target <- if (is.null(plan)) .target_schema() else
    .target_schema(plan, cols = line_item_grain(plan))

  list(
    title       = type,
    description = .squish(spec$description),
    type        = "object",
    properties  = list(
      type   = list(const = type),
      value  = value,
      target = target,
      during = list(type = "object",
                    properties = list(from = date, to = date),
                    required = I(c("from", "to")),
                    additionalProperties = FALSE),
      note   = list(type = "string")
    ),
    required             = I(c("type", "value")),
    additionalProperties = FALSE
  )
}
