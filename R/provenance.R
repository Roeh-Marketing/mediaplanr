# Provenance: what changed between a plan and its parent, and why.
#
# A scenario carries two records of its own derivation:
#
#   @edits      the edits build_scenario() applied, in a canonical form:
#                 list(form = "ops",        ops  = <list of ops>)
#                 list(form = "allocation", data = <grain columns + planned_spend>)
#   @rationale  why: who proposed it (author), toward what (goal), under which
#               constraints (constraints_id), with what predicted result
#               (forecast, supplied by the caller), and free notes.
#
# The canonical form is what makes @edits trustworthy. build_scenario() first
# turns whatever it was given into this record and then derives the scenario
# by replaying the record (see .replay() in verbs.R), so the record is, by
# construction, exactly what was applied. It is also plain JSON: dates and
# moments are strings on the plan's clock, numbers are doubles, target values
# are text -- so it survives a round trip unchanged and replays the same.

# ---- The edits record --------------------------------------------------------

# Turn `edits`, in any form build_scenario() accepts, into the canonical record.
# Checks the form and everything that needs no plan; what needs the plan's rows
# is checked when the record is replayed.
.record_edits <- function(plan, edits) {
  d <- plan@data
  g <- plan@grain

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
    rows <- .allocation_rows(d, g, line_item(edits, g))
    return(.allocation_record(plan, rows, edits[["planned_spend"]]))
  }

  if (is.numeric(edits) && !is.null(names(edits))) {
    rows <- .allocation_rows(d, g, names(edits))
    return(.allocation_record(plan, rows, unname(edits)))
  }

  if (is.list(edits)) {
    # One op, or a list of ops applied in order.
    ops <- if (any(names(edits) %in% .op_field_names())) list(edits) else edits
    if (!length(ops)) {
      stop("`edits` is an empty list; supply at least one operation.",
           call. = FALSE)
    }
    canonical <- lapply(seq_along(ops), function(i) {
      op <- ops[[i]]
      where <- paste0("edit op ", i, ": ")
      if (!is.list(op)) stop(where, "each op must be a list.", call. = FALSE)
      key <- .op_key(op, where)
      .check_op_fields(op, key, where)
      .canonical_op(op, key, plan)
    })
    return(list(form = "ops", ops = canonical))
  }

  stop("`edits` must be one of: a list of operations (target + ",
       paste(.op_keys, collapse = "/"), "), a data frame (grain columns + ",
       "planned_spend), or a named numeric vector keyed by line_item().",
       call. = FALSE)
}

# The plan rows an allocation names, by their line_item() keys at the full
# grain. Every key must be a row the plan has.
.allocation_rows <- function(d, grain, keys) {
  have <- line_item(d, grain)
  unknown <- setdiff(keys, have)
  if (length(unknown)) {
    stop("`edits` reference row(s) not in the plan: ",
         paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
  }
  match(keys, have)
}

# An allocation, recorded as given: the named rows' grain columns -- taken from
# the plan, so they are typed as the plan types them -- and the spend asked
# for. The time column is text, exactly as line_item() writes it, so the rows
# match again on replay.
.allocation_record <- function(plan, rows, spend) {
  data <- plan@data[rows, plan@grain, drop = FALSE]
  data[[plan@time_col]] <- as.character(data[[plan@time_col]])
  data[["planned_spend"]] <- as.numeric(spend)
  rownames(data) <- NULL
  list(form = "allocation", data = data)
}

# One op in canonical form: its fields in registry order (operation first),
# each in its canonical shape. Assumes .check_op_fields() has passed.
.canonical_op <- function(op, key, plan) {
  fields <- .op_registry[[key]]$fields
  out <- list()
  for (nm in intersect(names(fields), names(op))) {
    value <- .canonical_field(op[[nm]], fields[[nm]]$type, plan)
    # An empty target means "every row"; leaving it out says the same.
    if (identical(fields[[nm]]$type, "target") && !length(value)) next
    out[[nm]] <- value
  }
  out
}

.canonical_field <- function(x, type, plan) {
  switch(
    type,
    number    = as.numeric(x),
    days      = as.numeric(x),
    true      = TRUE,
    target    = .canonical_target(x),
    window    = list(from = .canonical_time(x[["from"]], plan),
                     to   = .canonical_time(x[["to"]], plan)),
    line_item = .canonical_line_item(x, plan),
    bounds    = .canonical_bounds(x)
  )
}

# Target values as text: .match_target() compares them as text, so this is
# the same selection, and it reads back from JSON unchanged. A JSON array
# arrives as a list, which unlist() makes the vector it stood for.
.canonical_target <- function(x) {
  if (!length(x)) return(list())
  lapply(x, function(v) as.character(unlist(v)))
}

# A date or a moment as a string: a date as YYYY-MM-DD, a moment as its wall
# clock on the plan's own clock. Ops read strings on the plan's clock, so the
# string names the same instant wherever it is replayed.
.canonical_time <- function(x, plan) {
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXct")) {
    return(format(x, "%Y-%m-%d %H:%M:%S", tz = plan@tz))
  }
  as.character(unlist(x))
}

