# Verbs that take a plan are S7 generics dispatching on it.

# The operation keys recognised in an edit op. Exactly one per op.
#
# Two families. Value ops change planned_spend on rows that already exist and
# leave the row set alone -- everything the package could do until now.
# Structural ops change which rows there are: a plan can finally gain and lose
# line items, and a flight can move.
.value_ops      <- c("set", "scale", "delta", "delta_each", "total")
.structural_ops <- c("add", "drop", "shift", "restage")
.op_keys        <- c(.value_ops, .structural_ops)

# Resolve an op's `target` to a logical row mask over `d`.
#
# `target` is a named list of grain column -> value(s), naming any SUBSET of the
# grain (a partial key). Missing/empty target matches every row. Unmatched
# values error rather than silently selecting nothing — a caller (or an LLM)
# that typos a channel name must hear about it, not get a no-op scenario back.
.match_target <- function(d, grain, target, where = "") {
  if (is.null(target) || length(target) == 0) return(rep(TRUE, nrow(d)))

  if (!is.list(target) || is.null(names(target)) || any(!nzchar(names(target)))) {
    stop(where, "`target` must be a named list of grain column = value(s).",
         call. = FALSE)
  }
  unknown <- setdiff(names(target), grain)
  if (length(unknown)) {
    stop(where, "`target` may only name grain columns (",
         paste(grain, collapse = ", "), "); got: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }

  # Per-column check first, so a typo names the offending value and the
  # alternatives instead of producing a bare "matched no rows".
  for (nm in names(target)) {
    have <- unique(as.character(d[[nm]]))
    bad <- setdiff(as.character(target[[nm]]), have)
    if (length(bad)) {
      stop(where, "no such value(s) in '", nm, "': ",
           paste(bad, collapse = ", "), ". Valid: ",
           paste(utils::head(have, 8), collapse = ", "),
           if (length(have) > 8) ", ..." else "", call. = FALSE)
    }
  }

  keep <- rep(TRUE, nrow(d))
  for (nm in names(target)) {
    keep <- keep & (as.character(d[[nm]]) %in% as.character(target[[nm]]))
  }
  if (!any(keep)) {
    stop(where, "target matched no rows: the values are individually valid but ",
         "do not co-occur in the plan.", call. = FALSE)
  }
  keep
}

# Resolve `during` to a row mask: rows whose period OVERLAPS the window.
#
# Overlap, not containment -- "cut back April" means every buy that is live in
# April, including one that started in March. Note that `during` SELECTS rows,
# it never slices them: a flight that is half in the window is matched whole,
# and an op applies to all of it.
.match_during <- function(d, plan, during, where = "") {
  if (!is.list(during) || !all(c("from", "to") %in% names(during))) {
    stop(where, "`during` must be a list with `from` and `to` dates.",
         call. = FALSE)
  }
  from <- .as_op_date(during[["from"]], "during$from", where)
  to   <- .as_op_date(during[["to"]],   "during$to",   where)
  if (to < from) {
    stop(where, "`during` ends (", format(to), ") before it starts (",
         format(from), ").", call. = FALSE)
  }
  span <- .span_of(d, plan@week_col)
  if (is.null(span)) {
    stop(where, "`during` needs a plan with a week column; this plan has no ",
         "time dimension.", call. = FALSE)
  }
  span$start <= to & span$end >= from
}

# A date supplied inside an op, which for an LLM caller arrives as a string.
.as_op_date <- function(x, what, where = "") {
  if (inherits(x, "Date")) return(x[1])
  d <- suppressWarnings(tryCatch(as.Date(as.character(x)[1]),
                                 error = function(e) NA))
  if (is.na(d)) {
    stop(where, "`", what, "` must be a Date or an ISO-8601 date string; got: ",
         paste(utils::head(as.character(x), 1), collapse = ""), ".",
         call. = FALSE)
  }
  d
}

# The rows an op acts on: target, narrowed by during when given.
.match_rows <- function(d, plan, op, where = "") {
  keep <- .match_target(d, plan@grain, op[["target"]], where)
  if (!is.null(op[["during"]])) {
    keep <- keep & .match_during(d, plan, op[["during"]], where)
    if (!any(keep)) {
      stop(where, "no rows are in market during that window.", call. = FALSE)
    }
  }
  keep
}

# The weekday this plan's weeks begin on, for ops that create new weeks.
.plan_week_start <- function(plan) {
  ws <- week_start(plan)
  if (is.na(ws)) 1L else .weekday_num(ws)
}

# Apply one edit op to `d`, returning the updated data frame.
.apply_op <- function(d, plan, op, i) {
  where <- paste0("edit op ", i, ": ")
  if (!is.list(op)) {
    stop(where, "each op must be a list.", call. = FALSE)
  }

  present <- intersect(names(op), .op_keys)
  if (length(present) != 1L) {
    stop(where, "supply exactly one of ", paste(.op_keys, collapse = "/"),
         "; got ",
         if (!length(present)) "none" else paste(present, collapse = " + "),
         ".", call. = FALSE)
  }
  extra <- setdiff(names(op), c("target", "during", .op_keys))
  if (length(extra)) {
    stop(where, "unknown field(s): ", paste(extra, collapse = ", "),
         ". Allowed: target, during, ", paste(.op_keys, collapse = ", "), ".",
         call. = FALSE)
  }
  if (present == "add" && !is.null(op[["target"]])) {
    stop(where, "`add` does not take a `target`: it names the line item to ",
         "create, which by definition is not in the plan yet.", call. = FALSE)
  }

  out <- switch(
    present,
    add     = .op_add(d, plan, op[["add"]], where),
    drop    = .op_drop(d, plan, op, where),
    shift   = .op_shift(d, plan, op, where),
    restage = .op_restage(d, plan, op, where),
    .op_value(d, plan, op, present, where)
  )
  rownames(out) <- NULL
  out
}

# set / scale / delta / total -- spend on rows that already exist.
.op_value <- function(d, plan, op, present, where) {
  v <- op[[present]]
  if (!is.numeric(v) || length(v) != 1L || is.na(v)) {
    stop(where, "`", present, "` must be a single non-missing number.",
         call. = FALSE)
  }
  keep <- .match_rows(d, plan, op, where)
  ps <- d[["planned_spend"]]

  d[["planned_spend"]][keep] <- switch(
    present,
    set        = v,
    scale      = ps[keep] * v,
    delta_each = ps[keep] + v,
    # `delta` is the relative partner of `total`: it moves the matched cells'
    # SUM by v, holding their mix -- so "take 50k out of TV" takes 50k out of
    # TV, not 50k out of each of its weeks. Distributing in proportion rather
    # than evenly per cell is what preserves the channel's flighting shape, and
    # is why a flight stays "even" through it instead of flipping to "custom".
    delta = .group_total(ps[keep], sum(ps[keep]) + v, present, v, where),
    total = .group_total(ps[keep], v, present, v, where)
  )
  d
}

# Re-scale a group to `target`, holding its mix.
.group_total <- function(ps, target, present, v, where) {
  s <- sum(ps)
  if (s == 0) {
    stop(where, "cannot apply `", present, "` to a group whose current ",
         "planned_spend is 0: there is no mix to distribute by. Use `set`",
         if (present == "delta") " or `delta_each`" else "", " instead.",
         call. = FALSE)
  }
  if (target < 0) {
    stop(where, "`", present, "` of ", v, " would take the group below zero: ",
         "it currently plans ", format(s), ". A plan cannot hold negative ",
         "spend.", call. = FALSE)
  }
  ps / s * target
}

# drop -- remove matched rows entirely. Distinct from zeroing them: a dropped
# line item is not bought at all, where a zeroed one is still in the plan at
# nothing, and compare_scenarios() reports the two identically only by accident.
.op_drop <- function(d, plan, op, where) {
  if (!isTRUE(op[["drop"]])) {
    stop(where, "`drop` must be TRUE. It takes no value: the rows to remove ",
         "are named by `target` / `during`.", call. = FALSE)
  }
  keep <- .match_rows(d, plan, op, where)
  d[!keep, , drop = FALSE]
}

# add -- introduce a line item the plan does not have. Either for one week, or
# as a flight, which expands across the weeks it touches exactly as an import
# would.
.op_add <- function(d, plan, spec, where) {
  if (!is.list(spec) || is.null(names(spec)) || any(!nzchar(names(spec)))) {
    stop(where, "`add` must be a named list of the line item's columns plus ",
         "planned_spend, and either a week or flight_start/flight_end.",
         call. = FALSE)
  }
  if (!"planned_spend" %in% names(spec)) {
    stop(where, "`add` needs a `planned_spend`.", call. = FALSE)
  }
  spend <- spec[["planned_spend"]]
  if (!is.numeric(spend) || length(spend) != 1L || is.na(spend) || spend < 0) {
    stop(where, "`add$planned_spend` must be a single non-negative number.",
         call. = FALSE)
  }

  wk <- plan@week_col
  li <- setdiff(plan@grain, wk)
  miss <- setdiff(li, names(spec))
  if (length(miss)) {
    stop(where, "`add` is missing line item column(s): ",
         paste(miss, collapse = ", "), ".", call. = FALSE)
  }

  has_flight <- all(c("flight_start", "flight_end") %in% names(spec))
  if (length(wk) && !has_flight && !wk %in% names(spec)) {
    stop(where, "`add` needs either `", wk, "` or flight_start/flight_end: the ",
         "plan is weekly, so a new line item has to say when it runs.",
         call. = FALSE)
  }

  if (has_flight) {
    fs <- .as_op_date(spec[["flight_start"]], "add$flight_start", where)
    fe <- .as_op_date(spec[["flight_end"]],   "add$flight_end",   where)
    if (fe < fs) {
      stop(where, "the added flight ends (", format(fe), ") before it starts (",
           format(fs), ").", call. = FALSE)
    }
    ws <- .plan_week_start(plan)
    sp <- .spread_flight(fs, fe, spend, ws)
    # Adding a flight to a plan authored week-by-week introduces the flighting
    # columns, NA on every row that is not part of a flight.
    d   <- .ensure_flight_cols(d)
    new <- .blank_rows(d, nrow(sp))
    if (length(wk)) new[[wk]] <- sp[["week"]]
    new[["planned_spend"]] <- sp[["planned_spend"]]
    new[["flight_id"]]    <- .flight_ids(1L)
    new[["flight_start"]] <- fs
    new[["flight_end"]]   <- fe
    new[["period_basis"]] <- .infer_basis(fs, fe, ws)
    new[["pacing"]]       <- "even"
  } else {
    new <- .blank_rows(d, 1L)
    if (length(wk)) {
      new[[wk]] <- .as_op_date(spec[[wk]], paste0("add$", wk), where)
    }
    new[["planned_spend"]] <- spend
  }
  for (nm in li) new[[nm]] <- spec[[nm]]

  # Anything else the caller named that the plan carries as a column.
  for (nm in setdiff(names(spec), c(li, wk, "planned_spend",
                                    "flight_start", "flight_end"))) {
    if (nm %in% names(new)) new[[nm]] <- spec[[nm]]
  }

  out <- rbind(d, new)
  clash <- intersect(line_item(new, plan@grain), line_item(d, plan@grain))
  if (length(clash)) {
    stop(where, "the plan already has row(s) at ",
         paste(utils::head(clash, 3), collapse = "; "),
         ". Use set/scale/delta to change what is there, or drop it first.",
         call. = FALSE)
  }
  out
}

# n all-NA rows with `d`'s exact columns and types.
.blank_rows <- function(d, n) {
  out <- d[rep(NA_integer_, n), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# Give `d` the flighting columns if it lacks them, NA throughout. A plan
# authored week-by-week has none until a flight is added to it.
.ensure_flight_cols <- function(d) {
  for (nm in setdiff(flight_cols(), names(d))) {
    d[[nm]] <- if (nm %in% c("flight_start", "flight_end")) {
      as.Date(rep(NA_real_, nrow(d)))
    } else {
      NA_character_
    }
  }
  d
}

# shift -- move matched flights, or matched weeks, by a number of days.
.op_shift <- function(d, plan, op, where) {
  by <- op[["shift"]]
  if (!is.numeric(by) || length(by) != 1L || is.na(by) || by != round(by)) {
    stop(where, "`shift` must be a single whole number of days ",
         "(negative to move earlier).", call. = FALSE)
  }
  by <- as.integer(by)
  keep <- .match_rows(d, plan, op, where)
  .restage_rows(d, plan, keep, by = by, where = where)
}

# restage -- move matched flights to explicit dates.
.op_restage <- function(d, plan, op, where) {
  spec <- op[["restage"]]
  if (!is.list(spec) || !all(c("from", "to") %in% names(spec))) {
    stop(where, "`restage` must be a list with `from` and `to` dates.",
         call. = FALSE)
  }
  from <- .as_op_date(spec[["from"]], "restage$from", where)
  to   <- .as_op_date(spec[["to"]],   "restage$to",   where)
  if (to < from) {
    stop(where, "`restage` ends (", format(to), ") before it starts (",
         format(from), ").", call. = FALSE)
  }
  keep <- .match_rows(d, plan, op, where)
  .restage_rows(d, plan, keep, from = from, to = to, where = where)
}

# The engine behind shift and restage.
#
# `flight_id` is DELIBERATELY preserved. A moved buy is the same buy, so a
# scenario and its parent can be compared flight to flight rather than reading
# as a drop plus an add. That only works within a derivation tree -- ids are
# minted per import -- which is exactly the case that matters here.
#
# Matching one row of a flight moves the whole flight: half a flight in one
# place and half in another is not a thing a planner can buy.
.restage_rows <- function(d, plan, keep, by = NULL, from = NULL, to = NULL,
                          where = "") {
  wk <- plan@week_col
  if (!length(wk)) {
    stop(where, "this plan has no time dimension, so there is nothing to move.",
         call. = FALSE)
  }
  ws  <- .plan_week_start(plan)
  ids <- if ("flight_id" %in% names(d)) unique(d[["flight_id"]][keep]) else NULL
  ids <- ids[!is.na(ids)]

  # Rows with no flight: move the week itself. Only whole weeks, because a week
  # column shifted by three days no longer holds week starts.
  plain <- keep & (if (length(ids)) !(d[["flight_id"]] %in% ids) else TRUE)
  plain[is.na(plain)] <- keep[is.na(plain)]
  if (any(plain)) {
    if (is.null(by)) {
      stop(where, "`restage` needs flights: row(s) matched here record no ",
           "flight, so they have no in-market dates to restage. Use `shift` to ",
           "move their weeks, or `drop` and `add` to replace them.",
           call. = FALSE)
    }
    if (by %% 7L != 0L) {
      stop(where, "`shift` on rows that record no flight must be a whole ",
           "number of weeks (a multiple of 7); got ", by, ". Those rows are ",
           "keyed by week start, which a part-week shift would break.",
           call. = FALSE)
    }
    d[[wk]][plain] <- .as_date(d[[wk]][plain] + by)
  }

  for (id in ids) {
    d <- .restage_one(d, plan, id, by = by, from = from, to = to, ws = ws,
                      where = where)
  }

  k <- line_item(d, plan@grain)
  if (anyDuplicated(k)) {
    dups <- unique(k[duplicated(k)])
    stop(where, "moving it there would collide with what is already planned: ",
         paste(utils::head(dups, 3), collapse = "; "),
         ". A plan holds one period per line item per week.", call. = FALSE)
  }
  d
}

.restage_one <- function(d, plan, id, by, from, to, ws, where) {
  wk <- plan@week_col
  i  <- which(d[["flight_id"]] == id)
  fs <- d[["flight_start"]][i][1]
  fe <- d[["flight_end"]][i][1]

  new_fs <- if (is.null(by)) from else .as_date(fs + by)
  new_fe <- if (is.null(by)) to   else .as_date(fe + by)

  total <- sum(d[["planned_spend"]][i])
  sp    <- .spread_flight(new_fs, new_fe, total, ws)

  # A hand-shaped flight has per-week values with nowhere to land if the week
  # structure changes. Carry the shape across when it maps 1:1, and refuse
  # otherwise rather than silently discarding the planner's work.
  if (identical(d[["pacing"]][i][1], "custom")) {
    old_span <- .span_of(d, wk)[i, , drop = FALSE]
    old_ord  <- order(old_span$start)
    old_days <- as.integer(old_span$end - old_span$start)[old_ord] + 1L
    new_days <- as.integer(sp[["week"]] +
                             pmin(6L, as.integer(new_fe - sp[["week"]])) -
                             pmax(sp[["week"]], new_fs)) + 1L
    if (!identical(old_days, new_days)) {
      stop(where, "flight ", id, " is custom-paced, and moving it there ",
           "changes its week structure (", paste(old_days, collapse = "+"),
           " days becomes ", paste(new_days, collapse = "+"),
           "), so its hand-set weekly figures have nowhere to land. Move it a ",
           "whole number of weeks, or re-shape it after moving.",
           call. = FALSE)
    }
    sp[["planned_spend"]] <- d[["planned_spend"]][i][old_ord]
  }

  new <- .blank_rows(d, nrow(sp))
  for (nm in setdiff(names(d), c(wk, "planned_spend", "flight_start",
                                 "flight_end"))) {
    new[[nm]] <- d[[nm]][i][1]
  }
  new[[wk]]              <- sp[["week"]]
  new[["planned_spend"]] <- sp[["planned_spend"]]
  new[["flight_start"]]  <- new_fs
  new[["flight_end"]]    <- new_fe

  rbind(d[-i, , drop = FALSE], new)
}

# Apply edits to a plan's data, returning a new data frame. Accepts three
# shapes; see ?build_scenario.
.apply_edits <- function(plan, edits) {
  d <- plan@data
  g <- plan@grain
  base_key <- line_item(d, g)

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
    ek <- line_item(edits, g)
    unknown <- setdiff(ek, base_key)
    if (length(unknown)) {
      stop("`edits` reference row(s) not in the plan: ",
           paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
    }
    idx <- match(ek, base_key)
    d[["planned_spend"]][idx] <- as.numeric(edits[["planned_spend"]])

  } else if (is.numeric(edits) && !is.null(names(edits))) {
    unknown <- setdiff(names(edits), base_key)
    if (length(unknown)) {
      stop("`edits` reference row(s) not in the plan: ",
           paste(utils::head(unknown, 5), collapse = "; "), call. = FALSE)
    }
    idx <- match(names(edits), base_key)
    d[["planned_spend"]][idx] <- as.numeric(edits)

  } else if (is.list(edits)) {
    # One op, or a list of ops applied in order.
    ops <- if (any(names(edits) %in% c("target", "during", .op_keys))) {
      list(edits)
    } else {
      edits
    }
    if (!length(ops)) {
      stop("`edits` is an empty list; supply at least one operation.",
           call. = FALSE)
    }
    for (i in seq_along(ops)) d <- .apply_op(d, plan, ops[[i]], i)

  } else {
    stop("`edits` must be one of: a list of operations (target + ",
         paste(.op_keys, collapse = "/"), "), a data frame (grain columns + ",
         "planned_spend), or a named numeric vector keyed by line_item().",
         call. = FALSE)
  }

  # Every edit form funnels through here, so this is the one place the derived
  # facts can fall out of step with the money.
  #
  # .reunit() re-derives units from the new spend at the HELD rate: a cut budget
  # buys fewer impressions, it does not win a better CPM.
  # .repace() re-derives each flight's pacing; a flight is never broken by an
  # edit, only re-labelled "custom" when its shape no longer matches an even
  # spread.
  .repace(.reunit(d), plan@week_col)
}

#' Derive a new scenario plan from a base plan
#'
#' Produces a new [MediaPlan] by changing `planned_spend` and leaving everything
#' else untouched. The returned plan carries `@parent_id` set to the base plan's
#' id, so lineage is preserved through every derivation, and the base plan is
#' never mutated.
#'
#' `mediaplanr` deliberately does not forecast or optimize: it expresses *plan
#' intent*. To build a scenario from an optimizer, run the optimization
#' elsewhere (e.g. `mrmopt::opt_mix()`) and pass the resulting planned_spend allocation
#' in as an absolute `edits` data frame.
#'
#' @section Edit forms:
#' `edits` accepts three shapes.
#'
#' **1. Operations** — a list of ops, or a single op, applied in order. This is
#' the form to drive from a UI or an LLM tool call: the caller states the
#' *operation* and the arithmetic happens here, exactly.
#'
#' Each op is `list(<selection>, <exactly one operation>)`.
#'
#' **Selecting rows**
#' \describe{
#'   \item{`target`}{Named list of grain column = value(s), naming any **subset**
#'     of the grain — so `list(week = "2026-03-09")` hits every channel in that
#'     week. Values may be vectors. Omit `target` to match the whole plan.
#'     Targeting a value that does not exist is an error, never a silent no-op.}
#'   \item{`during`}{`list(from =, to =)`. Narrows to rows whose period
#'     **overlaps** that window — so "cut back April" reaches a flight that
#'     started in March and is still running. `during` *selects* rows; it never
#'     slices them, so a flight half inside the window is matched whole.}
#' }
#'
#' **Changing spend on rows that exist**
#' \describe{
#'   \item{`total`}{Make the matched cells **sum** to this, holding their
#'     current mix. This is the "set the budget" operation.}
#'   \item{`delta`}{Move the matched cells' **sum** by this, holding their mix.
#'     This is the "take 50k out of TV" operation.}
#'   \item{`scale`}{Multiply each matched cell (e.g. `1.2` = +20%). Per cell and
#'     across cells mean the same thing for a multiplier.}
#'   \item{`set`}{Absolute planned_spend, applied to **each** matched cell.}
#'   \item{`delta_each`}{Add to **each** matched cell (may be negative).}
#' }
#'
#' Note the deliberate split, and that it runs both ways:
#'
#' | | across the matched cells | to each matched cell |
#' |---|---|---|
#' | absolute | `total` | `set` |
#' | relative | `delta` | `delta_each` |
#'
#' So `list(target = list(channel = "TV"), total = 50)` makes TV's rows add up
#' to 50, while `set = 50` puts 50 on every TV row. Likewise `delta = -50`
#' takes 50 out of TV altogether, while `delta_each = -50` takes 50 out of
#' every TV row — which on a 26-week plan is 1,300.
#'
#' `delta` is almost always the one you want, and it is the one to reach for
#' when a user says "move 50k from TV to Social": two ops, `delta = -50000` on
#' TV and `delta = 50000` on Social. Distributing in proportion rather than
#' evenly per cell preserves the channel's flighting shape, so a flight stays
#' evenly paced through it.
#'
#' **Changing which rows there are**
#' \describe{
#'   \item{`add`}{Named list: the line item's columns, a `planned_spend`, and
#'     either the week or `flight_start`/`flight_end`. A flight expands across
#'     the weeks it touches exactly as [media_plan_from_flights()] would. Takes
#'     no `target` — the row does not exist yet. Adding onto a cell the plan
#'     already has is an error.}
#'   \item{`drop`}{`TRUE`. Removes the matched rows entirely. Distinct from
#'     setting them to zero: a dropped line item is not bought at all, where a
#'     zeroed one is still in the plan at nothing.}
#'   \item{`shift`}{A whole number of days, negative to move earlier. Moves the
#'     matched **flights**, re-spreading each total across its new dates. Rows
#'     that record no flight have their week moved instead, which must be a
#'     multiple of 7.}
#'   \item{`restage`}{`list(from =, to =)`. Moves the matched flights to those
#'     dates. Needs flights; rows without one have no in-market dates to move.}
#' }
#'
#' A moved flight **keeps its `flight_id`**, so a scenario and its parent can be
#' read flight to flight rather than as a drop plus an add. Matching one row of a
#' flight moves the whole flight. A custom-paced flight keeps its hand-set weekly
#' figures when the move maps them 1:1 — a whole-week shift of a week-aligned
#' flight — and errors otherwise rather than silently discarding them.
#'
#' **2. Data frame** — grain columns + `planned_spend`; matched cells are
#' overridden with those absolute values. Natural for optimizer output.
#'
#' **3. Named numeric vector** — keyed by [line_item()], e.g. `c("TV" = 100)`.
#' Terse for one or two cells at a simple grain.
#'
#' @section Metadata on a derived scenario:
#' `advertiser` and `planner` are **inherited** from the parent — they describe
#' the engagement and the person working, not the individual scenario — and can
#' be overridden per call.
#'
#' `status` is deliberately **not** inherited. A scenario derived from an
#' `"approved"` plan is not itself approved, and silently carrying that forward
#' would manufacture an approval nobody gave. It resets to `"in development"`,
#' which is what a freshly derived scenario actually is, unless you say
#' otherwise.
#'
#' `name` is required and `nickname` is per-scenario, so neither is inherited.
#'
#' @param plan The base [MediaPlan].
#' @param edits The edits to apply; see *Edit forms*.
#' @param name Formal name for the new scenario. **Required**.
#' @param nickname Optional short working handle. Preferred over `name` when
#'   labelling the scenario in a [ScenarioSet].
#' @param advertiser Optional override; defaults to the parent's advertiser.
#' @param planner Optional override; defaults to the parent's planner.
#' @param status Workflow state for the new scenario; defaults to
#'   `"in development"`. Never inherited from the parent.
#' @param objective Human-facing objective / notes for the new scenario.
#' @param ... Unused; for method extension.
#' @return A new [MediaPlan] at the base plan's grain, with `@parent_id` set.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search", "Social"),
#'              planned_spend = c(80, 40, 40)),
#'   grain = "channel", name = "base"
#' )
#'
#' # "Increase Search by 20%" — the caller states intent, R does the math
#' build_scenario(base, edits = list(target = list(channel = "Search"),
#'                                   scale = 1.2), name = "Search +20%")
#'
#' # "Set the total budget to 200", holding the current mix
#' build_scenario(base, edits = list(total = 200), name = "Budget 200")
#'
#' # "Move 10 from TV to Search" — ops apply in order. `delta` moves each
#' # group's TOTAL, so this is budget-neutral however many rows they have.
#' build_scenario(base, edits = list(
#'   list(target = list(channel = "TV"),     delta = -10),
#'   list(target = list(channel = "Search"), delta =  10)
#' ), name = "shift 10")
#'
#' # Absolute allocation (e.g. from mrmopt::opt_mix())
#' build_scenario(
#'   base,
#'   edits = data.frame(channel = c("TV", "Search"), planned_spend = c(50, 70)),
#'   name = "Optimized"
#' )
#'
#' # Terse single-cell override
#' build_scenario(base, edits = c("Search" = 120), name = "Search boost")
#'
#' # A plan can gain and lose line items
#' build_scenario(base, edits = list(add = list(channel = "Audio",
#'                                              planned_spend = 25)),
#'                name = "add audio")
#' build_scenario(base, edits = list(target = list(channel = "TV"), drop = TRUE),
#'                name = "no TV")
#' @export
build_scenario <- S7::new_generic("build_scenario", "plan",
  function(plan, edits, name, nickname = "", advertiser = NULL, planner = NULL,
           status = "in development", objective = "", ...) S7::S7_dispatch())

S7::method(build_scenario, MediaPlan) <- function(plan, edits, name,
    nickname = "", advertiser = NULL, planner = NULL,
    status = "in development", objective = "", ...) {
  if (missing(edits) || is.null(edits)) {
    stop("`edits` is required: supply a list of operations, a data frame ",
         "(grain columns + planned_spend), or a named numeric vector keyed ",
         "by line_item().", call. = FALSE)
  }
  if (missing(name) || !length(name) || is.na(name[1]) || !nzchar(name[1])) {
    stop("`name` is required: every scenario carries a formal name. Use ",
         "`nickname` for a short working handle.", call. = FALSE)
  }
  MediaPlan(
    data       = .apply_edits(plan, edits),
    grain      = plan@grain,
    week_col   = plan@week_col,
    id         = new_id("plan"),
    parent_id  = plan@id,
    name       = name,
    nickname   = nickname,
    # Inherited: these describe the engagement, not the scenario.
    advertiser = advertiser %||% plan@advertiser,
    planner    = planner %||% plan@planner,
    # NOT inherited: a derivative of an approved plan is not itself approved.
    status     = .normalise_status(status),
    objective  = objective
  )
}
