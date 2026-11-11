# Edit ops: the registry, the constructors, and the JSON Schema.
#
# An op is a plain list -- list(scale = 1.2, target = list(channel = "TV")) --
# so an op written by hand, built by op_scale(), or parsed from an agent's JSON
# tool call is the same object. This file is the one description of which ops
# exist and which fields each takes. Everything else reads from it:
#
#   .apply_op()         which operation an op carries, and its allowed fields
#   op_*()              the constructors, which check an op before any plan
#   plan_ops_schema()   the JSON Schema an agent's edits are validated against
#
# Only what can be checked WITHOUT a plan lives here: types, lengths, the shape
# of a window, whether a date string parses. Whether a target exists in a plan,
# or a week is a week start, is checked in verbs.R when the op is applied.

# ---- The registry ------------------------------------------------------------

# One field of an op. `type` is one of:
#
#   "number"     a single number; `min` is an optional lower bound
#   "days"       a single whole number of days
#   "true"       the literal TRUE, for an op that carries no value (drop)
#   "target"     a named list of grain column = value(s)
#   "window"     list(from =, to =) of dates or moments
#   "line_item"  the new line item `add` introduces
#
# `description` is written for whoever composes the op -- often a model reading
# the JSON Schema -- so it says what the field means, not how it is stored.
.field <- function(type, description, required = FALSE, min = NULL) {
  list(type = type, description = description, required = required, min = min)
}

# The two ways an op selects rows. Most ops take both.
.target_field <- .field(
  "target",
  "Rows to act on: grain column = value, or an array of values. Names any
  subset of the grain; omit to match every row."
)
.during_field <- .field(
  "window",
  "Narrow to rows in market at any point in this window (overlap, not
  containment: a flight that is partly inside is matched whole)."
)

# One op: its family, a one-line description, and its fields. The field named
# after the op carries its value and is the only required one.
.op_spec <- function(key, family, description, ...) {
  fields <- list(...)
  fields[[key]]$required <- TRUE
  list(family = family, description = description, fields = fields)
}

# Every op the package knows. Two families: value ops change planned_spend on
# rows that already exist; structural ops change which rows there are.
.op_registry <- list(
  set = .op_spec(
    "set", "value", "Put this planned_spend on each matched row.",
    set    = .field("number", "Planned spend for each matched row.", min = 0),
    target = .target_field,
    during = .during_field
  ),
  scale = .op_spec(
    "scale", "value",
    "Multiply each matched row's planned_spend, e.g. 1.2 for +20%.",
    scale  = .field("number", "The multiplier.", min = 0),
    target = .target_field,
    during = .during_field
  ),
  delta = .op_spec(
    "delta", "value",
    "Move the matched rows' TOTAL by this amount, holding their mix.",
    delta  = .field("number", "Amount to add to the total; negative to cut."),
    target = .target_field,
    during = .during_field
  ),
  delta_each = .op_spec(
    "delta_each", "value", "Add this amount to EACH matched row.",
    delta_each = .field("number", "Amount per row; negative to cut."),
    target     = .target_field,
    during     = .during_field
  ),
  total = .op_spec(
    "total", "value",
    "Make the matched rows sum to this total, holding their mix.",
    total  = .field("number", "The new total planned_spend.", min = 0),
    target = .target_field,
    during = .during_field
  ),
  add = .op_spec(
    "add", "structural",
    "Introduce a line item the plan does not have, for one period or as a
    flight.",
    add = .field(
      "line_item",
      "The new line item: every line item column, planned_spend, and either
      the plan's time column or flight_start and flight_end."
    )
  ),
  drop = .op_spec(
    "drop", "structural",
    "Remove the matched rows entirely. Unlike setting them to 0, the line item
    is then not in the plan at all.",
    drop   = .field("true", "Always true; target and during choose the rows."),
    target = .target_field,
    during = .during_field
  ),
  shift = .op_spec(
    "shift", "structural",
    "Move the matched flights by a number of days, re-spreading each total
    across its new dates. Rows with no flight move their period instead.",
    shift  = .field("days", "Whole days; negative moves earlier."),
    target = .target_field,
    during = .during_field
  ),
  restage = .op_spec(
    "restage", "structural",
    "Move the matched flights to new in-market dates.",
    restage = .field("window", "The flights' new in-market window."),
    target  = .target_field,
    during  = .during_field
  )
)

