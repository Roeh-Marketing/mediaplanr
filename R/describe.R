# describe_plan(): the agent's view of a plan.
#
# An agent working on a plan needs to know what is in it before it proposes an
# edit -- what it spends, on what, when, what cannot move, and what an op may
# name -- and it needs that in a form that fits in its context however big the
# plan is. So every section is a summary with a fixed cap: the top values by
# spend and a count of the rest, never the full table.
#
# Every number is derived from @data on the call, never stored, and each one
# reconciles to it: the per-column breakdowns, the commitments and the months
# each add back up to the total.
#
# Later phases append the facts they add to a plan (approval, spend basis,
# budget, model coverage, constraints) as sections here.

#' A compact description of a plan, for an agent's context
#'
#' Summarises a [MediaPlan] as a plain named list an agent can read before it
#' proposes an edit: what the plan is, how it is keyed, what it spends and on
#' what, what cannot move, what it buys, when it spends, and the values an op
#' may target. Every section is capped -- the `top_n` values by spend, plus
#' a count and total for the rest -- so the description stays the same size
#' whether the plan has fifty rows or fifty thousand.
#'
#' Everything is derived from the plan on the call, and the numbers reconcile
#' to `@data`: each column's breakdown, the commitments and the months all add
#' up to the total. Money is rounded to the cent, shares to four places, and
#' dates are ISO strings on the plan's clock, so the list serializes to JSON as
#' it stands.
#'
#' @section Sections:
#' \describe{
#'   \item{`identity`}{`name`, `nickname`, `id` and `parent_id` (short ids),
#'     `status`, `approved_on`, `objective`, the rationale's `author`, and
#'     `edits` -- the ops
#'     that derived it from its parent, in order (`"allocation"` for an
#'     allocation edit; empty for a root).}
#'   \item{`shape`}{`grain` (coarsest first, time last), `time_col`,
#'     `time_basis`, `tz`, the flight window, `n_line_items`, `n_rows`,
#'     `is_topline` and the `subplan_cells` a subplan owns.}
#'   \item{`money`}{`total`, and `spend_by` each line item column: its
#'     `top` values (`value`, `spend`, `share`) and an `other` bucket
#'     (`n_values`, `spend`).}
#'   \item{`commitments`}{Spend that cannot move, from the spend bounds
#'     ([bound_cols()]): `committed` (rows whose min and max equal their
#'     spend), `floor_locked` (the floors under rows with a floor),
#'     `flexible` (rows with no floor), `headroom` (all spend an edit could
#'     take out: the flexible spend plus what sits above floors), and
#'     `n_bounded_line_items`. A plan with no bounds is all headroom.}
#'   \item{`units`}{One row per unit type: `planned_units`, the
#'     `planned_spend` behind them, and the blended `rate` (a CPM for
#'     impressions).}
#'   \item{`time`}{Spend by calendar month, via [calendarize()].}
#'   \item{`targetable`}{What an op's `target` may name: for each line item
#'     column, its `top` values by spend and `n_more`; for the time column,
#'     the `first` and `last` value and how many there are. The full lists
#'     are in [plan_ops_schema()] for the plan.}
#' }
#'
#' @param plan A [MediaPlan].
#' @param top_n How many values to list for each column before the rest are
#'   summarised. A whole number, 1 or more.
#' @param as_json `FALSE` (default) returns the nested list; `TRUE` returns it
#'   as JSON text.
#' @return A named list with the sections above, or a `json` string when
#'   `as_json = TRUE`. Lists that can hold several values (`grain`, `edits`,
#'   `subplan_cells`, `top` values) stay JSON arrays even with one element.
#' @seealso [plan_ops_schema()] for the full contract an agent's ops are
#'   checked against; [line_item_summary()] for the uncapped roster.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(month = rep(as.Date(c("2026-10-01", "2026-11-01")), each = 3),
#'              channel = c("Streaming", "Search", "Social"),
#'              planned_spend = c(60000, 20000, 10000, 40000, 20000, 10000),
#'              min_spend = c(60000, 15000, NA, 40000, 15000, NA),
#'              max_spend = c(60000, NA, NA, 40000, NA, NA)),
#'   grain = "channel", time = "month", name = "Q4"
#' )
#' d <- describe_plan(plan, top_n = 2)
#' d$money$spend_by$channel
#' d$commitments
#'
#' cat(describe_plan(plan, as_json = TRUE))
#' @export
describe_plan <- function(plan, top_n = 10, as_json = FALSE) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!.is_single_number(top_n) || top_n < 1 || top_n != round(top_n)) {
    stop("`top_n` must be a single whole number, 1 or more.", call. = FALSE)
  }

  out <- list(
    identity    = .describe_identity(plan),
    shape       = .describe_shape(plan),
    money       = .describe_money(plan, top_n),
    commitments = .describe_commitments(plan),
    units       = .describe_units(plan),
    time        = .describe_time(plan),
    targetable  = .describe_targetable(plan, top_n)
  )
  if (!as_json) return(out)
  jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE, dataframe = "rows",
                   na = "null", digits = NA)
}

# ---- the sections ------------------------------------------------------------

# Arrays are wrapped in I() so that toJSON(auto_unbox = TRUE) keeps a
# one-element one an array, as plan_ops_schema() does.