# The line item `add` introduces. A new FLIGHT is given its flight_id here,
# before it is applied, so the record names the very flight that was created
# and a replay creates the same one.
.canonical_line_item <- function(x, plan) {
  time_fields <- c(plan@time_col, "flight_start", "flight_end")
  out <- lapply(names(x), function(nm) {
    v <- unlist(x[[nm]])
    if (nm %in% time_fields) return(.canonical_time(v, plan))
    if (nm %in% bound_cols() && .is_no_bound(v)) return(NA_real_)
    if (is.numeric(v)) return(as.numeric(v))
    if (is.factor(v)) return(as.character(v))
    v
  })
  names(out) <- names(x)
  is_flight <- all(c("flight_start", "flight_end") %in% names(out))
  if (is_flight && is.null(out[["flight_id"]])) out$flight_id <- .flight_ids(1L)
  out
}

# Rebound's bounds, `min` before `max`, "no bound" always as NA.
.canonical_bounds <- function(x) {
  x <- x[intersect(c("min", "max"), names(x))]
  lapply(x, function(v) if (.is_no_bound(v)) NA_real_ else as.numeric(v))
}

# The record read back from JSON. An allocation's `data` comes from the
# simplified parse, which makes it a data frame; ops come from the raw parse,
# where an array stays a list, and are made canonical again so that what was
# written and what is read are identical.
.edits_from_json <- function(simplified, raw, plan) {
  if (is.null(raw) || !length(raw)) return(list())
  form <- as.character(unlist(raw$form))
  if (identical(form, "allocation")) {
    data <- as.data.frame(simplified$data, stringsAsFactors = FALSE)
    data[[plan@time_col]] <- as.character(data[[plan@time_col]])
    data[["planned_spend"]] <- as.numeric(data[["planned_spend"]])
    return(list(form = "allocation", data = data))
  }
  ops <- lapply(raw$ops, function(op) .canonical_op(op, .op_key(op), plan))
  list(form = "ops", ops = ops)
}

# Validator support: @edits is empty, or a canonical record. A record says how
# a plan was derived from its parent, so a plan carrying one must name its
# parent.
.validate_edits <- function(edits, parent_id) {
  if (!length(edits)) return(character(0))
  form <- edits[["form"]]
  if (!length(parent_id) || !nzchar(parent_id[1])) {
    return("@edits is set but @parent_id is empty: edits record a derivation.")
  }
  if (identical(form, "ops")) {
    ops <- edits[["ops"]]
    one_key <- vapply(ops, function(op) {
      is.list(op) && length(intersect(names(op), .op_keys)) == 1L
    }, logical(1))
    if (!length(ops) || !all(one_key)) {
      return("@edits$ops must be a non-empty list of ops, each with one operation.")
    }
    return(character(0))
  }
  if (identical(form, "allocation")) {
    data <- edits[["data"]]
    if (!is.data.frame(data) || !"planned_spend" %in% names(data)) {
      return("@edits$data must be a data frame with a planned_spend column.")
    }
    return(character(0))
  }
  "@edits$form must be \"ops\" or \"allocation\"."
}

# ---- Rationale ---------------------------------------------------------------

.rationale_keys    <- c("author", "goal", "constraints_id", "forecast", "notes")
.rationale_authors <- c("human", "agent", "optimizer")

# A rationale as stored: strings as single strings, a forecast as a named list
# of numbers. JSON hands back integers and one-element arrays; this undoes
# both so a round trip is exact. Checking is the validator's job.
.as_rationale <- function(x) {
  if (is.null(x) || !length(x)) return(list())
  if (!is.list(x) || is.null(names(x))) {
    stop("`rationale` must be a named list: any of ",
         paste(.rationale_keys, collapse = ", "), ".", call. = FALSE)
  }
  for (nm in intersect(c("author", "goal", "constraints_id", "notes"),
                       names(x))) {
    x[[nm]] <- as.character(unlist(x[[nm]]))
  }
  if (!is.null(x[["forecast"]])) {
    # Integers become doubles; anything that is not a number is left as it
    # is, for the validator to name.
    x[["forecast"]] <- lapply(as.list(x[["forecast"]]), function(v) {
      v <- unlist(v)
      if (is.numeric(v)) as.numeric(v) else v
    })
  }
  x
}