.op_keys <- names(.op_registry)

# Every field name any op may carry. A list naming one of these is a single op;
# an unnamed list is a list of ops.
.op_field_names <- function() {
  unique(unlist(lapply(.op_registry, function(spec) names(spec$fields))))
}

# ---- Checking an op without a plan -------------------------------------------

# Which operation `op` carries. Exactly one registered key, or an error.
.op_key <- function(op, where = "") {
  present <- intersect(names(op), .op_keys)
  if (length(present) != 1L) {
    stop(where, "supply exactly one of ", paste(.op_keys, collapse = "/"),
         "; got ",
         if (!length(present)) "none" else paste(present, collapse = " + "),
         ".", call. = FALSE)
  }
  present
}

# Check every field of an op carrying `key` against the registry: no field the
# op does not take, required fields present, each the right type.
.check_op_fields <- function(op, key, where = "") {
  fields <- .op_registry[[key]]$fields

  # Asked often enough to deserve its own answer.
  if (key == "add" && !is.null(op[["target"]])) {
    stop(where, "`add` does not take a `target`: it names the line item to ",
         "create, which by definition is not in the plan yet.", call. = FALSE)
  }
  extra <- setdiff(names(op), names(fields))
  if (length(extra)) {
    stop(where, "unknown field(s): ", paste(extra, collapse = ", "), ". `",
         key, "` takes: ", paste(names(fields), collapse = ", "), ".",
         call. = FALSE)
  }

  for (nm in names(fields)) {
    value <- op[[nm]]
    if (is.null(value)) {
      if (fields[[nm]]$required) {
        stop(where, "`", nm, "` is required.", call. = FALSE)
      }
      next
    }
    .check_field(value, fields[[nm]], nm, where)
  }
  invisible(op)
}

# Check one field's value against its spec. Errors; returns nothing useful.
.check_field <- function(x, spec, name, where = "") {
  switch(
    spec$type,
    number    = .check_number(x, name, spec$min, where),
    days      = .check_days(x, name, where),
    true      = .check_true(x, name, where),
    target    = .check_target_shape(x, name, where),
    window    = .check_window(x, name, where),
    line_item = .check_line_item(x, name, where),
    stop("internal: unknown field type '", spec$type, "'.", call. = FALSE)
  )
}

.is_single_number <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x)
}

.check_number <- function(x, name, min = NULL, where = "") {
  if (!.is_single_number(x)) {
    stop(where, "`", name, "` must be a single non-missing number.",
         call. = FALSE)
  }
  if (!is.null(min) && x < min) {
    stop(where, "`", name, "` must be ", min, " or more; got ", x, ".",
         call. = FALSE)
  }
}

.check_days <- function(x, name, where = "") {
  if (!.is_single_number(x) || x != round(x)) {
    stop(where, "`", name, "` must be a single whole number of days ",
         "(negative to move earlier).", call. = FALSE)
  }
}

.check_true <- function(x, name, where = "") {
  if (!isTRUE(x)) {
    stop(where, "`", name, "` must be TRUE. It takes no value: the rows are ",
         "named by `target` / `during`.", call. = FALSE)
  }
}

# A target's shape: a named list, each name carrying at least one value. Whether
# the names are grain columns and the values exist needs a plan; see
# .match_target().
.check_target_shape <- function(x, name = "target", where = "") {
  if (!length(x)) return(invisible(NULL))    # empty: matches every row
  if (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x)))) {
    stop(where, "`", name, "` must be a named list of grain column = value(s).",
         call. = FALSE)
  }
  empty <- names(x)[lengths(x) == 0L]
  if (length(empty)) {
    stop(where, "`", name, "` names no value for: ",
         paste(empty, collapse = ", "), ".", call. = FALSE)
  }
}

