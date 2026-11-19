# check_budget(): a plan against the budget envelope it was signed under.
#
# A real plan's "topline" is rarely a plan. It is a set of signed
# authorisations -- Streaming may spend 1.2m in Q4, Programmatic 800k -- that
# the detailed plan is expected to land on, give or take a little. That is a
# pairing, like a plan and a decomp: two artifacts, each valid on its own,
# checked against each other. So it warns rather than errors, and the budget
# is an argument, never a slot on the plan.
#
# A subplan is different, and the help pages say so: a subplan OWNS a cell of
# the plan, and the cell must equal its rollup exactly. An envelope only sets a
# target the plan is checked against, with a tolerance.

#' Check a plan against a budget envelope
#'
#' Compares a plan with the budget it was authorised under: rows such as
#' "Streaming, October to December, 1.2m". For each budget row, the plan's
#' spend on the matching line items inside that window is summed, and the
#' variance reported. Rows whose variance is more than `tolerance` either way
#' are listed in a warning.
#'
#' Budget rows may name any subset of the plan's line item columns, at any
#' window, and may overlap -- a quarterly channel envelope and a whole-year
#' total can sit in one table. Spend is measured day by day (through
#' [calendarize()]), so a window that ends mid-week takes only the days of that
#' week inside it, whatever the plan is keyed by.
#'
#' Like [check_coverage()], this **warns rather than errors**: the plan and
#' the budget are each valid, and it is their pairing that disagrees.
#'
#' @section An envelope is not a subplan:
#' Both put a number on part of a plan, and they are easy to confuse. A budget
#' envelope is a **target**: the plan is checked against it, with a tolerance,
#' and nothing stops the plan from missing it. A subplan ([attach_subplan()])
#' is **ownership**: a team plans that cell's detail, and the plan's rows there
#' *are* the subplan's rollup, exactly, and cannot be edited around it. Signed
#' channel-by-quarter authorisations are an envelope.
#'
#' @param plan A [MediaPlan].
#' @param budget A data frame, one row per envelope: `from` and `to` (the
#'   window, inclusive; `Date` or ISO strings), `amount`, and any of the
#'   plan's [line_item_grain()] columns naming which line items it covers. A
#'   column left out, or `NA` in a row, means every value -- a row with no
#'   line item columns is a whole-plan envelope.
#' @param tolerance How far planned spend may sit from a budget row's
#'   `amount`, either way, before the row is reported. In the plan's money;
#'   default half a unit, i.e. a rounding difference.
#' @return The budget rows, with `from` and `to` as dates, plus:
#'   \describe{
#'     \item{`planned`}{The plan's spend on those line items in that window.}
#'     \item{`variance`}{`planned - amount`: positive is over budget.}
#'     \item{`variance_pct`}{`variance / amount`; `NA` for a zero budget.}
#'     \item{`in_plan`}{`FALSE` when the row names a value the plan does not
#'       have at all -- a channel with no line items -- so its `planned` of 0
#'       is an absence rather than an underspend.}
#'     \item{`within`}{Whether the variance is within `tolerance`.}
#'   }
#' @seealso [attach_subplan()] for a cell a team owns outright;
#'   [describe_plan()], which summarises the variances when given a budget.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(month = rep(as.Date(c("2026-10-01", "2026-11-01",
#'                                    "2026-12-01")), each = 2),
#'              channel = c("Streaming", "Search"),
#'              planned_spend = c(400, 100, 400, 100, 420, 100)),
#'   grain = "channel", time = "month", name = "Q4"
#' )
#' budget <- data.frame(
#'   channel = c("Streaming", "Search", NA),
#'   from = "2026-10-01", to = "2026-12-31",
#'   amount = c(1200, 300, 1500)
#' )
#' check_budget(plan, budget)
#' @export
check_budget <- function(plan, budget, tolerance = 0.5) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!.is_single_number(tolerance) || tolerance < 0) {
    stop("`tolerance` must be a single number, 0 or more.", call. = FALSE)
  }
  budget <- .as_budget(budget, plan)
  lg <- intersect(line_item_grain(plan), names(budget))

  # The plan's spend by line item and day: every basis lands on the same
  # calendar, so a window can cut a week or a month wherever it ends.
  daily <- calendarize(plan, "day")

  planned <- numeric(nrow(budget))
  in_plan <- logical(nrow(budget))
  for (i in seq_len(nrow(budget))) {
    covers <- .budget_row_covers(budget[i, , drop = FALSE], daily, lg)
    in_window <- daily[["day"]] >= budget$from[i] & daily[["day"]] <= budget$to[i]
    planned[i] <- sum(daily[["planned_spend"]][covers & in_window])
    in_plan[i] <- any(covers)
  }

  out <- budget
  out[["planned"]]      <- round(planned, 2)
  out[["variance"]]     <- round(planned - budget$amount, 2)
  out[["variance_pct"]] <- ifelse(budget$amount != 0,
                                  out$variance / budget$amount, NA_real_)
  out[["in_plan"]]      <- in_plan
  out[["within"]]       <- abs(out$variance) <= tolerance

  if (!all(out$within)) .warn_off_budget(out, lg, tolerance)
  out
}