.validate_rationale <- function(r) {
  if (!length(r)) return(character(0))
  if (is.null(names(r)) || any(!nzchar(names(r)))) {
    return("@rationale must be a named list.")
  }
  unknown <- setdiff(names(r), .rationale_keys)
  if (length(unknown)) {
    return(paste0("@rationale may hold only ",
                  paste(.rationale_keys, collapse = ", "), "; got: ",
                  paste(unknown, collapse = ", "), "."))
  }

  errs <- character(0)
  single_string <- function(v) is.character(v) && length(v) == 1L && !is.na(v)
  for (nm in intersect(c("author", "goal", "constraints_id", "notes"),
                       names(r))) {
    if (!single_string(r[[nm]])) {
      errs <- c(errs, paste0("@rationale$", nm, " must be a single string."))
    }
  }
  if (single_string(r[["author"]]) && !r[["author"]] %in% .rationale_authors) {
    errs <- c(errs, paste0("@rationale$author must be one of: ",
                           paste(.rationale_authors, collapse = ", "), "."))
  }
  f <- r[["forecast"]]
  if (!is.null(f)) {
    numbers <- is.list(f) && length(f) && !is.null(names(f)) &&
      all(nzchar(names(f))) &&
      all(vapply(f, .is_single_number, logical(1)))
    if (!numbers) {
      errs <- c(errs, paste0("@rationale$forecast must be a named list of ",
                             "single numbers, e.g. list(revenue = 1.2e6)."))
    }
  }
  errs
}

# ---- edit_log() --------------------------------------------------------------

