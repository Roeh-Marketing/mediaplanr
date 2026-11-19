# model_map() and spend_by_model(): which response model scores which spend.
#
# Response models (mrmopt's) are fitted at whatever grain the data supported,
# and rarely the plan's: TV modelled as a channel, programmatic by partner, a
# new tactic not at all. To score a plan, each line item needs exactly one
# model, chosen the same way every time. The rule is the one roll_up() already
# implies -- fall back to the coarser level when the finer one has no model --
# made explicit: of the models whose named values all match a line item, the
# one naming the most columns wins.
#
# Like check_coverage() and check_budget(), this is a pairing: the plan and
# the model list are each valid, so a line item with no model is a warning and
# a visible NA, never an error and never silently dropped. Data frames in and
# out; nothing here knows about mrmopt.

#' Which response model scores each line item
#'
#' Maps every line item of a plan to the response model that should score it,
#' when models are fitted at a different grain from the plan -- or at several.
#' `models` lists the fitted models, one row each, by the line item values
#' they cover: a channel-level model names a channel and leaves the finer
#' columns empty; a partner-level model names the partner too.
#'
#' **The most specific model wins.** Of the models whose named values all
#' match a line item, the one naming the most columns is chosen, so a
#' partner-level model takes precedence over its channel's model, which is
#' the fallback for the channel's other partners. Two matching models naming
#' the same number of columns -- a channel model and a campaign model, both
#' covering one line -- is an error naming both: which one scores it is a
#' decision for whoever fitted them, not a guess for this function.
#'
#' A line item no model covers gets `model_id = NA`, and a warning gives the
#' spend left unmodeled and its share of the plan. Both the plan and the
#' models are valid on their own; it is their pairing that leaves a gap.
#'
#' @param plan A [MediaPlan].
#' @param models A data frame of fitted models: a `model_id` column (unique)
#'   and any of the plan's [line_item_grain()] columns. `NA` or a blank cell
#'   means the model covers any value of that column; a row with no line item
#'   columns set covers the whole plan.
#' @return One row per line item, in [line_item_summary()]'s order: the line
#'   item columns, `line_item` (its key), `model_id`, `match_level` (the
#'   columns the model matched on, joined with `" + "`; `""` for a
#'   whole-plan model, `NA` when unmodeled) and `planned_spend`.
#' @seealso [spend_by_model()] for the spend each model scores, period by
#'   period; [describe_plan()], which reports model coverage when given
#'   `models`.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "TV", "Search", "Audio"),
#'              partner = c("NBC", "ESPN", "Google", "Spotify"),
#'              planned_spend = c(50, 30, 40, 10)),
#'   grain = c("channel", "partner"), time = "week", name = "Q3"
#' )
#' models <- data.frame(
#'   model_id = c("tv", "tv_nbc", "search"),
#'   channel  = c("TV", "TV", "Search"),
#'   partner  = c(NA, "NBC", NA)
#' )
#' # NBC has its own model; ESPN falls back to TV's; Audio has none.
#' model_map(plan, models)
#' @export
model_map <- function(plan, models) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  models <- .as_models(models, plan)
  cols   <- setdiff(names(models), "model_id")

  roster <- line_item_summary(plan)
  roster <- roster[, c(line_item_grain(plan), "line_item", "planned_spend"),
                   drop = FALSE]

  chosen <- .most_specific_model(roster, models, cols)
  out <- roster[, c(line_item_grain(plan), "line_item"), drop = FALSE]
  out[["model_id"]]      <- models$model_id[chosen]
  out[["match_level"]]   <- .match_level(models, cols)[chosen]
  out[["planned_spend"]] <- roster$planned_spend
  rownames(out) <- NULL

  .warn_unmodeled(out)
  out
}