# A window's shape: list(from =, to =), both readable as a date or a moment,
# and not backwards. The plan reads them again in its own frame when the op is
# applied; this catches what is wrong regardless of the plan.
.check_window <- function(x, name, where = "") {
  if (!is.list(x) || !all(c("from", "to") %in% names(x))) {
    stop(where, "`", name, "` must be a list with `from` and `to` dates.",
         call. = FALSE)
  }
  extra <- setdiff(names(x), c("from", "to"))
  if (length(extra)) {
    stop(where, "`", name, "` takes only `from` and `to`; got also: ",
         paste(extra, collapse = ", "), ".", call. = FALSE)
  }
  .check_date_pair(x[["from"]], x[["to"]],
                   paste0(name, "$from"), paste0(name, "$to"),
                   label = paste0("`", name, "`"), where = where)
}

# Two op dates: each readable as a date or a moment, and the second not before
# the first. A date and a moment can only be ordered on the plan's clock, so
# only two of the same kind are compared here.
.check_date_pair <- function(from, to, from_what, to_what, label, where = "") {
  from <- .as_op_date(from, from_what, where)
  to   <- .as_op_date(to,   to_what,   where)
  if (identical(class(from), class(to)) && to < from) {
    stop(where, label, " ends (", format(to), ") before it starts (",
         format(from), ").", call. = FALSE)
  }
}

# The line item `add` introduces. Which columns it must name depends on the
# plan; that every value is single, the spend is valid, and a flight has both
# ends does not.
.check_line_item <- function(x, name, where = "") {
  if (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x)))) {
    stop(where, "`", name, "` must be a named list of the line item's columns ",
         "plus planned_spend, and either a week or flight_start/flight_end.",
         call. = FALSE)
  }
  if (!"planned_spend" %in% names(x)) {
    stop(where, "`", name, "` needs a `planned_spend`.", call. = FALSE)
  }
  spend <- x[["planned_spend"]]
  if (!.is_single_number(spend) || spend < 0) {
    stop(where, "`", name, "$planned_spend` must be a single non-negative ",
         "number.", call. = FALSE)
  }
  not_single <- names(x)[lengths(x) != 1L]
  if (length(not_single)) {
    stop(where, "every value in `", name, "` must be a single value; ",
         "not: ", paste(not_single, collapse = ", "), ".", call. = FALSE)
  }

  has_end <- c("flight_start", "flight_end") %in% names(x)
  if (sum(has_end) == 1L) {
    stop(where, "`", name, "` needs both flight_start and flight_end, or ",
         "neither.", call. = FALSE)
  }
  if (all(has_end)) {
    .check_date_pair(x[["flight_start"]], x[["flight_end"]],
                     paste0(name, "$flight_start"), paste0(name, "$flight_end"),
                     label = "the added flight", where = where)
  }
}

# ---- Constructors ------------------------------------------------------------

# Assemble an op from its fields in a fixed order, leaving out the ones not
# given, and check it. `key` names the op.
.new_op <- function(key, ...) {
  op <- Filter(Negate(is.null), list(...))
  .check_op_fields(op, key, where = paste0("op_", key, "(): "))
  op
}