# The budget as given, checked: the window columns read as dates, the amount a
# number, and every other column one of the plan's line item columns.
.as_budget <- function(budget, plan) {
  if (!is.data.frame(budget)) {
    stop("`budget` must be a data frame with `from`, `to` and `amount`.",
         call. = FALSE)
  }
  need <- setdiff(c("from", "to", "amount"), names(budget))
  if (length(need)) {
    stop("`budget` is missing column(s): ", paste(need, collapse = ", "), ".",
         call. = FALSE)
  }
  lg <- line_item_grain(plan)
  unknown <- setdiff(names(budget), c("from", "to", "amount", lg))
  if (length(unknown)) {
    stop("`budget` names column(s) the plan's line items do not have: ",
         paste(unknown, collapse = ", "), ". It may use: ",
         paste(lg, collapse = ", "), ".", call. = FALSE)
  }
  if (!is.numeric(budget$amount) || anyNA(budget$amount)) {
    stop("`budget$amount` must be numbers, with none missing.", call. = FALSE)
  }

  for (col in c("from", "to")) {
    budget[[col]] <- .as_budget_date(budget[[col]], col)
  }
  backwards <- which(budget$to < budget$from)
  if (length(backwards)) {
    stop("budget row(s) ", paste(backwards, collapse = ", "), " end before ",
         "they start.", call. = FALSE)
  }
  rownames(budget) <- NULL
  budget
}

.as_budget_date <- function(x, col) {
  d <- if (inherits(x, "Date")) x else
    suppressWarnings(tryCatch(as.Date(as.character(x)),
                              error = function(e) rep(as.Date(NA), length(x))))
  if (anyNA(d)) {
    stop("`budget$", col, "` must be dates: Date values or ISO strings such ",
         "as \"2026-10-01\".", call. = FALSE)
  }
  d
}

# Which of the daily rows a budget row covers, by its line item columns alone.
# NA in a budget column covers every value.
.budget_row_covers <- function(row, daily, cols) {
  covers <- rep(TRUE, nrow(daily))
  for (col in cols) {
    want <- row[[col]]
    if (!is.na(want)) {
      covers <- covers & as.character(daily[[col]]) == as.character(want)
    }
  }
  covers
}

# A budget row in words: what it covers, and when.
# "channel Streaming, 2026-10-01..2026-12-31"; "(whole plan), 2026-...".
.budget_label <- function(row, cols) {
  named <- Filter(function(v) !is.na(v), as.list(row[cols]))
  paste0(.target_label(named), ", ", row$from, "..", row$to)
}

.warn_off_budget <- function(out, cols, tolerance) {
  off <- out[!out$within, , drop = FALSE]
  lines <- vapply(seq_len(nrow(off)), function(i) {
    row <- off[i, , drop = FALSE]
    paste0(.budget_label(row, cols), ": planned ", .money(row$planned),
           " against ", .money(row$amount), " (",
           .signed_money(row$variance), ")",
           if (!row$in_plan) " -- not in the plan" else "")
  }, character(1))
  warning(nrow(off), " budget row(s) off by more than ", tolerance, ": ",
          .first_few(lines, 5), ".", call. = FALSE)
}