#' The spend each response model scores, period by period
#'
#' The input a response-model forecast needs: the plan's spend summed to each
#' model (as [model_map()] assigns line items to models) for each period of a
#' calendar. Spend no model covers is kept, under `model_id = NA`, so the
#' totals always reconcile to the plan -- it is never dropped silently.
#'
#' The plan is first re-cut onto the calendar with [calendarize()], so a
#' weekly model can score a monthly plan and the other way round, and a plan
#' keyed by moments lands on the days its spots air.
#'
#' @inheritParams model_map
#' @param basis The calendar to sum over: `"week"`, `"day"` or `"month"`.
#' @param week_start For `basis = "week"`, the weekday the models' weeks
#'   start on; the plan's own by default. See [calendarize()].
#' @return A long data frame, one row per model per period: `model_id`, a
#'   column named after `basis` holding each period's start, and
#'   `planned_spend`. When a model's rows are all one unit type, its
#'   `unit_type`, `planned_units` and blended `planned_rate` too. Ordered by
#'   model, unmodeled spend last, then by period.
#' @seealso [model_map()] for the mapping itself.
#' @examples
#' plan <- media_plan_from_df(
#'   data.frame(week = rep(as.Date(c("2026-07-06", "2026-07-13")), each = 2),
#'              channel = c("TV", "Search"),
#'              planned_spend = c(50, 40, 60, 40)),
#'   grain = "channel", time = "week", name = "Q3"
#' )
#' models <- data.frame(model_id = c("tv", "search"),
#'                      channel = c("TV", "Search"))
#' spend_by_model(plan, models)
#' spend_by_model(plan, models, basis = "month")
#'
#' \dontrun{
#' # The hand-off to a response model:
#' mrmopt::forecast(fitted_models, spend_by_model(plan, models))
#' }
#' @export
spend_by_model <- function(plan, models, basis = c("week", "day", "month"),
                           week_start = NULL) {
  basis <- match.arg(basis)
  map <- model_map(plan, models)

  cal <- calendarize(plan, basis, week_start = week_start)
  key <- line_item(cal, line_item_grain(plan))
  cal[["model_id"]] <- map$model_id[match(key, map$line_item)]

  # Sum each model's line items within each period; units ride along only
  # where they add up (one unit type), as they do everywhere else.
  keep <- intersect(c("model_id", basis, "planned_spend", unit_cols()),
                    names(cal))
  out <- .aggregate_to(cal[, keep, drop = FALSE], c("model_id", basis))
  out <- out[order(is.na(out$model_id), out$model_id, out[[basis]]), ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}

# ---- the models, checked -------------------------------------------------------

# The models as given, checked: a unique model_id, and every other column one
# of the plan's line item columns. Blank cells become NA -- "any value" --
# because a model list kept in a spreadsheet comes back with "" for empty.
.as_models <- function(models, plan) {
  if (!is.data.frame(models) || !"model_id" %in% names(models)) {
    stop("`models` must be a data frame with a `model_id` column and any of ",
         "the plan's line item columns.", call. = FALSE)
  }
  lg <- line_item_grain(plan)
  unknown <- setdiff(names(models), c("model_id", lg))
  if (length(unknown)) {
    stop("`models` names column(s) the plan's line items do not have: ",
         paste(unknown, collapse = ", "), ". It may use: ",
         paste(lg, collapse = ", "), ".", call. = FALSE)
  }

  models <- as.data.frame(models, stringsAsFactors = FALSE)
  models$model_id <- as.character(models$model_id)
  if (anyNA(models$model_id) || any(!nzchar(models$model_id))) {
    stop("every model needs a `model_id`.", call. = FALSE)
  }
  dup_ids <- unique(models$model_id[duplicated(models$model_id)])
  if (length(dup_ids)) {
    stop("`model_id` must be unique; repeated: ",
         paste(dup_ids, collapse = ", "), ".", call. = FALSE)
  }

  cols <- intersect(lg, names(models))
  for (col in cols) {
    v <- as.character(models[[col]])
    v[!is.na(v) & !nzchar(trimws(v))] <- NA
    models[[col]] <- v
  }

  # Two models covering exactly the same values would tie on every line item
  # they match; say so once, here, rather than per line item.
  key <- do.call(paste, c(lapply(cols, function(col) {
    ifelse(is.na(models[[col]]), "<any>", models[[col]])
  }), list(sep = " | ")))
  if (length(cols) && anyDuplicated(key)) {
    clash <- key[duplicated(key)][1]
    stop("models ", paste(models$model_id[key == clash], collapse = " and "),
         " cover exactly the same line items (", clash, "). Keep one.",
         call. = FALSE)
  }
  models[, c("model_id", cols), drop = FALSE]
}

# ---- matching ------------------------------------------------------------------

# For each roster row, the position in `models` of the model that scores it,
# or NA. A model matches a row when every column it names holds the row's
# value; of the matches, the one naming the most columns wins.
.most_specific_model <- function(roster, models, cols) {
  # covers[i, m]: does model m cover roster row i?
  covers <- matrix(vapply(seq_len(nrow(models)), function(m) {
    .model_covers(models[m, , drop = FALSE], roster, cols)
  }, logical(nrow(roster))), nrow = nrow(roster))
  specificity <- .specificity(models, cols)

  chosen <- rep(NA_integer_, nrow(roster))
  ties <- character(0)
  for (i in seq_len(nrow(roster))) {
    candidates <- which(covers[i, ])
    if (!length(candidates)) next
    best <- candidates[specificity[candidates] == max(specificity[candidates])]
    if (length(best) > 1L) {
      ties <- c(ties, paste0(roster$line_item[i], " (",
                             paste(models$model_id[best], collapse = ", "), ")"))
      next
    }
    chosen[i] <- best
  }
  if (length(ties)) {
    stop("two or more equally specific models cover the same line item, so ",
         "which one scores it would be a guess: ", .first_few(ties),
         ". Make one more specific, or drop one.", call. = FALSE)
  }
  chosen
}

# Which roster rows one model covers: every column it names matches.
.model_covers <- function(model, roster, cols) {
  covers <- rep(TRUE, nrow(roster))
  for (col in cols) {
    want <- model[[col]]
    if (!is.na(want)) covers <- covers & as.character(roster[[col]]) == want
  }
  covers
}

# How many columns each model names.
.specificity <- function(models, cols) {
  if (!length(cols)) return(rep(0L, nrow(models)))
  rowSums(!is.na(models[, cols, drop = FALSE]))
}

# The columns each model names, as text: "channel + partner"; "" for a model
# that names none and so covers the whole plan.
.match_level <- function(models, cols) {
  vapply(seq_len(nrow(models)), function(m) {
    named <- cols[!is.na(unlist(models[m, cols, drop = FALSE]))]
    paste(named, collapse = " + ")
  }, character(1))
}

.warn_unmodeled <- function(map) {
  gap <- is.na(map$model_id)
  if (!any(gap)) return(invisible(NULL))
  total <- sum(map$planned_spend)
  unmodeled <- sum(map$planned_spend[gap])
  share <- if (total > 0) unmodeled / total else 0
  items <- paste0(map$line_item[gap], " (", .money(map$planned_spend[gap]), ")")
  warning(sum(gap), " line item(s) have no model: ", .first_few(items),
          ". ", .money(unmodeled), " of ", .money(total), " planned spend (",
          round(100 * share, 1), "%) is unmodeled.", call. = FALSE)
}
