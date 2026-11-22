# Verbs that take a plan are S7 generics dispatching on it.
#
# Which ops exist, the fields each takes, and every check that needs no plan
# live in ops.R. This file applies an op to a plan's rows, and holds the checks
# that do need one: does the target exist, is the window in market, would a
# move collide with a row already planned.

# Resolve an op's `target` to a logical row mask over `d`.
#
# `target` is a named list of grain column -> value(s), naming any SUBSET of the
# grain (a partial key). Missing/empty target matches every row. Unmatched
# values error rather than silently selecting nothing — a caller (or an LLM)
# that typos a channel name must hear about it, not get a no-op scenario back.
#
# `none_hint` is appended when nothing matches, for a caller that knows what
# the fix is likely to be.
#
# `strict = FALSE` is for READING, never for an edit: a value the plan does not
# have matches nothing instead of erroring, because a scope or a section may
# name a channel the plan no longer buys. An unknown column is still an error
# either way -- that is a typo, not an absence.
.match_target <- function(d, grain, target, where = "", none_hint = "",
                          strict = TRUE) {
  if (is.null(target) || length(target) == 0) return(rep(TRUE, nrow(d)))

  .check_target_shape(target, "target", where)
  unknown <- setdiff(names(target), grain)
  if (length(unknown)) {
    stop(where, "`target` may only name grain columns (",
         paste(grain, collapse = ", "), "); got: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }

  # Per-column check first, so a typo names the offending value and the
  # alternatives instead of producing a bare "matched no rows".
  if (strict) for (nm in names(target)) {
    have <- unique(as.character(d[[nm]]))
    bad <- setdiff(as.character(target[[nm]]), have)
    if (length(bad)) {
      stop(where, "no such value(s) in '", nm, "': ",
           paste(bad, collapse = ", "), ". Valid: ",
           paste(utils::head(have, 8), collapse = ", "),
           if (length(have) > 8) ", ..." else ".", none_hint,
           call. = FALSE)
    }
  }

  keep <- rep(TRUE, nrow(d))
  for (nm in names(target)) {
    keep <- keep & (as.character(d[[nm]]) %in% as.character(target[[nm]]))
  }
  if (strict && !any(keep)) {
    stop(where, "target matched no rows: the values are individually valid but ",
         "do not co-occur in the plan.", none_hint, call. = FALSE)
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
  # A window given as dates against a plan of moments means whole days: from
  # midnight of `from` through the last moment of `to`.
  tv   <- d[[plan@time_col]]
  from <- .as_op_time(during[["from"]], "during$from", tv, where)
  to   <- .as_op_time(during[["to"]],   "during$to",   tv, where, end = TRUE)
  if (to < from) {
    stop(where, "`during` ends (", format(to), ") before it starts (",
         format(from), ").", call. = FALSE)
  }
  span <- .span_of(d, plan@time_col, plan@time_basis)
  span$start <= to & span$end >= from
}

# A date or moment from an op, read in the PLAN's frame rather than the
# session's.
#
# "2026-02-08 20:45" means a quarter to nine on the plan's clock, whoever's
# machine the op is parsed on. Without this an op does not round-trip: a spot
# added at 20:45 to a UTC schedule lands five hours out for a caller in New
# York, silently, because base R reads a bare string in the session timezone.
# A value that arrives already typed is left alone -- it names an instant, and
# whoever built it meant it.
#
# `end = TRUE` reads a bare date as the END of that day, so "through Feb 8"
# includes the 20:00 spot rather than stopping at midnight.
.as_op_time <- function(x, what, like, where = "", end = FALSE) {
  v <- .as_op_date(x, what, where)
  if (is.character(x) && inherits(v, "POSIXct")) {
    tz <- attr(like, "tzone")
    if (!is.null(tz)) {
      v <- as.POSIXct(format(v, "%Y-%m-%d %H:%M:%S"), tz = tz)
    }
  }
  if (end) .align_time_end(v, like) else .align_time(v, like)
}

# A date -- or a moment -- supplied inside an op, which for an LLM caller
# arrives as a string.
.as_op_date <- function(x, what, where = "") {
  if (inherits(x, "Date") || inherits(x, "POSIXct")) return(x[1])
  d <- suppressWarnings(tryCatch(.as_time_col(as.character(x)[1], what),
                                 error = function(e) NA))
  if (length(d) != 1 || is.na(d)) {
    stop(where, "`", what, "` must be a Date, a moment, or an ISO-8601 string ",
         "of either; got: ",
         paste(utils::head(as.character(x), 1), collapse = ""), ".",
         call. = FALSE)
  }
  d
}

# The rows an op acts on: its target, narrowed by its during when given.
.match_rows <- function(d, plan, op, where = "") {
  .select_rows(d, plan, op[["target"]], op[["during"]], where)
}

# The rows a target selects, narrowed by a window when given. Rows a subplan
# owns are refused here, so every edit door gets that check.
.select_rows <- function(d, plan, target, during = NULL, where = "",
                         none_hint = "") {
  keep <- .find_rows(d, plan, target, during, where, none_hint)
  .stop_if_backed(plan, d, keep, where)
  keep
}

# The same selection with no subplan refusal: the read path, shared by
# .select_rows() and by match_rows() and its kin in sections.R, so a scope
# check and an edit can never resolve a target differently. `strict` as in
# .match_target(); a window that leaves nothing is an error only when strict.
.find_rows <- function(d, plan, target, during = NULL, where = "",
                       none_hint = "", strict = TRUE) {
  keep <- .match_target(d, plan@grain, target, where, none_hint, strict)
  if (!is.null(during)) {
    keep <- keep & .match_during(d, plan, during, where)
    if (strict && !any(keep)) {
      stop(where, "no rows are in market during that window.", none_hint,
           call. = FALSE)
    }
  }
  keep
}

# Rows a subplan owns are read-only on the parent. Every edit door passes its
# selection through here, so the error names the right door -- the subplan --
# rather than silently letting the topline drift from the detail beneath it.
.stop_if_backed <- function(plan, d, keep, where = "") {
  if (!length(plan@subplans)) return(invisible(NULL))
  hit <- keep & .backed_rows(plan, d)
  hit[is.na(hit)] <- FALSE
  if (any(hit)) {
    key <- line_item(d, line_item_grain(plan))[hit][1]
    stop(where, .cell_label(plan, key), " is planned in a subplan; edit the ",
         "subplan and re-attach.", call. = FALSE)
  }
  invisible(NULL)
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
  # Everything checkable without the plan, from the registry in ops.R -- the
  # same checks an op_*() constructor ran, so a hand-written or JSON op gets
  # them too.
  key <- .op_key(op, where)
  .check_op_fields(op, key, where)

  out <- switch(
    key,
    transfer = .apply_transfer(d, plan, op, where),
    add      = .apply_add(d, plan, op[["add"]], where),
    drop     = .apply_drop(d, plan, op, where),
    shift    = .apply_shift(d, plan, op, where),
    restage  = .apply_restage(d, plan, op, where),
    rebound  = .apply_rebound(d, plan, op, where),
    .apply_value(d, plan, op, key, where)
  )
  rownames(out) <- NULL
  out
}

# set / scale / delta / delta_each / total -- spend on rows that already exist.
.apply_value <- function(d, plan, op, present, where) {
  v    <- op[[present]]
  keep <- .match_rows(d, plan, op, where)
  # The matched rows as a group: what they plan, and their spend bounds.
  group <- list(
    ps    = d[["planned_spend"]][keep],
    lower = .lower_bounds(d)[keep],
    upper = .upper_bounds(d)[keep],
    keys  = .bound_labels(d, plan@grain, keep),
    what  = paste0("`", present, "` of ", .money(v))
  )
  ps <- group$ps

  new <- switch(
    present,
    set        = rep(v, length(ps)),
    scale      = ps * v,
    delta_each = ps + v,
    # `delta` is the relative partner of `total`: it moves the matched cells'
    # SUM by v, holding their mix -- so "take 50k out of TV" takes 50k out of
    # TV, not 50k out of each of its weeks. Distributing in proportion rather
    # than evenly per cell is what preserves the channel's flighting shape, and
    # is why a flight stays "even" through it instead of flipping to "custom".
    # Rows at a bound stop there and the rest of the group takes up the slack.
    delta = .group_total(group, sum(ps) + v, present, v, where),
    total = .group_total(group, v, present, v, where)
  )
  # delta and total have already routed around the bounds; set, scale and
  # delta_each name each row's value outright, so a bound can only refuse them.
  .stop_if_outside_bounds(new, group$lower, group$upper, group$keys,
                          group$what, where)
  d[["planned_spend"]][keep] <- new
  d
}

# Re-scale a group to `target`, holding its mix as far as its bounds allow.
.group_total <- function(group, target, present, v, where) {
  s <- sum(group$ps)
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
  .distribute(group$ps, change = target - s, weights = group$ps,
              lower = group$lower, upper = group$upper,
              keys = group$keys, what = group$what, where = where)
}

# transfer -- move an amount from one set of rows to another, leaving the plan's
# total unchanged. The commonest real edit ("move 50k from TV to Social"), and
# as two deltas it would lose the fact that its halves belong together.
.apply_transfer <- function(d, plan, op, where) {
  amount <- op[["transfer"]]

  # Each side is a target narrowed by its own window, or by the shared one.
  from_rows <- .select_rows(
    d, plan, op[["from"]], op[["from_during"]] %||% op[["during"]],
    where = paste0(where, "`from`: ")
  )
  to_rows <- .select_rows(
    d, plan, op[["to"]], op[["to_during"]] %||% op[["during"]],
    where = paste0(where, "`to`: "),
    none_hint = paste0(" To move money into a line item the plan does not ",
                       "have yet, `add` it first, earlier in the same edits.")
  )
  both <- from_rows & to_rows
  if (any(both)) {
    rows <- line_item(d, plan@grain)[both]
    stop(where, "`from` and `to` share ", sum(both), " row(s), e.g. ",
         paste(utils::head(rows, 3), collapse = "; "), ". Money cannot move ",
         "from a row to itself: narrow one side with its target or window.",
         call. = FALSE)
  }

  ps <- d[["planned_spend"]]
  available <- sum(ps[from_rows])
  # Within half a cent of everything the source holds means all of it: a sum
  # of fractional rows rarely equals the figure a person types for it.
  if (amount > available && amount - available < 0.005) amount <- available
  if (amount > available) {
    stop(where, "`transfer` of ", format(amount), " is more than `from` ",
         "holds: it plans ", format(available), ". A plan cannot hold ",
         "negative spend.", call. = FALSE)
  }

  # Each side spreads within its rows' bounds, so a transfer out of a channel
  # with a committed line comes out of the lines that are free to give.
  lower <- .lower_bounds(d)
  upper <- .upper_bounds(d)
  keys  <- .bound_labels(d, plan@grain, rep(TRUE, nrow(d)))
  what  <- paste0("`transfer` of ", .money(amount))

  ps[from_rows] <- .distribute(
    ps[from_rows], -amount, weights = ps[from_rows],
    lower = lower[from_rows], upper = upper[from_rows], keys = keys[from_rows],
    what = what, where = paste0(where, "`from`: ")
  )
  ps[to_rows] <- .distribute(
    ps[to_rows], amount, weights = .receiving_weights(d, plan, to_rows),
    lower = lower[to_rows], upper = upper[to_rows], keys = keys[to_rows],
    what = what, where = paste0(where, "`to`: ")
  )
  .stop_if_total_changed(d[["planned_spend"]], ps, "transfer")

  d[["planned_spend"]] <- ps
  d
}

# How the rows receiving a transfer share it. In proportion to what they
# already plan, like delta -- or, when they plan nothing and so have no mix to
# follow, evenly by the days each is in market: the rule an even flight
# follows, so money moved into an empty flight lands as if it had been bought
# that way.
.receiving_weights <- function(d, plan, rows) {
  current <- d[["planned_spend"]][rows]
  if (sum(current) > 0) return(current)
  .row_days(d, plan@time_col, plan@time_basis)[rows]
}

# An op that only moves money must leave the plan's total where it was, to the
# cent. If it does not, the arithmetic above is wrong.
.stop_if_total_changed <- function(before, after, what) {
  drift <- sum(after) - sum(before)
  if (abs(drift) >= 0.005) {
    stop("internal: `", what, "` changed the plan's total by ", format(drift),
         ". This is a bug in mediaplanr.", call. = FALSE)
  }
  invisible(NULL)
}

# drop -- remove matched rows entirely. Distinct from zeroing them: a dropped
# line item is not bought at all, where a zeroed one is still in the plan at
# nothing, and compare_scenarios() reports the two identically only by accident.
#
# A row with a floor cannot be dropped: the floor is money already promised.
.apply_drop <- function(d, plan, op, where) {
  keep <- .match_rows(d, plan, op, where)
  floored <- keep & .lower_bounds(d) > 0
  if (any(floored)) {
    stop(where, "`drop` would remove row(s) with a floor: ",
         .first_few(.bound_labels(d, plan@grain, floored)), ". Lower the ",
         "floor first with `rebound`, earlier in the same edits.",
         call. = FALSE)
  }
  d[!keep, , drop = FALSE]
}

# add -- introduce a line item the plan does not have. Either for one week, or
# as a flight, which expands across the weeks it touches exactly as an import
# would.
#
# `spec`'s shape -- a named list, a valid spend, both flight dates or neither --
# was checked by .check_line_item(); what is checked here needs the plan.
.apply_add <- function(d, plan, spec, where) {
  spend <- spec[["planned_spend"]]
  wk <- plan@time_col
  li <- setdiff(plan@grain, wk)
  miss <- setdiff(li, names(spec))
  if (length(miss)) {
    stop(where, "`add` is missing line item column(s): ",
         paste(miss, collapse = ", "), ".", call. = FALSE)
  }

  has_flight <- all(c("flight_start", "flight_end") %in% names(spec))
  if (!has_flight && !wk %in% names(spec)) {
    stop(where, "`add` needs either `", wk, "` or flight_start/flight_end: a ",
         "new line item has to say when it runs.", call. = FALSE)
  }
  # Bounds given for the new line item introduce the bound columns, NA (no
  # bound) on every row that already exists.
  bounds <- intersect(bound_cols(), names(spec))
  if (length(bounds)) d <- .ensure_bound_cols(d)

  if (has_flight) {
    # Read in the plan's own type: a date given to a timed plan means that whole
    # day, and a moment given to a weekly one means the day it falls on.
    fs <- .as_op_time(spec[["flight_start"]], "add$flight_start", d[[wk]], where)
    fe <- .as_op_time(spec[["flight_end"]], "add$flight_end", d[[wk]], where,
                      end = TRUE)
    if (fe < fs) {
      stop(where, "the added flight ends (", format(fe), ") before it starts (",
           format(fs), ").", call. = FALSE)
    }
    ws <- .plan_week_start(plan)
    sp <- .spread_flight(fs, fe, spend, plan@time_basis, ws)
    # Adding a flight to a plan authored period-by-period introduces the
    # flighting columns, NA on every row that is not part of a flight.
    d   <- .ensure_flight_cols(d, d[[wk]])
    new <- .blank_rows(d, nrow(sp))
    new[[wk]] <- sp[["period"]]
    new[["planned_spend"]] <- sp[["planned_spend"]]
    # The recorded op names the flight it creates (.canonical_line_item()),
    # so a replay creates the same flight.
    new[["flight_id"]]    <- spec[["flight_id"]] %||% .flight_ids(1L)
    new[["flight_start"]] <- fs
    new[["flight_end"]]   <- fe
    new[["period_basis"]] <- .infer_basis(fs, fe, ws)
    new[["pacing"]]       <- "even"
    # A flight's bounds are for the whole buy, so they are split across its
    # periods beside its spend: a committed flight stays committed in every
    # period.
    for (b in bounds) {
      new[[b]] <- .split_bound(
        as.numeric(spec[[b]]), b, spend, sp[["planned_spend"]],
        function(x) .spread_flight(fs, fe, x, plan@time_basis, ws)[["planned_spend"]]
      )
    }
  } else {
    new <- .blank_rows(d, 1L)
    new[[wk]] <- .as_op_time(spec[[wk]], paste0("add$", wk), d[[wk]], where)
    new[["planned_spend"]] <- spend
    for (b in bounds) new[[b]] <- as.numeric(spec[[b]])
  }
  for (nm in li) new[[nm]] <- spec[[nm]]
  # Adding into a cell a subplan owns is an edit to that cell.
  .stop_if_backed(plan, new, rep(TRUE, nrow(new)), where)

  # Anything else the caller named that the plan carries as a column.
  # The flight columns are set above, and only for a flight: a flight_id named
  # on a single-period add must not attach the row to some other buy.
  for (nm in setdiff(names(spec), c(li, wk, "planned_spend", bound_cols(),
                                    flight_cols()))) {
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

# rebound -- set min_spend / max_spend on the matched rows, and no spend.
#
# A bound named in the op is replaced; one left out is untouched; NA or null
# removes it. The new bounds must still contain what each row plans: rebound
# records a commitment, it does not move money to fit one.
.apply_rebound <- function(d, plan, op, where) {
  spec <- op[["rebound"]]
  keep <- .match_rows(d, plan, op, where)
  d    <- .ensure_bound_cols(d)

  as_bound <- function(v) if (.is_no_bound(v)) NA_real_ else as.numeric(v)
  if ("min" %in% names(spec)) d[["min_spend"]][keep] <- as_bound(spec[["min"]])
  if ("max" %in% names(spec)) d[["max_spend"]][keep] <- as_bound(spec[["max"]])

  .stop_if_outside_bounds(
    d[["planned_spend"]][keep], .lower_bounds(d)[keep], .upper_bounds(d)[keep],
    keys = .bound_labels(d, plan@grain, keep), what = "`rebound`",
    where = where,
    fix = paste("Choose bounds that contain the spend already planned, or",
                "change the spend first, earlier in the same edits.")
  )
  d
}

# n all-NA rows with `d`'s exact columns and types.
.blank_rows <- function(d, n) {
  out <- d[rep(NA_integer_, n), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# Give `d` the flighting columns if it lacks them, NA throughout. A plan
# authored period-by-period has none until a flight is added to it.
#
# `like` is the plan's time column: the flight dates are compared against it on
# every span, so they are minted in its type -- moments on a timed plan, dates
# otherwise -- rather than always as Dates.
.ensure_flight_cols <- function(d, like = as.Date(NA)) {
  for (nm in setdiff(flight_cols(), names(d))) {
    d[[nm]] <- if (nm %in% c("flight_start", "flight_end")) {
      .as_time_like(rep(NA_real_, nrow(d)), like)
    } else {
      NA_character_
    }
  }
  d
}

# shift -- move matched flights, or matched weeks, by a number of days.
.apply_shift <- function(d, plan, op, where) {
  by <- as.integer(op[["shift"]])
  keep <- .match_rows(d, plan, op, where)
  .restage_rows(d, plan, keep, by = by, where = where)
}

# restage -- move matched flights to explicit dates.
.apply_restage <- function(d, plan, op, where) {
  spec <- op[["restage"]]
  # Read in the plan's own frame, here rather than in .restage_one(), so the
  # two are comparable before anything is moved. A date and a moment can only
  # be ordered once both are on the plan's clock, so the order is checked again.
  tv   <- d[[plan@time_col]]
  from <- .as_op_time(spec[["from"]], "restage$from", tv, where)
  to   <- .as_op_time(spec[["to"]],   "restage$to",   tv, where, end = TRUE)
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
  wk    <- plan@time_col
  basis <- plan@time_basis
  ws    <- .plan_week_start(plan)
  ids <- if ("flight_id" %in% names(d)) unique(d[["flight_id"]][keep]) else NULL
  ids <- ids[!is.na(ids)]

  # Rows with no flight: move the period itself. The move has to land on the
  # plan's own calendar -- a week column shifted by three days no longer holds
  # week starts -- so what counts as a legal shift depends on the basis.
  plain <- keep & (if (length(ids)) !(d[["flight_id"]] %in% ids) else TRUE)
  plain[is.na(plain)] <- keep[is.na(plain)]
  if (any(plain)) {
    if (is.null(by)) {
      stop(where, "`restage` needs flights: row(s) matched here record no ",
           "flight, so they have no in-market dates to restage. Use `shift` to ",
           "move their periods, or `drop` and `add` to replace them.",
           call. = FALSE)
    }
    if (identical(basis, "week") && by %% 7L != 0L) {
      stop(where, "`shift` on rows that record no flight must be a whole ",
           "number of weeks (a multiple of 7); got ", by, ". Those rows are ",
           "keyed by week start, which a part-week shift would break.",
           call. = FALSE)
    }
    if (identical(basis, "month")) {
      stop(where, "this plan is keyed by month, so shifting its rows by days ",
           "would move them off month starts. Restage the flight, or `drop` ",
           "and `add` the rows.", call. = FALSE)
    }
    d[[wk]][plain] <- .shift_time(d[[wk]][plain], by)
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
         ". A plan holds one row per line item per period.", call. = FALSE)
  }
  d
}

.restage_one <- function(d, plan, id, by, from, to, ws, where) {
  wk    <- plan@time_col
  basis <- plan@time_basis
  i  <- which(d[["flight_id"]] == id)
  fs <- d[["flight_start"]][i][1]
  fe <- d[["flight_end"]][i][1]

  # `by` is whole days, in the flight column's own type; `from` and `to` have
  # already been read in the plan's frame by .apply_restage(), so a timed buy
  # can be restaged to a date and a dated one to a moment.
  new_fs <- if (is.null(by)) .align_time(from, fs)   else .shift_time(fs, by)
  new_fe <- if (is.null(by)) .align_time_end(to, fe) else .shift_time(fe, by)

  total <- sum(d[["planned_spend"]][i])
  sp    <- .spread_flight(new_fs, new_fe, total, basis, ws)

  # Per-period figures -- a hand-set shape, or spend bounds -- have nowhere to
  # land if the period structure changes. Carry them across when it maps 1:1,
  # and refuse otherwise rather than silently discarding the planner's work
  # or a commitment.
  custom  <- identical(d[["pacing"]][i][1], "custom")
  bounds  <- intersect(bound_cols(), names(d))
  bounded <- length(bounds) > 0 && any(!is.na(unlist(d[i, bounds])))
  old_ord <- order(.span_of(d, wk, basis)$start[i])
  # A timed buy is always one row, wherever it moves, so it always maps 1:1.
  check_structure <- (custom || bounded) && !identical(basis, "instant")
  if (check_structure) {
    old_days <- .row_days(d, wk, basis)[i][old_ord]
    new_days <- as.integer(pmin(.period_end(sp[["period"]], basis), new_fe) -
                             pmax(sp[["period"]], new_fs)) + 1L
    if (!identical(old_days, new_days)) {
      stop(where, "flight ", id, " is ",
           if (custom) "custom-paced" else "bound by min/max spend",
           ", and moving it there changes its period structure (",
           paste(old_days, collapse = "+"), " days becomes ",
           paste(new_days, collapse = "+"), "), so its per-period ",
           if (custom) "figures" else "bounds", " have nowhere to land. Move ",
           "it a whole number of periods, or ",
           if (custom) "re-shape it" else "clear its bounds with `rebound`",
           " first.", call. = FALSE)
    }
    sp[["planned_spend"]] <- d[["planned_spend"]][i][old_ord]
  }

  new <- .blank_rows(d, nrow(sp))
  for (nm in setdiff(names(d), c(wk, "planned_spend", "flight_start",
                                 "flight_end", bound_cols()))) {
    new[[nm]] <- d[[nm]][i][1]
  }
  new[[wk]]              <- sp[["period"]]
  new[["planned_spend"]] <- sp[["planned_spend"]]
  new[["flight_start"]]  <- new_fs
  new[["flight_end"]]    <- new_fe
  # Bounds move with their periods, in order; a flight with none keeps NA.
  if (bounded) for (b in bounds) new[[b]] <- d[[b]][i][old_ord]

  rbind(d[-i, , drop = FALSE], new)
}

# An allocation -- a data frame or named vector of absolute spend, typically an
# optimizer's output -- names each row's value outright, so a row it would put
# outside its bounds is refused. The fix is upstream: give the optimizer the
# bounds.
.set_allocation <- function(d, plan, idx, values) {
  .stop_if_outside_bounds(
    values, .lower_bounds(d)[idx], .upper_bounds(d)[idx],
    keys = line_item(d, plan@grain)[idx],
    what = "the allocation in `edits`"
  )
  d[["planned_spend"]][idx] <- values
  d
}

# Apply a canonical edits record (see .record_edits() in provenance.R) to the
# parent's data, returning the derived data frame.
#
# This is the ONLY way a scenario's data is made: build_scenario() records the
# edits and then replays that record, so replaying a stored @edits on its
# parent reproduces the scenario's @data exactly.
.replay <- function(parent, record) {
  d <- parent@data

  if (identical(record$form, "allocation")) {
    alloc <- record$data
    idx <- .allocation_rows(d, parent@grain, line_item(alloc, parent@grain))
    .stop_if_backed(parent, d, seq_len(nrow(d)) %in% idx)
    d <- .set_allocation(d, parent, idx, alloc[["planned_spend"]])
  } else {
    for (i in seq_along(record$ops)) {
      d <- .apply_op(d, parent, record$ops[[i]], i)
    }
  }

  # Every edit form funnels through here, so this is the one place the derived
  # facts can fall out of step with the money.
  #
  # .reunit() re-derives units from the new spend at the HELD rate: a cut budget
  # buys fewer impressions, it does not win a better CPM.
  # .repace() re-derives each flight's pacing; a flight is never broken by an
  # edit, only re-labelled "custom" when its shape no longer matches an even
  # spread.
  .repace(.reunit(d), parent@time_col, parent@time_basis)
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
#' Each op is `list(<exactly one operation>, <selection>)`, a plain list that
#' can be written by hand, built by an [op constructor][ops] such as
#' [op_scale()], or parsed from an agent's JSON tool call -- all three are the
#' same object. The constructors check an op where it is written;
#' [plan_ops_schema()] gives the same rules as a JSON Schema.
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
#'   \item{`transfer`}{Move this amount from the `from` cells to the `to`
#'     cells, leaving the plan's total unchanged. Takes `from` and `to` in
#'     place of `target`, and `from_during` / `to_during` to window one side.
#'     See [op_transfer()].}
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
#' `delta` is almost always the one you want when the budget itself changes:
#' distributing in proportion rather than evenly per cell preserves the
#' channel's flighting shape, so a flight stays evenly paced through it. When
#' money moves *between* line items -- "move 50k from TV to Social" -- reach for
#' `transfer`. It spreads each side the same way `delta` would, and keeps the
#' two halves of the move together as one op.
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
#' @section Spend bounds:
#' Rows may carry `min_spend` and `max_spend` ([bound_cols()]): an upfront
#' commitment, a partner floor, a cap. Every edit respects them.
#'
#' - `delta`, `total` and `transfer` spread a change across a group, and a row
#'   that reaches its bound **stops there** while the rest of the group takes
#'   up the slack. A cut to a channel with a committed line comes out of its
#'   other lines. Only when the group as a whole cannot absorb the change is
#'   the op refused, saying how much it could take.
#' - `set`, `scale`, `delta_each` and allocation edits name each row's value
#'   outright, so a row that would land outside its bounds is refused.
#' - `drop` refuses a row with a floor. `shift` and `restage` carry each
#'   period's bounds with it, and refuse a move that changes a bounded
#'   flight's period structure.
#'
#' Bounds change only through `rebound` ([op_rebound()]), never as a side
#' effect of moving money: to cut committed spend, lower the commitment and
#' then cut, in that order, in one edits list.
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
#' `@subplans` **carry**: the scenario is still a topline. Rows a subplan
#' backs are read-only, so an edit reaching one — including a whole-plan op
#' like `list(total = 200)` — errors naming the subplan to edit instead. See
#' [attach_subplan()]. `@approved_on` is cleared with the status: whether and
#' when the scenario is approved is its own business; see [revise()].
#'
#' `@edits` records exactly what was applied, in a canonical form: the ops
#' with their fields in a fixed order and dates as text on the plan's clock,
#' or the allocation as given. The scenario is derived by replaying that
#' record, so replaying it on the parent reproduces the scenario. `@rationale`
#' holds the `rationale` given here. Both belong to this derivation and are
#' never inherited; [edit_log()] lays them out across a set.
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
#' @param rationale Optional structured reasons for the derivation, kept as
#'   `@rationale` beside the `objective` headline: a named list with any of
#'   `author` (`"human"`, `"agent"` or `"optimizer"`), `goal` (text),
#'   `constraints_id` (the `@id` of the [PlanConstraints] it was checked
#'   against), `forecast` (a named list of numbers the caller supplies -- the
#'   package never computes them) and `notes` (text). Never inherited.
#' @param ... Unused; for method extension.
#' @return A new [MediaPlan] at the base plan's grain, with `@parent_id` set.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search", "Social"),
#'              planned_spend = c(80, 40, 40)),
#'   grain = "channel", time = "week", name = "base"
#' )
#'
#' # "Increase Search by 20%" — the caller states intent, R does the math
#' build_scenario(base, edits = op_scale(1.2, target = list(channel = "Search")),
#'                name = "Search +20%")
#'
#' # The same op written by hand, as an agent's JSON would arrive
#' build_scenario(base, edits = list(scale = 1.2,
#'                                   target = list(channel = "Search")),
#'                name = "Search +20%, by hand")
#'
#' # "Set the total budget to 200", holding the current mix
#' build_scenario(base, edits = op_total(200), name = "Budget 200")
#'
#' # "Move 10 from TV to Search" — budget-neutral however many rows each has
#' build_scenario(base, edits = op_transfer(10, from = list(channel = "TV"),
#'                                          to = list(channel = "Search")),
#'                name = "move 10")
#'
#' # Ops in a list apply in order
#' build_scenario(base, edits = list(
#'   op_transfer(10, from = list(channel = "TV"), to = list(channel = "Search")),
#'   op_scale(0.5, target = list(channel = "Social"))
#' ), name = "move 10, halve Social")
#'
#' # Absolute allocation (e.g. from mrmopt::opt_mix())
#' build_scenario(
#'   base,
#'   edits = data.frame(week = as.Date("2026-07-06"),
#'                      channel = c("TV", "Search"), planned_spend = c(50, 70)),
#'   name = "Optimized"
#' )
#'
#' # Terse single-cell override, keyed by line_item() at the full grain
#' build_scenario(base, edits = c("Search | 2026-07-06" = 120),
#'                name = "Search boost")
#'
#' # A plan can gain and lose line items
#' build_scenario(base, edits = op_add(channel = "Audio", week = "2026-07-06",
#'                                     planned_spend = 25),
#'                name = "add audio")
#' build_scenario(base, edits = op_drop(target = list(channel = "TV")),
#'                name = "no TV")
#' @export
build_scenario <- S7::new_generic("build_scenario", "plan",
  function(plan, edits, name, nickname = "", advertiser = NULL, planner = NULL,
           status = "in development", objective = "", rationale = list(),
           ...) S7::S7_dispatch())

S7::method(build_scenario, MediaPlan) <- function(plan, edits, name,
    nickname = "", advertiser = NULL, planner = NULL,
    status = "in development", objective = "", rationale = list(), ...) {
  if (missing(edits) || is.null(edits)) {
    stop("`edits` is required: supply a list of operations, a data frame ",
         "(grain columns + planned_spend), or a named numeric vector keyed ",
         "by line_item().", call. = FALSE)
  }
  if (missing(name) || !length(name) || is.na(name[1]) || !nzchar(name[1])) {
    stop("`name` is required: every scenario carries a formal name. Use ",
         "`nickname` for a short working handle.", call. = FALSE)
  }
  # Record the edits in canonical form, then derive the scenario by replaying
  # that record, so what is stored is exactly what was applied.
  record <- .record_edits(plan, edits)

  # Everything not named here is carried from the parent -- including its
  # subplans, whose rows the edit path refuses to touch, so the scenario is
  # still a valid topline.
  .copy_plan(
    plan,
    data       = .replay(plan, record),
    id         = new_id("plan"),
    parent_id  = plan@id,
    name       = name,
    nickname   = nickname,
    # Inherited: these describe the engagement, not the scenario.
    advertiser = advertiser %||% plan@advertiser,
    planner    = planner %||% plan@planner,
    # NOT inherited: a derivative of an approved plan is not itself approved,
    # and has no approval date.
    status      = .normalise_status(status),
    approved_on = as.Date(character(0)),
    objective  = objective,
    # Provenance: this scenario's own edits and reasons, never the parent's.
    edits      = record,
    rationale  = .as_rationale(rationale)
  )
}
