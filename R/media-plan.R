#' Line item identifier for each row
#'
#' Collapses the given columns into a single character vector of line item
#' identifiers, one per row. A **line item** is a specific combination of the
#' plan's descriptive dimensions — channel, partner, tactic — and is how the
#' package identifies what a row is buying. This is what the decomp constrains
#' and what response models attach to.
#'
#' At a weekly grain a row is a line item *for a given week*, so pass
#' [line_item_grain()] to identify the line item independent of time, or the
#' full `@grain` to identify the row.
#'
#' @param df A data frame containing the columns.
#' @param cols Character vector of column names to combine.
#' @param sep Separator between parts. Default `" | "`.
#' @return A character vector of identifiers, length `nrow(df)`.
#' @examples
#' d <- data.frame(channel = c("TV", "TV"), partner = c("NBC", "ESPN"))
#' line_item(d, c("channel", "partner"))
#' @export
line_item <- function(df, cols, sep = " | ") {
  if (length(cols) == 0) {
    stop("`cols` must name at least one column.", call. = FALSE)
  }
  missing <- setdiff(cols, names(df))
  if (length(missing)) {
    stop("column(s) not found: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  parts <- lapply(cols, function(g) as.character(df[[g]]))
  do.call(paste, c(parts, list(sep = sep)))
}

#' The grain columns that identify a line item, excluding the week
#'
#' A plan's `@grain` describes a row. When the plan has a week column, a row is
#' a line item *per week*; this drops the week so what remains identifies the
#' line item itself — the level the decomp constrains and response models are
#' fitted at.
#'
#' @param plan A [MediaPlan].
#' @return Character vector of grain columns excluding `@week_col`.
#' @export
line_item_grain <- function(plan) {
  setdiff(plan@grain, plan@week_col)
}

#' The allowed plan workflow states
#'
#' `@status` tracks where a plan sits in the review workflow. The set is fixed
#' so that typos error rather than creating a silent fourth state, and so a UI
#' can build its dropdown from one source of truth. `""` means unset.
#'
#' @return A character vector of the valid, canonical status values.
#' @examples
#' status_levels()
#' @export
status_levels <- function() {
  c("in development", "to review", "approved")
}

# Internal: normalise user-supplied status to canonical form, or error.
.normalise_status <- function(status) {
  if (is.null(status) || !length(status)) return("")
  status <- trimws(tolower(as.character(status)[1]))
  if (!nzchar(status)) return("")
  if (!status %in% status_levels()) {
    stop("`status` must be one of: ",
         paste(status_levels(), collapse = ", "),
         " (or \"\" for unset); got \"", status, "\".", call. = FALSE)
  }
  status
}

#' A media plan at a configurable grain
#'
#' `MediaPlan` is a typed wrapper around a flat plan table. `@data` is a plain,
#' directly accessible data frame of the grain columns plus a `planned_spend` column;
#' the class adds a validator, a synthetic identity (`@id`), and lineage
#' (`@parent_id`).
#'
#' A plan holds **planned values only** — `planned_spend` is what was intended
#' for a row, including for weeks that have already passed. It is never what
#' actually happened; actualised spend and attributed KPI live in the decomp.
#'
#' A plan on its own is therefore **blind to past and future**. "Historical",
#' "future", under-delivery and over-delivery are not properties of a plan: they
#' only exist for a *pairing* of a plan with a decomp that reports actuals
#' through a given date. That is why no through-date is stored here, and why
#' editing a row for a past week is a perfectly ordinary thing to do — you are
#' revising what was planned, and the plan cannot know that week has passed.
#' See [check_coverage()] for the one pairing operation the package provides.
#'
#' Any other columns on the supplied data frame are carried through untouched.
#'
#' Construct one with [media_plan_from_df()] rather than calling the constructor
#' directly.
#'
#' @param data A data frame with the grain columns + `planned_spend`. One row per grain
#'   cell.
#' @param grain Character vector naming the columns that identify a row. When
#'   the plan is weekly this includes the week column.
#' @param week_col Optional name of the week column within `@grain`. Must hold
#'   `Date` values (the week start). Empty means the plan has no time dimension.
#' @param id Opaque synthetic id (identity/lineage only).
#' @param parent_id Id of the plan this one was derived from; empty for a root
#'   plan.
#' @param name Formal plan name. **Required** — every plan is named.
#' @param nickname Optional short working handle, e.g. `"aggressive TV"`. Used
#'   in preference to `@name` when labelling scenarios, so a set of in-progress
#'   scenarios reads well without renaming the formal plan.
#' @param advertiser Optional advertiser / client this plan belongs to.
#' @param planner Optional person responsible for the plan.
#' @param status Optional workflow state; one of [status_levels()], or `""` when
#'   unset.
#' @param objective Human-facing objective / notes.
#' @param revision Integer revision number, default `1`. Set by [revise()];
#'   never bumped automatically. Printed as `Rev 2` when above 1.
#' @param subplans Named list of `MediaPlan`s, one per parent line item they
#'   back. Populate through [attach_subplan()], not by hand: attaching
#'   recomputes the parent's rows for that cell and the validator refuses a
#'   subplan whose rollup the parent's rows do not match.
#' @section Derived properties:
#' `@flight_start`, `@flight_end` and `@flight_days` are computed from `@data`
#' on every read and cannot be assigned. They describe the plan's own extent —
#' the dates it has line items for — and so are true of the plan alone. See
#' [flight_window()] for why that is a different thing from the decomp
#' through-date [check_coverage()] takes, and why only one of the two can live
#' on a plan.
#' @return A `MediaPlan` S7 object.
#' @export
MediaPlan <- S7::new_class(
  "MediaPlan",
  properties = list(
    data      = S7::new_property(S7::class_data.frame, default = quote(data.frame())),
    grain     = S7::new_property(S7::class_character, default = character(0)),
    week_col  = S7::new_property(S7::class_character, default = character(0)),
    id        = S7::new_property(S7::class_character, default = quote(new_id("plan"))),
    parent_id = S7::new_property(S7::class_character, default = character(0)),
    name       = S7::new_property(S7::class_character, default = ""),
    nickname   = S7::new_property(S7::class_character, default = ""),
    advertiser = S7::new_property(S7::class_character, default = ""),
    planner    = S7::new_property(S7::class_character, default = ""),
    status     = S7::new_property(S7::class_character, default = ""),
    objective  = S7::new_property(S7::class_character, default = ""),

    # Planners say "Rev 2". Manual, never auto-bumped: revise() sets it, and
    # anything that mints a new @id starts again at 1.
    revision   = S7::new_property(S7::class_integer, default = 1L),

    # Subplans: a named list of MediaPlans, keyed by the parent line item each
    # one backs (line_item(@data, line_item_grain(self)) -- "TV", "TV | NBC").
    # Composition, not inheritance: a subplan is an ordinary plan, and what
    # changes is the PARENT's behaviour. Its rows for that cell are the
    # subplan's rollup and are read-only. See ?attach_subplan.
    subplans   = S7::new_property(S7::class_list, default = quote(list())),

    # Derived, never stored: getter properties are read-only, so these cannot
    # drift from @data. S7 does not enforce the declared class on a getter's
    # return value, so each one is responsible for its own type -- hence the
    # explicit length-0 Date / integer for "the plan has no time dimension".
    flight_start = S7::new_property(S7::class_Date, getter = function(self) {
      w <- flight_window(self)
      if (length(w)) unname(w[["start"]]) else as.Date(character(0))
    }),
    flight_end = S7::new_property(S7::class_Date, getter = function(self) {
      w <- flight_window(self)
      if (length(w)) unname(w[["end"]]) else as.Date(character(0))
    }),
    flight_days = S7::new_property(S7::class_integer, getter = function(self) {
      .flight_days(self)
    })
  ),
  validator = function(self) {
    d <- self@data
    g <- self@grain
    errs <- character(0)

    if (length(g) < 1) {
      errs <- c(errs, "@grain must name at least one column.")
    }
    miss <- setdiff(g, names(d))
    if (length(miss)) {
      errs <- c(errs, paste0("grain column(s) not in @data: ",
                             paste(miss, collapse = ", ")))
    }

    if (!"planned_spend" %in% names(d)) {
      errs <- c(errs, "@data must contain a 'planned_spend' column.")
    } else {
      sp <- d[["planned_spend"]]
      if (!is.numeric(sp)) {
        errs <- c(errs, "'planned_spend' must be numeric.")
      } else if (anyNA(sp)) {
        errs <- c(errs, "'planned_spend' must not contain NA.")
      } else if (any(sp < 0)) {
        errs <- c(errs, "'planned_spend' must be non-negative.")
      }
    }

    if (length(self@week_col)) {
      if (length(self@week_col) != 1) {
        errs <- c(errs, "@week_col must name a single column.")
      } else if (!self@week_col %in% g) {
        errs <- c(errs, paste0("@week_col '", self@week_col,
                               "' must be one of the @grain columns."))
      } else if (self@week_col %in% names(d) && !inherits(d[[self@week_col]], "Date")) {
        errs <- c(errs, paste0("week column '", self@week_col,
                               "' must hold Date values (the week start)."))
      }
    }

    # Flighting and unit columns ride along: checked, never part of the key. A
    # plan that records neither skips all of this.
    errs <- c(errs, .validate_flight_cols(d))
    if (!length(errs)) errs <- c(errs, .validate_unit_cols(d))

    # One row per grain cell.
    if (length(miss) == 0 && length(g) >= 1 && nrow(d) > 0) {
      k <- line_item(d, g)
      if (anyDuplicated(k)) {
        dups <- unique(k[duplicated(k)])
        errs <- c(errs, paste0(
          "@data has duplicate rows at grain (", paste(g, collapse = ", "),
          "): ", paste(utils::head(dups, 5), collapse = "; "),
          ". One row per grain cell is required."))
      }
    }

    if (length(self@id) != 1 || is.na(self@id) || !nzchar(self@id)) {
      errs <- c(errs, "@id must be a single non-empty string.")
    }

    if (length(self@name) != 1 || is.na(self@name) || !nzchar(self@name)) {
      errs <- c(errs, "@name is required: every plan must carry a formal name.")
    }

    for (fld in c("nickname", "advertiser", "planner", "status")) {
      v <- S7::prop(self, fld)
      if (length(v) > 1) {
        errs <- c(errs, paste0("@", fld, " must be a single string."))
      }
    }

    if (length(self@status) == 1 && nzchar(self@status) &&
        !self@status %in% status_levels()) {
      errs <- c(errs, paste0("@status must be one of: ",
                             paste(status_levels(), collapse = ", "),
                             " (or \"\" for unset)."))
    }

    if (length(self@revision) != 1 || is.na(self@revision) ||
        self@revision < 1L) {
      errs <- c(errs, "@revision must be a single positive integer.")
    }

    # Only when the table itself is sound: the subplan invariant compares
    # rows against rollups, which is meaningless on a malformed table.
    if (!length(errs)) errs <- c(errs, .validate_subplans(self))

    if (length(errs)) errs else NULL
  }
)

# Internal: the label to use for a plan in a scenario set -- the working handle
# if there is one, otherwise the formal name.
.plan_label <- function(plan) {
  if (length(plan@nickname) && nzchar(plan@nickname)) plan@nickname else plan@name
}

#' Check a plan against a decomp (the one pairing operation)
#'
#' A plan on its own holds intent and is blind to what has already happened.
#' Pair it with a decomp — which reports actualised spend and attributed KPI
#' through a date — and questions about history become answerable. This is the
#' first of those: **does the plan account for everything the model measured?**
#'
#' Every line item in `decomp` should appear in the plan rows dated before
#' `through`. Missing ones are reported. Line items the plan has and the decomp
#' does not are *never* flagged: the future portion is expected to introduce new
#' partners and tactics, and the historical portion may carry line items the
#' decomp never modelled.
#'
#' This **warns rather than errors**. Both artifacts are individually valid; it
#' is their pairing that disagrees, so an app should surface the mismatch and
#' let the user resolve it, not refuse to load the plan.
#'
#' @param plan A [MediaPlan].
#' @section What `through` compares against:
#' A row is in scope when **any part of its in-market period falls before**
#' `through` — overlap, not containment. A decomp reporting through a Wednesday
#' has measured part of the week that began on the Monday, so that line item
#' should be expected in the plan.
#'
#' The comparison is against the row's period from [flight_window()]'s
#' machinery, not the bare week value, so it is right for a flight that starts
#' or ends mid-week: a buy whose flight begins on the Wednesday is *not* in
#' scope for a decomp reporting through the Tuesday, even though its week
#' started on the Monday.
#'
#' One consequence is worth stating rather than discovering. A long flight that
#' began the day before `through` is in scope on the strength of a single
#' measured day. That is deliberate — the decomp saw part of it, so the line
#' item should appear in the plan — but it means being in scope says nothing
#' about *how much* of a buy the decomp measured.
#'
#' @param decomp A data frame of the decomp's line items. May name any subset of
#'   [line_item_grain()] — a channel-only decomp checks channels and ignores
#'   partners.
#' @param through Optional `Date`. Restricts the check to plan rows in market
#'   before that date; see *What `through` compares against*. Without it, or on
#'   a plan with no time dimension, the whole plan is considered.
#' @return Invisibly, a character vector of the decomp line items missing from
#'   the plan — empty when coverage is complete. Returned so a UI can render
#'   them; the warning is for interactive use.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "Q3 plan"
#' )
#' check_coverage(p, data.frame(channel = c("TV", "Search")))
#' @export
check_coverage <- function(plan, decomp, through = NULL) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  if (!is.data.frame(decomp)) {
    stop("`decomp` must be a data frame of line item columns.", call. = FALSE)
  }

  li_grain <- line_item_grain(plan)
  cols <- intersect(names(decomp), li_grain)
  if (!length(cols)) {
    warning("`decomp` shares no line item columns with the plan's line item ",
            "grain (", paste(li_grain, collapse = ", "), "); not checked.",
            call. = FALSE)
    return(invisible(character(0)))
  }

  d <- plan@data
  if (!is.null(through)) {
    through <- as.Date(through)
    if (is.na(through)) stop("`through` must be a Date.", call. = FALSE)

    # Scope by OVERLAP, through the same .row_span() every other date question
    # uses: a row is in scope when any part of its in-market period falls before
    # `through`. A decomp reporting through Wednesday has measured part of the
    # week that began on Monday, so that line item should be expected in the
    # plan. Comparing against the week start alone happened to give this answer
    # for weekly rows, but not for a flight that starts mid-week.
    span <- .row_span(plan)
    if (is.null(span)) {
      warning("`through` was supplied but the plan has no time dimension; ",
              "checking the whole plan.", call. = FALSE)
    } else {
      d <- d[!is.na(span$start) & span$start < through, , drop = FALSE]
      if (!nrow(d)) {
        warning("no plan rows are in market before ", format(through),
                "; not checked.", call. = FALSE)
        return(invisible(character(0)))
      }
    }
  }

  missing <- setdiff(unique(line_item(decomp, cols)), unique(line_item(d, cols)))
  if (length(missing)) {
    warning("the plan is missing ", length(missing),
            " line item(s) present in the decomp: ",
            paste(utils::head(missing, 8), collapse = "; "),
            if (length(missing) > 8) paste0(" (+", length(missing) - 8, " more)") else "",
            call. = FALSE)
  }
  invisible(missing)
}

#' Build a validated media plan from a data frame
#'
#' The primary entry point for turning an uploaded plan into a [MediaPlan].
#' Normalises the spend column name to `planned_spend`, coerces the week column
#' to `Date`, and runs the full validator on construction.
#'
#' It knows nothing about decomps: a plan is constructed from the plan alone.
#' To check a plan against a decomp, call [check_coverage()] — which can then be
#' re-run whenever the decomp refreshes, without rebuilding the plan.
#'
#' @param df A data frame holding the plan: grain columns plus a spend column.
#'   All other columns are preserved on `@data` untouched.
#' @param grain Character vector naming the columns that identify a row,
#'   including the week column when the plan is weekly.
#' @param week Optional name of the week column. Must be among `grain`. Values
#'   are coerced to `Date` (the week start).
#' @param planned_spend Name of the planned-spend column in `df`. Renamed to
#'   `planned_spend`. Holds intent on every row, including past weeks. Default
#'   `"planned_spend"`.
#' @param planned_units,planned_rate,unit_type Optional names of the columns
#'   recording what the line item buys: how much of it, at what price, and of
#'   what (`"impression"`, `"click"`, `"grp"`, ...). Renamed to the canonical
#'   names. The three quantities are bound by
#'   `planned_spend = planned_units * planned_rate / rate_per(unit_type)`, where
#'   `rate_per` is 1000 for impressions and 1 otherwise, so **supply any two and
#'   the third is computed** — a budget and a negotiated CPM give the
#'   impressions, a delivery goal and a rate give the budget. See
#'   [cost_per_unit()] and [unit_type_levels()].
#' @param name Formal plan name. **Required** — every plan carries one.
#' @param nickname Optional short working handle used in preference to `name`
#'   when labelling scenarios.
#' @param advertiser Optional advertiser / client.
#' @param planner Optional person responsible.
#' @param status Optional workflow state; one of [status_levels()] (matched
#'   case-insensitively) or `""` when unset.
#' @param objective Human-facing objective / notes.
#' @param id Optional explicit id; generated when `NULL`.
#' @param parent_id Optional parent id for lineage.
#' @param revision Integer revision number; default `1`. See [revise()].
#' @return A validated [MediaPlan].
#' @examples
#' df <- data.frame(
#'   channel = c("TV", "Search", "Social"),
#'   planned_spend = c(100, 80, 60)
#' )
#' media_plan_from_df(df, grain = "channel", name = "Q3 plan",
#'                    advertiser = "Acme", status = "in development")
#' @export
media_plan_from_df <- function(df, grain, week = NULL,
                               planned_spend = "planned_spend",
                               planned_units = NULL, planned_rate = NULL,
                               unit_type = NULL,
                               name, nickname = "", advertiser = "",
                               planner = "", status = "", objective = "",
                               id = NULL, parent_id = character(0),
                               revision = 1L) {
  if (missing(name) || !length(name) || is.na(name[1]) || !nzchar(name[1])) {
    stop("`name` is required: every plan carries a formal name. Use ",
         "`nickname` for a short working handle.", call. = FALSE)
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)

  df <- .rename_col(df, planned_units, "planned_units")
  df <- .rename_col(df, planned_rate,  "planned_rate")
  df <- .rename_col(df, unit_type,     "unit_type")

  # Spend is optional only when units and a rate can produce it.
  spend_given <- planned_spend %in% names(df)
  if (!spend_given &&
      !all(c("planned_units", "planned_rate") %in% names(df))) {
    stop("planned-spend column '", planned_spend, "' not found in `df`. ",
         "Supply it, or supply planned_units and planned_rate so it can be ",
         "computed.", call. = FALSE)
  }
  if (spend_given && planned_spend != "planned_spend") {
    if ("planned_spend" %in% names(df)) df[["planned_spend"]] <- NULL
    names(df)[names(df) == planned_spend] <- "planned_spend"
  }
  df <- .complete_trio(df)

  miss <- setdiff(grain, names(df))
  if (length(miss)) {
    stop("grain column(s) not found in `df`: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }

  week_col <- character(0)
  if (!is.null(week)) {
    if (length(week) != 1 || !week %in% grain) {
      stop("`week` must name a single column that is part of `grain` (",
           paste(grain, collapse = ", "), ").", call. = FALSE)
    }
    if (!inherits(df[[week]], "Date")) {
      # as.Date() *errors* on unparseable strings rather than returning NA.
      converted <- suppressWarnings(
        tryCatch(as.Date(df[[week]]),
                 error = function(e) rep(NA, nrow(df)))
      )
      if (anyNA(converted)) {
        stop("week column '", week, "' could not be coerced to Date. Supply ",
             "Date values or ISO-8601 strings (the week start).", call. = FALSE)
      }
      df[[week]] <- converted
    }
    week_col <- week
  }

  MediaPlan(
    data       = df,
    grain      = grain,
    week_col   = week_col,
    id         = id %||% new_id("plan"),
    parent_id  = parent_id,
    name       = name,
    nickname   = nickname,
    advertiser = advertiser,
    planner    = planner,
    status     = .normalise_status(status),
    objective  = objective,
    revision   = .as_revision(revision)
  )
}

# Coerce a user-supplied revision to a single integer, or error.
.as_revision <- function(revision) {
  r <- suppressWarnings(as.integer(revision))
  if (length(r) != 1L || is.na(r) || r < 1L || !isTRUE(all.equal(r, revision))) {
    stop("`revision` must be a single positive whole number.", call. = FALSE)
  }
  r
}

#' Roll a plan up to a coarser grain
#'
#' Aggregates `planned_spend` to a subset of the plan's grain, returning a new
#' [MediaPlan] with `@parent_id` set. Use it to find the nearest level at which
#' a response model exists: a new partner with no model of its own rolls up to
#' its channel, which has one.
#'
#' Treat `@grain` as an ordered nesting (channel, then partner, then tactic), so
#' "the next coarsest level" means dropping the rightmost column.
#'
#' @param plan A [MediaPlan].
#' @param grain Character vector; a subset of `plan@grain` to aggregate to.
#' @param name Optional name for the resulting plan; defaults to the source
#'   plan's name, since a rollup is the same plan viewed at a coarser grain.
#' @return A new [MediaPlan] at the coarser grain. Any subplans are dropped:
#'   a rollup is a coarser *view*, and the cells they backed may no longer
#'   exist at the new grain.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("TV", "TV", "Search"),
#'              partner = c("NBC", "ESPN", "Google"),
#'              planned_spend = c(30, 20, 50)),
#'   grain = c("channel", "partner"), name = "Q3 plan"
#' )
#' roll_up(p, "channel")@data
#' @export
roll_up <- function(plan, grain, name = NULL) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  extra <- setdiff(grain, plan@grain)
  if (length(extra)) {
    stop("`grain` must be a subset of the plan grain (",
         paste(plan@grain, collapse = ", "), "); not in it: ",
         paste(extra, collapse = ", "), call. = FALSE)
  }
  if (!length(grain)) {
    stop("`grain` must name at least one column.", call. = FALSE)
  }

  out <- .aggregate_to(plan@data, grain)

  # A rollup is a coarser VIEW, so it drops the subplans: the cells they back
  # may not exist at the new grain, and a view does not own anything. A new id
  # starts the revision count over.
  .copy_plan(
    plan,
    data      = out,
    grain     = grain,
    week_col  = intersect(plan@week_col, grain),
    id        = new_id("plan"),
    parent_id = plan@id,
    name      = name %||% plan@name,
    revision  = 1L,
    subplans  = list()
  )
}

#' Revise a plan's metadata without changing what it plans
#'
#' The metadata-only edit verb. Changes any of `name`, `nickname`,
#' `advertiser`, `planner`, `status`, `objective` and `revision`, and leaves
#' everything else — `@data`, `@grain`, `@id`, `@parent_id`, `@subplans` —
#' exactly as it was. Because `@id` is kept, the result is *the same plan*,
#' revised, rather than a derivative of it; that is the difference from
#' [build_scenario()], which mints a new id and lineage.
#'
#' This exists so that a consumer never has to rebuild a plan by naming its
#' slots by hand — the habit that silently drops any slot added later. Use
#' `revise()` for metadata, [build_scenario()] for spend, and
#' [attach_subplan()] / [detach_subplan()] for structure.
#'
#' `@revision` is never bumped automatically. Planners say *Rev 2* when they
#' mean it, so it is set here explicitly. It prints in the header once above 1.
#'
#' @param plan A [MediaPlan].
#' @param ... Named metadata fields to change: `name`, `nickname`,
#'   `advertiser`, `planner`, `status`, `objective`, `revision`. At least one.
#' @return The same plan (same `@id`) with the named fields changed.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "Q3 plan"
#' )
#' q <- revise(p, status = "approved", revision = 2)
#' identical(q@id, p@id)
#' q@revision
#' @export
revise <- function(plan, ...) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  changes <- list(...)
  allowed <- c("name", "nickname", "advertiser", "planner", "status",
               "objective", "revision")
  if (!length(changes)) {
    stop("nothing to revise: name at least one of ",
         paste(allowed, collapse = ", "), ".", call. = FALSE)
  }
  if (is.null(names(changes)) || any(!nzchar(names(changes)))) {
    stop("`revise()` takes named arguments only (", paste(allowed, collapse = ", "),
         ").", call. = FALSE)
  }
  bad <- setdiff(names(changes), allowed)
  if (length(bad)) {
    stop("`revise()` changes metadata only; cannot set: ",
         paste(bad, collapse = ", "), ". Allowed: ",
         paste(allowed, collapse = ", "), ". Use build_scenario() to change ",
         "spend and attach_subplan() / detach_subplan() to change structure.",
         call. = FALSE)
  }
  if ("status"   %in% names(changes)) changes$status   <- .normalise_status(changes$status)
  if ("revision" %in% names(changes)) changes$revision <- .as_revision(changes$revision)
  do.call(.copy_plan, c(list(plan), changes))
}