.describe_identity <- function(plan) {
  edits <- plan@edits
  ops <- if (!length(edits)) {
    character(0)
  } else if (identical(edits$form, "allocation")) {
    "allocation"
  } else {
    vapply(edits$ops, function(op) .op_key(op), character(1))
  }
  has_parent <- length(plan@parent_id) && nzchar(plan@parent_id[1])

  list(
    name      = plan@name,
    nickname  = plan@nickname,
    id        = short_id(plan@id),
    parent_id = if (has_parent) short_id(plan@parent_id) else NA_character_,
    status    = plan@status,
    approved_on = if (length(plan@approved_on)) format(plan@approved_on) else
      NA_character_,
    objective = plan@objective,
    author    = plan@rationale[["author"]] %||% NA_character_,
    edits     = I(ops)
  )
}

.describe_shape <- function(plan) {
  d <- plan@data
  list(
    grain         = I(plan@grain),
    time_col      = plan@time_col,
    time_basis    = plan@time_basis,
    tz            = plan@tz,
    flight_start  = .canonical_time(plan@flight_start, plan),
    flight_end    = .canonical_time(plan@flight_end, plan),
    n_line_items  = length(unique(line_item(d, line_item_grain(plan)))),
    n_rows        = nrow(d),
    is_topline    = is_topline(plan),
    subplan_cells = I(as.character(names(plan@subplans)))
  )
}

.describe_money <- function(plan, top_n) {
  d     <- plan@data
  total <- sum(d[["planned_spend"]])
  lg    <- line_item_grain(plan)
  spend_by <- lapply(lg, function(col) {
    .top_by_spend(d[[col]], d[["planned_spend"]], top_n, total)
  })
  names(spend_by) <- lg
  list(total = round(total, 2), spend_by = spend_by)
}

# One column's values ranked by the spend on them: the first `top_n` with
# their spend and share of `total`, and the rest summed into `other`. Ties are
# broken by value, so the order is stable from call to call.
.top_by_spend <- function(values, spend, top_n, total) {
  by  <- tapply(spend, as.character(values), sum)
  by  <- by[order(-by, names(by))]
  top <- utils::head(by, top_n)
  rest <- by[-seq_along(top)]
  share <- if (total > 0) top / total else rep(0, length(top))
  list(
    top = data.frame(value = names(top), spend = round(as.numeric(top), 2),
                     share = round(as.numeric(share), 4),
                     stringsAsFactors = FALSE),
    other = list(n_values = length(rest), spend = round(sum(rest), 2))
  )
}

# What of the plan's spend is held by its bounds, from the derived label on
# each row (see .commitment()). Every row's spend lands in exactly one of
# committed, floor_locked or headroom, so the three add up to the total.
.describe_commitments <- function(plan) {
  d     <- plan@data
  spend  <- d[["planned_spend"]]
  floors <- .lower_bounds(d)
  label  <- .commitment(d)

  committed    <- sum(spend[label == "committed"])
  floor_locked <- sum(floors[label == "floor"])
  bounded_items <- unique(line_item(d, line_item_grain(plan))[label != "flexible"])

  list(
    committed            = round(committed, 2),
    floor_locked         = round(floor_locked, 2),
    flexible             = round(sum(spend[label %in% c("flexible", "capped")]), 2),
    headroom             = round(sum(spend) - committed - floor_locked, 2),
    n_bounded_line_items = length(bounded_items)
  )
}

# Units add up only within one unit type, so one row per type, over the rows
# that record units. The blended rate is the spend behind those units at the
# type's quoting basis -- a CPM for impressions.
.describe_units <- function(plan) {
  d <- plan@data
  empty <- data.frame(unit_type = character(0), planned_units = numeric(0),
                      planned_spend = numeric(0), rate = numeric(0))
  if (!all(c("unit_type", "planned_units") %in% names(d))) return(empty)

  has_units <- !is.na(d[["unit_type"]]) & !is.na(d[["planned_units"]])
  if (!any(has_units)) return(empty)
  d <- d[has_units, , drop = FALSE]

  types <- sort(unique(as.character(d[["unit_type"]])))
  units <- vapply(types, function(t) sum(d$planned_units[d$unit_type == t]),
                  numeric(1))
  spend <- vapply(types, function(t) sum(d$planned_spend[d$unit_type == t]),
                  numeric(1))
  rate  <- ifelse(units > 0, spend * .rate_per(types) / units, NA_real_)
  data.frame(unit_type = types, planned_units = round(unname(units), 2),
             planned_spend = round(unname(spend), 2),
             rate = round(unname(rate), 4), stringsAsFactors = FALSE)
}

# Spend by calendar month, whatever the plan is keyed by.
.describe_time <- function(plan) {
  cal <- calendarize(plan, "month")
  by  <- tapply(cal[["planned_spend"]], format(cal[["month"]], "%Y-%m"), sum)
  data.frame(month = names(by), spend = round(as.numeric(by), 2),
             stringsAsFactors = FALSE)
}

# What an op's target may name. Line item columns: their values by spend, the
# same order as money$spend_by, capped. The time column: its range and count,
# as text exactly as a target matches it -- its values are regular enough that
# the range says where they are.
.describe_targetable <- function(plan, top_n) {
  d <- plan@data
  lg <- line_item_grain(plan)
  values <- lapply(lg, function(col) {
    ranked <- .top_by_spend(d[[col]], d[["planned_spend"]], top_n,
                            sum(d[["planned_spend"]]))
    list(top = I(ranked$top$value), n_more = ranked$other$n_values)
  })
  names(values) <- lg

  periods <- sort(unique(d[[plan@time_col]]))
  as_text <- as.character(periods)
  list(
    values  = values,
    periods = list(
      column   = plan@time_col,
      first    = if (length(as_text)) as_text[1] else NA_character_,
      last     = if (length(as_text)) as_text[length(as_text)] else NA_character_,
      n_values = length(as_text)
    )
  )
}