#' Build an edit op
#'
#' Constructors for the operations [build_scenario()] applies. Each returns the
#' **plain list** you would otherwise write by hand, so a constructor-built op,
#' a hand-written one and one parsed from an agent's JSON are interchangeable:
#'
#' ```r
#' op_scale(1.2, target = list(channel = "TV"))
#' # is exactly
#' list(scale = 1.2, target = list(channel = "TV"))
#' ```
#'
#' What a constructor adds is **checking where the op is written**: a wrong
#' type, a backwards window or an unparseable date errors here, before any plan
#' is involved. Whether the target exists in a particular plan can only be
#' known when the op is applied, so [build_scenario()] checks that.
#'
#' Fields come out in a fixed order -- the operation, then `target`, then
#' `during` -- and fields not given are left out, so `identical()` holds
#' against a hand-written op in that order. [build_scenario()] does not care
#' about order.
#'
#' @section Operations:
#' See *Edit forms* in [build_scenario()] for the full rules.
#' \describe{
#'   \item{`op_set()`}{Put `value` on **each** matched row.}
#'   \item{`op_total()`}{Make the matched rows **sum** to `value`, holding
#'     their mix.}
#'   \item{`op_scale()`}{Multiply each matched row by `by`.}
#'   \item{`op_delta()`}{Move the matched rows' **sum** by `by`, holding their
#'     mix. The usual way to say "take 50k out of TV".}
#'   \item{`op_delta_each()`}{Add `by` to **each** matched row.}
#'   \item{`op_add()`}{Introduce a line item, named by its columns in `...`:
#'     every line item column, `planned_spend`, and either the plan's time
#'     column or `flight_start` and `flight_end`.}
#'   \item{`op_drop()`}{Remove the matched rows entirely.}
#'   \item{`op_shift()`}{Move the matched flights by `days`.}
#'   \item{`op_restage()`}{Move the matched flights to run `from`--`to`.}
#' }
#'
#' @param value A single number: planned spend per row (`op_set()`) or for the
#'   matched rows in total (`op_total()`). Not negative.
#' @param by A single number: the multiplier (`op_scale()`, not negative) or
#'   the amount to add (`op_delta()`, `op_delta_each()`; negative to cut).
#' @param days A whole number of days; negative moves earlier.
#' @param from,to The new in-market dates: `Date`, `POSIXct`, or ISO-8601
#'   strings.
#' @param target Optional named list of grain column = value(s) selecting the
#'   rows to act on, e.g. `list(channel = c("TV", "Radio"))`. Omit to match
#'   every row.
#' @param during Optional `list(from =, to =)` narrowing to rows in market at
#'   any point in that window.
#' @param ... For `op_add()`: the new line item's columns, named.
#' @return A plain list: one edit op, ready for the `edits` argument of
#'   [build_scenario()] on its own or in a list of ops.
#' @seealso [build_scenario()] to apply ops; [plan_ops_schema()] for the JSON
#'   Schema an agent's ops are checked against.
#' @examples
#' op_scale(1.2, target = list(channel = "Search"))
#'
#' identical(op_scale(1.2, target = list(channel = "Search")),
#'           list(scale = 1.2, target = list(channel = "Search")))
#'
#' op_add(channel = "Audio", week = "2026-07-06", planned_spend = 25)
#' op_restage("2026-08-03", "2026-08-30", target = list(channel = "TV"))
#'
#' # A malformed op errors where it is written.
#' try(op_shift(2.5))
#'
#' base <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search", "Social"),
#'              planned_spend = c(80, 40, 40)),
#'   grain = "channel", time = "week", name = "base"
#' )
#' build_scenario(base, name = "move 10 to Search", edits = list(
#'   op_delta(-10, target = list(channel = "TV")),
#'   op_delta(10,  target = list(channel = "Search"))
#' ))
#' @name ops
NULL

#' @rdname ops
#' @export
op_set <- function(value, target = NULL, during = NULL) {
  .new_op("set", set = value, target = target, during = during)
}

#' @rdname ops
#' @export
op_scale <- function(by, target = NULL, during = NULL) {
  .new_op("scale", scale = by, target = target, during = during)
}

#' @rdname ops
#' @export
op_delta <- function(by, target = NULL, during = NULL) {
  .new_op("delta", delta = by, target = target, during = during)
}

#' @rdname ops
#' @export
op_delta_each <- function(by, target = NULL, during = NULL) {
  .new_op("delta_each", delta_each = by, target = target, during = during)
}

#' @rdname ops
#' @export
op_total <- function(value, target = NULL, during = NULL) {
  .new_op("total", total = value, target = target, during = during)
}

#' @rdname ops
#' @export
op_add <- function(...) {
  .new_op("add", add = list(...))
}

#' @rdname ops
#' @export
op_drop <- function(target = NULL, during = NULL) {
  .new_op("drop", drop = TRUE, target = target, during = during)
}