#' The edits behind every scenario in a set, one row per op
#'
#' Reads each scenario's `@edits` -- the record [build_scenario()] keeps of
#' exactly what it applied -- and lays them out as a change log: one row per
#' op, scenarios in lineage order (roots first, then each generation), ops in
#' the order they were applied. Alongside each op it carries who proposed the
#' scenario (`@rationale$author`) and why (`@objective`).
#'
#' An allocation edit (a data frame or named vector of absolute spend,
#' typically an optimizer's output) is one row, `op = "allocation"`, whose
#' `amount` is the net change in the plan's total. A scenario with no recorded
#' edits -- a root, or a plan imported from a file -- contributes no rows.
#'
#' @param set A [ScenarioSet].
#' @return A data frame with one row per op:
#'   \describe{
#'     \item{`scenario`, `parent`}{The scenario's label, and its parent's
#'       (its short id when the parent is not in the set).}
#'     \item{`author`}{`@rationale$author`: `"human"`, `"agent"`,
#'       `"optimizer"`, or `NA` when unstated.}
#'     \item{`op`}{The operation, e.g. `"transfer"`, or `"allocation"`.}
#'     \item{`target`}{The rows the op acts on, as `column value` --
#'       `"partner DSP A"`. For a transfer, its source; for `add`, the line
#'       item it creates; `"(whole plan)"` when the op names no target.}
#'     \item{`to`}{A transfer's destination; `NA` for every other op.}
#'     \item{`amount`}{The money the op states: the amount a transfer moves,
#'       a `delta`, an added line's spend, an allocation's net change. `NA`
#'       for ops that state no amount (`scale`, `set`, `shift`, ...).}
#'     \item{`detail`}{The op's own value, in words: `"x1.2"`, `"+7 days"`,
#'       `"min 30,000"`.}
#'     \item{`window`}{The op's `during` window, or a transfer's per-side
#'       windows; `NA` when it has none.}
#'     \item{`objective`}{The scenario's `@objective`.}
#'   }
#' @seealso [build_scenario()] for how edits and rationale are recorded;
#'   [lineage()] for the derivation tree itself.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search", "Social"),
#'              planned_spend = c(80, 40, 40)),
#'   grain = "channel", time = "week", name = "base"
#' )
#' s1 <- build_scenario(
#'   base, name = "Search push", objective = "Lift search share",
#'   edits = op_transfer(20, from = list(channel = "TV"),
#'                       to = list(channel = "Search")),
#'   rationale = list(author = "agent", goal = "maximise conversions")
#' )
#' s2 <- build_scenario(
#'   s1, name = "Trim social", objective = "Budget cut",
#'   edits = list(op_scale(0.5, target = list(channel = "Social")),
#'                op_delta(-5, target = list(channel = "TV"))),
#'   rationale = list(author = "human")
#' )
#' edit_log(add_scenario(add_scenario(scenario_set(base), s1), s2))
#' @export
edit_log <- function(set) {
  if (!S7::S7_inherits(set, ScenarioSet)) {
    stop("`set` must be a ScenarioSet.", call. = FALSE)
  }
  lin <- lineage(set)
  in_lineage_order <- order(lin$depth, seq_len(nrow(lin)))

  rows <- list()
  for (i in in_lineage_order) {
    plan <- set@scenarios[[lin$scenario[i]]]
    record <- plan@edits
    if (!length(record)) next

    about <- list(
      scenario  = lin$scenario[i],
      parent    = if (is.na(lin$parent[i])) short_id(plan@parent_id) else
        lin$parent[i],
      author    = plan@rationale[["author"]] %||% NA_character_,
      objective = plan@objective
    )
    ops <- if (identical(record$form, "allocation")) {
      list(.allocation_log_row(record, lin$spend_vs_parent[i]))
    } else {
      lapply(record$ops, .op_log_row, plan = plan)
    }
    for (op_row in ops) rows[[length(rows) + 1L]] <- c(about, op_row)
  }

  columns <- c("scenario", "parent", "author", "op", "target", "to",
               "amount", "detail", "window", "objective")
  if (!length(rows)) {
    empty <- lapply(stats::setNames(columns, columns), function(nm) {
      if (identical(nm, "amount")) numeric(0) else character(0)
    })
    return(as.data.frame(empty, stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  out <- out[, columns]
  rownames(out) <- NULL
  out
}

# One row of the log for one canonical op: what it acts on, where money goes,
# how much, its value in words, and its window. `plan` is the scenario the op
# built, for the names of its columns.
.op_log_row <- function(op, plan) {
  key <- .op_key(op)
  v   <- op[[key]]
  target <- if (identical(key, "transfer")) op[["from"]] else op[["target"]]

  amount <- switch(key, transfer = v, delta = v,
                   add = v[["planned_spend"]], NA_real_)
  detail <- switch(
    key,
    set        = paste(.money(v), "per row"),
    scale      = paste0("x", v),
    delta_each = paste(.signed_money(v), "per row"),
    total      = paste("total", .money(v)),
    shift      = paste(if (v >= 0) paste0("+", v) else v, "days"),
    restage    = paste("to", .window_text(v)),
    rebound    = .bounds_text(v),
    add        = .add_text(v, plan),
    NA_character_
  )
  window <- if (identical(key, "transfer") &&
                !is.null(op[["from_during"]] %||% op[["to_during"]])) {
    paste0("from: ", .window_text(op[["from_during"]] %||% op[["during"]]),
           "; to: ", .window_text(op[["to_during"]] %||% op[["during"]]))
  } else if (!is.null(op[["during"]])) {
    .window_text(op[["during"]])
  } else {
    NA_character_
  }

  list(
    op     = key,
    target = if (identical(key, "add")) .added_label(v, plan) else
      .target_label(target),
    to     = if (identical(key, "transfer")) .target_label(op[["to"]]) else
      NA_character_,
    amount = as.numeric(amount),
    detail = detail,
    window = window
  )
}

.allocation_log_row <- function(record, net_change) {
  list(op = "allocation", target = NA_character_, to = NA_character_,
       amount = net_change,
       detail = paste(nrow(record$data), "row(s) set"),
       window = NA_character_)
}

# A target as "column value", in the style of .cell_label(): columns joined by
# " | ", then their values; several values for one column joined by "/".
# "partner | tactic DSP A | Regional", "channel TV/Search".
.target_label <- function(target) {
  if (!length(target)) return("(whole plan)")
  values <- vapply(target, function(v) paste(v, collapse = "/"), character(1))
  paste(paste(names(target), collapse = " | "),
        paste(values, collapse = " | "))
}

# The line item an `add` creates, labelled by its line item columns.
.added_label <- function(spec, plan) {
  .target_label(spec[intersect(line_item_grain(plan), names(spec))])
}

.window_text <- function(w) {
  if (is.null(w)) return("(all)")
  paste0(w[["from"]], "..", w[["to"]])
}

.signed_money <- function(x) paste0(if (x >= 0) "+" else "-", .money(abs(x)))

.bounds_text <- function(b) {
  word <- function(v) if (is.na(v)) "none" else .money(v)
  parts <- c(if ("min" %in% names(b)) paste("min", word(b[["min"]])),
             if ("max" %in% names(b)) paste("max", word(b[["max"]])))
  paste(parts, collapse = ", ")
}

# When an added line runs: its flight, or the one period it was added for.
.add_text <- function(spec, plan) {
  if (!is.null(spec[["flight_start"]])) {
    return(paste0("flight ", spec[["flight_start"]], "..", spec[["flight_end"]]))
  }
  paste(plan@time_col, spec[[plan@time_col]])
}
