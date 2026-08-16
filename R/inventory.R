# What is in the plan: the values present on each grain column, and the roster
# of line items. Both are derived from @data and both are read-only views -- no
# ids are minted and no MediaPlan is returned, because neither of these is a
# plan.

# Sorted distinct values, keeping the column's own type so a week column comes
# back as Dates. A factor yields the labels actually present, which is what a
# caller can target with; the unused levels are not in the plan.
.distinct <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  sort(unique(x))
}

#' The values present on a grain column
#'
#' Answers "which channels are in this plan?" — for whatever the user called
#' their channel column. The package never privileges a column name: `channel`
#' is simply a dimension someone chose to key on, and a plan may key on
#' `media_type` or `vehicle` instead. So this takes the column by name and
#' errors, listing the alternatives, when asked for one the plan does not have.
#'
#' The values are exactly what [build_scenario()]'s `target` accepts, so an
#' answer from here can be passed straight into an edit without translation.
#'
#' @param plan A [MediaPlan].
#' @param col Name of a single grain column. `NULL` (the default) returns a
#'   named list covering every grain column, including the week.
#' @return Sorted unique values for `col`, in the column's own type; or a named
#'   list of those vectors when `col` is `NULL`.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("TV", "TV", "Search"),
#'              partner = c("NBC", "ESPN", "Google"),
#'              planned_spend = c(30, 20, 50)),
#'   grain = c("channel", "partner"), name = "Q3 plan"
#' )
#'
#' grain_values(p, "channel")
#' grain_values(p)
#' @export
grain_values <- function(plan, col = NULL) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  g <- plan@grain

  if (is.null(col)) {
    return(stats::setNames(lapply(g, function(nm) .distinct(plan@data[[nm]])), g))
  }
  if (length(col) != 1 || !col %in% g) {
    stop("`col` must name a single grain column (", paste(g, collapse = ", "),
         "); got: ", paste(col, collapse = ", "), ".", call. = FALSE)
  }
  .distinct(plan@data[[col]])
}

# Aggregate a Date column by line item key, dropping NA within each item.
# tapply()/split() work in numeric, so the result is converted back.
.span_by_item <- function(dates, key, keys, f) {
  parts <- split(as.numeric(dates), key)[keys]
  vals <- vapply(parts, function(v) {
    v <- v[!is.na(v)]
    if (!length(v)) NA_real_ else f(v)
  }, numeric(1))
  as.Date(unname(vals), origin = "1970-01-01")
}

#' The roster of line items in a plan
#'
#' One row per line item — the time-free identity of what is being bought — with
#' its total planned spend, how many plan rows it occupies, and its own flight
#' window. Where [line_item()] returns the key for every row, this returns the
#' distinct roster.
#'
#' The grain columns come back as **columns**, not folded into the key, because
#' that is the shape both consumers need: a UI renders them as its left-hand
#' rows, and the `target` of an edit operation is column-and-value pairs. The
#' pasted key is included as `line_item` for the callers that want it.
#'
#' Ordered by planned spend descending, ties broken by key, so the head of the
#' table is the part of the plan worth looking at first and the order is stable
#' between calls.
#'
#' @param plan A [MediaPlan].
#' @return A data frame: the [line_item_grain()] columns, then `line_item` (the
#'   key), `planned_spend` (the item's total), `n_rows`, and — only when the
#'   plan has a time dimension — `flight_start` and `flight_end`. The date
#'   columns are absent rather than `NA` on a timeless plan.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week    = as.Date(c("2026-03-02", "2026-03-02", "2026-04-06")),
#'              channel = c("TV", "Search", "TV"),
#'              partner = c("NBC", "Google", "NBC"),
#'              planned_spend = c(30, 20, 35)),
#'   grain = c("channel", "partner", "week"), week = "week", name = "Q2 plan"
#' )
#'
#' line_item_summary(p)
#' @export
line_item_summary <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  d  <- plan@data
  lg <- line_item_grain(plan)
  if (!length(lg)) {
    stop("the plan's grain is only its week column, so it has no line items ",
         "to summarise.", call. = FALSE)
  }

  span <- .row_span(plan)

  if (!nrow(d)) {
    out <- d[0, lg, drop = FALSE]
    out[["line_item"]]     <- character(0)
    out[["planned_spend"]] <- numeric(0)
    out[["n_rows"]]        <- integer(0)
    if (!is.null(span)) {
      out[["flight_start"]] <- as.Date(character(0))
      out[["flight_end"]]   <- as.Date(character(0))
    }
    rownames(out) <- NULL
    return(out)
  }

  # Same idiom as roll_up(): keep the first row of each group for its dimension
  # values, then attach the aggregates in that order.
  k     <- line_item(d, lg)
  first <- !duplicated(k)
  keys  <- k[first]
  out   <- d[first, lg, drop = FALSE]

  out[["line_item"]]     <- keys
  out[["planned_spend"]] <- as.numeric(tapply(d[["planned_spend"]], k, sum)[keys])
  out[["n_rows"]]        <- as.integer(table(k)[keys])
  # A line item is bought on one unit type at one rate, so these aggregate
  # cleanly here even though they need care at a coarser grain.
  out <- .attach_units(out, .aggregate_units(d, k, keys))

  if (!is.null(span)) {
    out[["flight_start"]] <- .span_by_item(span$start, k, keys, min)
    out[["flight_end"]]   <- .span_by_item(span$end,   k, keys, max)
  }

  out <- out[order(-out[["planned_spend"]], out[["line_item"]]), , drop = FALSE]
  rownames(out) <- NULL
  out
}