#' @rdname ops
#' @export
op_shift <- function(days, target = NULL, during = NULL) {
  .new_op("shift", shift = days, target = target, during = during)
}

#' @rdname ops
#' @export
op_restage <- function(from, to, target = NULL, during = NULL) {
  .new_op("restage", restage = list(from = from, to = to),
          target = target, during = during)
}

# ---- JSON Schema -------------------------------------------------------------

#' JSON Schema for the edits an agent may send
#'
#' Describes the operations form of `edits` (see [build_scenario()]) as a JSON
#' Schema, draft 2020-12: an array of ops, each exactly one of the shapes the
#' [op constructors][ops] build. Hand it to a tool-calling model as the type of
#' its `edits` argument, and a malformed op is refused before R sees it.
#'
#' Without a plan, the schema says what any op may look like. With one, it
#' narrows to what is legal on **that** plan, which is the contract to give an
#' agent working on it:
#'
#' - `target` may name only the plan's grain columns, each limited to the
#'   values present.
#' - Dates take the shape the plan's time basis uses: `YYYY-MM-DD` for a plan
#'   keyed by day, week or month; a date or a date-time for a plan of moments.
#' - `add` must name every line item column, and may set only columns the plan
#'   has.
#'
#' The schema is the first check, not the only one. Some rules depend on the
#' plan's rows in ways a schema cannot state -- values that each exist but never
#' occur together, a shift that would collide with a row already planned -- and
#' [build_scenario()] still enforces them.
#'
#' To read an agent's ops in R, parse with
#' `jsonlite::fromJSON(x, simplifyVector = FALSE)`. Simplifying turns an array
#' of ops into a data frame, which [build_scenario()] would read as an
#' allocation rather than a list of operations.
#'
#' @param plan Optional [MediaPlan] to narrow the schema to.
#' @param as_json `FALSE` (default) returns the schema as a nested list; `TRUE`
#'   returns it as JSON text.
#' @return A nested list, or a `json` string when `as_json = TRUE`.
#' @seealso [ops] for the constructors that build each shape.
#' @examples
#' schema <- plan_ops_schema()
#' vapply(schema$items$oneOf, function(op) op$title, character(1))
#'
#' plan <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", time = "week", name = "base"
#' )
#' # On a plan, `target` lists the values an op may name.
#' scale <- plan_ops_schema(plan)$items$oneOf[[2]]
#' scale$properties$target$properties$channel
#'
#' cat(substr(plan_ops_schema(plan, as_json = TRUE), 1, 200))
#' @export
plan_ops_schema <- function(plan = NULL, as_json = FALSE) {
  if (!is.null(plan) && !S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan, or NULL for the plan-free schema.",
         call. = FALSE)
  }
  op_schemas <- lapply(.op_keys, .op_schema, plan = plan)

  schema <- list(
    `$schema`   = "https://json-schema.org/draft/2020-12/schema",
    title       = "mediaplanr edits",
    description = paste(
      "Edit operations applied in order to derive a scenario. Each op",
      "carries exactly one operation key."
    ),
    type     = "array",
    minItems = 1L,
    items    = list(oneOf = op_schemas)
  )
  if (!as_json) return(schema)
  jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE)
}

# Arrays in the schema are wrapped in I() so that toJSON(auto_unbox = TRUE)
# keeps a one-element `required` or `enum` as an array, as JSON Schema needs.

# The schema for one op: an object with that op's fields and no others.
.op_schema <- function(key, plan = NULL) {
  spec  <- .op_registry[[key]]
  props <- lapply(spec$fields, .field_schema, plan = plan)
  required <- names(spec$fields)[vapply(spec$fields, function(f) f$required,
                                        logical(1))]
  list(
    title                = key,
    description          = .squish(spec$description),
    type                 = "object",
    properties           = props,
    required             = I(required),
    additionalProperties = FALSE
  )
}

# The schema for one field, by its registry type.
.field_schema <- function(field, plan = NULL) {
  description <- .squish(field$description)
  out <- switch(
    field$type,
    number    = list(type = "number", minimum = field$min),
    days      = list(type = "integer"),
    true      = list(const = TRUE),
    target    = .target_schema(plan),
    window    = .window_schema(plan),
    line_item = .line_item_schema(plan)
  )
  # description first, and no NULL entries (an unset `minimum`).
  Filter(Negate(is.null), c(list(description = description), out))
}

# A target: grain column -> one value or an array of values. On a plan, only
# its grain columns, and only the values present -- compared as text, exactly
# as .match_target() compares them.
.target_schema <- function(plan = NULL) {
  if (is.null(plan)) {
    scalar <- list(type = I(c("string", "number")))
    return(list(
      type = "object",
      additionalProperties = list(anyOf = list(
        scalar,
        list(type = "array", items = scalar, minItems = 1L)
      ))
    ))
  }
  per_column <- lapply(plan@grain, function(col) {
    values <- I(as.character(grain_values(plan, col)))
    list(anyOf = list(
      list(enum = values),
      list(type = "array", items = list(enum = values), minItems = 1L)
    ))
  })
  names(per_column) <- plan@grain
  list(type = "object", properties = per_column, additionalProperties = FALSE)
}

.window_schema <- function(plan = NULL) {
  list(
    type                 = "object",
    properties           = list(from = .time_schema(plan),
                                to   = .time_schema(plan)),
    required             = I(c("from", "to")),
    additionalProperties = FALSE
  )
}

# A date, or a date and a time, as a string. A plan keyed by day, week or month
# reads only dates; a plan of moments, or no plan, reads either.
.time_schema <- function(plan = NULL) {
  date <- "[0-9]{4}-[0-9]{2}-[0-9]{2}"
  if (!is.null(plan) && plan@time_basis != "instant") {
    return(list(type = "string", pattern = paste0("^", date, "$"),
                description = "ISO 8601 date, YYYY-MM-DD."))
  }
  clock <- "([ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?Z?)?"
  list(type = "string", pattern = paste0("^", date, clock, "$"),
       description = paste("ISO 8601 date, or date and time",
                           "(YYYY-MM-DD HH:MM:SS) on the plan's clock."))
}

# The line item `add` introduces. On a plan: every line item column required,
# and the period given either by the time column or by both flight dates.
.line_item_schema <- function(plan = NULL) {
  spend   <- list(type = "number", minimum = 0)
  flights <- list(flight_start = .time_schema(plan),
                  flight_end   = .time_schema(plan))
  both_flight_dates <- list(flight_start = I("flight_end"),
                            flight_end   = I("flight_start"))

  if (is.null(plan)) {
    return(list(
      type                 = "object",
      properties           = c(list(planned_spend = spend), flights),
      required             = I("planned_spend"),
      dependentRequired    = both_flight_dates,
      additionalProperties = list(type = I(c("string", "number")))
    ))
  }

  li <- line_item_grain(plan)
  # Values here may be new to the plan -- that is what add is for -- so the
  # line item columns are not limited to the values present.
  li_props <- stats::setNames(
    rep(list(list(type = I(c("string", "number")))), length(li)), li)
  time_prop <- stats::setNames(list(.time_schema(plan)), plan@time_col)
  # Other columns the plan carries, such as unit_type or planned_rate, may be
  # set too; the flight bookkeeping columns are minted by add itself.
  others <- setdiff(names(plan@data),
                    c(plan@grain, "planned_spend", flight_cols()))
  other_props <- stats::setNames(
    rep(list(list(type = I(c("string", "number")))), length(others)), others)

  list(
    type       = "object",
    properties = c(li_props, time_prop, list(planned_spend = spend), flights,
                   other_props),
    required   = I(c(li, "planned_spend")),
    oneOf      = list(
      list(required = I(plan@time_col)),
      list(required = I(c("flight_start", "flight_end")))
    ),
    additionalProperties = FALSE
  )
}

# Registry descriptions are written across lines for reading in source; a
# schema wants them on one.
.squish <- function(x) gsub("\\s+", " ", trimws(x))
