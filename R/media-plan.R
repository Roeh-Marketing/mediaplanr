#' Line item identifier for each row
#'
#' Collapses the given columns into a single character vector of line item
#' identifiers, one per row. A **line item** is a specific combination of the
#' plan's descriptive dimensions — channel, partner, tactic — and is how the
#' package identifies what a row is buying. This is what the decomp constrains
#' and what response models attach to.
#'
#' Every plan is keyed by time, so a row is a line item *for one period* —
#' a week, a day, a month, a moment. Pass [line_item_grain()] to identify the
#' line item independent of time, or the full `@grain` to identify the row.
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

#' The grain columns that identify a line item, excluding time
#'
#' A plan's `@grain` describes a row, and every plan is keyed by time, so a row
#' is a line item *for one period*. This drops `@time_col`, leaving the columns
#' that identify the line item itself — the level the decomp constrains and
#' response models are fitted at.
#'
#' @param plan A [MediaPlan].
#' @return Character vector of grain columns excluding `@time_col`.
#' @export
line_item_grain <- function(plan) {
  setdiff(plan@grain, plan@time_col)
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
#' Every plan is keyed by time. `@time_col` is required and `@time_basis` says
#' what one of its values covers — a day, a week, a month, or a moment for a
#' buy placed at a specific time. Those two are what a row's in-market period is
#' derived from, so nothing in the package has to assume a week. See
#' [time_basis_levels()].
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
#' @param grain Character vector naming the columns that identify a row. It
#'   always ends with `@time_col`, which the constructors append for you — a
#'   caller names the line item columns and the time column separately.
#' @param time_col Name of the plan's time column, part of `@grain`.
#'   **Required**: every plan is planned against a calendar. Holds `Date`
#'   values (the first day of the period) or `POSIXct` moments.
#' @param time_basis What one value of `@time_col` stands for; one of
#'   [time_basis_levels()]. `"day"`, `"week"` and `"month"` go with a `Date`
#'   column, `"instant"` with a `POSIXct` one.
#' @param tz The plan's timezone: the clock its times are stated on, as an
#'   Olson name (`"America/New_York"`, `"UTC"`). It is the plan's own property
#'   rather than a detail of whichever column happens to hold a moment, so a
#'   time given to an edit is read on the plan's clock wherever the code runs.
#'   `""` means unstated, and then the session's zone decides — which is the
#'   ambiguity worth removing. Only moments have a clock, so this has no effect
#'   on a plan keyed by day, week or month.
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
#' @param approved_on The date the plan was approved: a single `Date`, or
#'   empty when unset. Only an approved plan may carry one, and even then it
#'   is optional -- it is never defaulted to today. A plan's *revision* is not
#'   stored: it is its place among the approved plans in its lineage; see
#'   [lineage()].
#' @param subplans Named list of `MediaPlan`s, one per parent line item they
#'   back. Populate through [attach_subplan()], not by hand: attaching
#'   recomputes the parent's rows for that cell and the validator refuses a
#'   subplan whose rollup the parent's rows do not match.
#' @param edits The edits that derived this plan from `parent_id`, as
#'   [build_scenario()] recorded them; empty for a root. Replaying them on the
#'   parent reproduces `data` exactly. See [edit_log()].
#' @param rationale Why this plan was derived: a named list with any of
#'   `author` (`"human"`, `"agent"` or `"optimizer"`), `goal`,
#'   `constraints_id`, `forecast` (a named list of numbers the caller
#'   supplies) and `notes`. Empty when unstated. Set through
#'   [build_scenario()] or [revise()].
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
    time_col  = S7::new_property(S7::class_character, default = character(0)),
    time_basis = S7::new_property(S7::class_character, default = "week"),
    tz        = S7::new_property(S7::class_character, default = ""),
    id        = S7::new_property(S7::class_character, default = quote(new_id("plan"))),
    parent_id = S7::new_property(S7::class_character, default = character(0)),
    name       = S7::new_property(S7::class_character, default = ""),
    nickname   = S7::new_property(S7::class_character, default = ""),
    advertiser = S7::new_property(S7::class_character, default = ""),
    planner    = S7::new_property(S7::class_character, default = ""),
    status     = S7::new_property(S7::class_character, default = ""),
    objective  = S7::new_property(S7::class_character, default = ""),

    # The date the plan was approved, when it is and someone said when. Empty
    # otherwise -- never defaulted from Sys.Date(). "Rev 2" is not stored: a
    # plan's revision is its place among the approved plans in its lineage,
    # which lineage() derives.
    approved_on = S7::new_property(S7::class_Date,
                                   default = quote(as.Date(character(0)))),

    # Subplans: a named list of MediaPlans, keyed by the parent line item each
    # one backs (line_item(@data, line_item_grain(self)) -- "TV", "TV | NBC").
    # Composition, not inheritance: a subplan is an ordinary plan, and what
    # changes is the PARENT's behaviour. Its rows for that cell are the
    # subplan's rollup and are read-only. See ?attach_subplan.
    subplans   = S7::new_property(S7::class_list, default = quote(list())),

    # Provenance: how this plan was derived from @parent_id, and why. @edits
    # is the canonical record build_scenario() applied -- replaying it on the
    # parent reproduces @data exactly. @rationale is the structured reason
    # beside @objective's headline. Both empty on a root. See ?edit_log.
    edits      = S7::new_property(S7::class_list, default = quote(list())),
    rationale  = S7::new_property(S7::class_list, default = quote(list())),

    # Derived, never stored: getter properties are read-only, so these cannot
    # drift from @data. Their type is the time column's -- Dates on most plans,
    # moments on a plan of spots -- so they are declared class_any and each one
    # is responsible for returning the right thing, including for the empty
    # case, where the type still has to be right for a caller that stores it.
    flight_start = S7::new_property(S7::class_any, getter = function(self) {
      w <- flight_window(self)
      if (length(w)) unname(w[["start"]]) else w
    }),
    flight_end = S7::new_property(S7::class_any, getter = function(self) {
      w <- flight_window(self)
      if (length(w)) unname(w[["end"]]) else w
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

    # Time is not optional. A plan that does not say when it runs cannot be
    # paced, put on a calendar, or checked against a decomp, and every verb in
    # the package would need a second code path to pretend otherwise.
    tc   <- self@time_col
    type <- NA_character_
    if (length(tc) != 1 || is.na(tc) || !nzchar(tc)) {
      errs <- c(errs, paste0(
        "@time_col is required: every plan names the column it is planned ",
        "against."))
    } else if (!tc %in% g) {
      errs <- c(errs, paste0("@time_col '", tc,
                             "' must be one of the @grain columns."))
    } else if (tc %in% names(d)) {
      type <- .time_type(d[[tc]])
      if (is.na(type)) {
        errs <- c(errs, paste0(
          "time column '", tc, "' must hold Date values (the first day of the ",
          "period) or POSIXct moments."))
      }
    }

    if (length(tc) == 1 && !is.na(tc) && nzchar(tc) &&
        !length(setdiff(g, tc))) {
      errs <- c(errs, paste0(
        "@grain is only the time column: name at least one line item column ",
        "(channel, partner, tactic) as well."))
    }

    # The zone is the plan's, and the column is displayed on it: keeping the
    # two equal is what lets every other function read the clock off either.
    z <- self@tz
    if (length(z) != 1 || is.na(z)) {
      errs <- c(errs, "@tz must be a single string (\"\" when unstated).")
    } else if (!.valid_tz(z)) {
      errs <- c(errs, paste0("@tz '", z, "' is not a timezone this platform ",
                             "knows; see OlsonNames()."))
    } else if (identical(type, "datetime") && !identical(.tz_of(d[[tc]]), z)) {
      errs <- c(errs, paste0(
        "time column '", tc, "' is displayed in '", .tz_of(d[[tc]]),
        "' but @tz is '", z, "'. Build the plan through media_plan_from_df(), ",
        "which puts the column on the plan's clock."))
    }

    tb <- self@time_basis
    if (length(tb) != 1 || is.na(tb) || !tb %in% time_basis_levels()) {
      errs <- c(errs, paste0("@time_basis must be one of: ",
                             paste(time_basis_levels(), collapse = ", "), "."))
    } else if (!is.na(type) && !tb %in% .bases_for_type(type)) {
      errs <- c(errs, if (identical(type, "datetime")) {
        paste0("'", tc, "' holds POSIXct moments, so @time_basis must be ",
               "\"instant\"; got \"", tb, "\".")
      } else {
        paste0("@time_basis \"instant\" needs a POSIXct time column; '", tc,
               "' holds Dates. Use one of: ",
               paste(.bases_for_type("date"), collapse = ", "), ".")
      })
    }

    # Flighting, unit and bound columns ride along: checked, never part of the
    # key. A plan that records none of them skips all of this. Flight dates are
    # compared against the time column, so they are held to its type.
    errs <- c(errs, .validate_flight_cols(d, type))
    if (!length(errs)) errs <- c(errs, .validate_unit_cols(d))
    if (!length(errs)) errs <- c(errs, .validate_bound_cols(d, line_item(d, g)))

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

    # Only an approved plan has an approval date. revise() clears it when the
    # status moves on; this is the backstop.
    a <- self@approved_on
    if (length(a) > 1L || anyNA(a)) {
      errs <- c(errs, "@approved_on must be a single date, or empty when unset.")
    } else if (length(a) == 1L && !identical(self@status, "approved")) {
      errs <- c(errs, paste0(
        "@approved_on is set but @status is \"", self@status, "\": only an ",
        "approved plan has an approval date. Use revise(status = \"approved\", ",
        "approved_on = ).")
      )
    }

    errs <- c(errs, .validate_edits(self@edits, self@parent_id),
              .validate_rationale(self@rationale))

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
#' @param through Optional `Date` (or `POSIXct`, on a plan keyed by moments).
#'   Restricts the check to plan rows in market before it; see *What `through`
#'   compares against*. Without it the whole plan is considered.
#' @return Invisibly, a character vector of the decomp line items missing from
#'   the plan — empty when coverage is complete. Returned so a UI can render
#'   them; the warning is for interactive use.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", time = "week", name = "Q3 plan"
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
    through <- .align_time(.as_time_col(through, "through"), d[[plan@time_col]])
    if (!length(through) || is.na(through[1])) {
      stop("`through` must be a Date or a moment.", call. = FALSE)
    }
    through <- through[1]

    # Scope by OVERLAP, through the same .row_span() every other date question
    # uses: a row is in scope when any part of its in-market period falls before
    # `through`. A decomp reporting through Wednesday has measured part of the
    # week that began on Monday, so that line item should be expected in the
    # plan. Comparing against the week start alone happened to give this answer
    # for weekly rows, but not for a flight that starts mid-week.
    span <- .row_span(plan)
    d <- d[!is.na(span$start) & span$start < through, , drop = FALSE]
    if (!nrow(d)) {
      warning("no plan rows are in market before ", format(through),
              "; not checked.", call. = FALSE)
      return(invisible(character(0)))
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
#' Normalises the spend column name to `planned_spend`, reads the time column
#' and appends it to the grain, and runs the full validator on construction.
#'
#' It knows nothing about decomps: a plan is constructed from the plan alone.
#' To check a plan against a decomp, call [check_coverage()] — which can then be
#' re-run whenever the decomp refreshes, without rebuilding the plan.
#'
#' @param df A data frame holding the plan: grain columns plus a spend column.
#'   All other columns are preserved on `@data` untouched. Optional
#'   [bound_cols()] `min_spend` and `max_spend` record spend that cannot move
#'   -- a commitment, a floor, a cap -- and every edit then respects them.
#' @param grain Character vector naming the **line item** columns — channel,
#'   partner, tactic. The time column is appended to them automatically, so
#'   there is no need to name it here; naming it anyway is harmless, and it is
#'   moved to the end either way.
#' @param time Name of the plan's time column. A time column is **required**:
#'   every plan says when it runs. Left `NULL`, it is taken from `df` when
#'   exactly one Date or POSIXct column is available to be it. Values may be
#'   `Date` (the first day of the period), `POSIXct` moments, or ISO-8601
#'   strings of either.
#' @param time_basis What one value of the time column covers; one of
#'   [time_basis_levels()]. Inferred from the column when `NULL`: month starts
#'   read as `"month"`, dates that all fall on one weekday as `"week"`,
#'   anything else as `"day"`, and a `POSIXct` column always as `"instant"`.
#'   Declare it when the guess would be wrong — a single month of a monthly
#'   plan cannot be told from a single week.
#' @param tz The plan's timezone, as an Olson name (`"America/New_York"`).
#'   Times given as strings are read on it, and the time column is put on it,
#'   so the plan reads the same wherever the code runs. Taken from the column
#'   when `NULL` and it already carries one; `""` otherwise, which leaves the
#'   session's zone to decide.
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
#' @param approved_on Optional date the plan was approved, as a `Date` or an
#'   ISO string; only with `status = "approved"`. Never defaulted to today.
#' @param objective Human-facing objective / notes.
#' @param id Optional explicit id; generated when `NULL`.
#' @param parent_id Optional parent id for lineage.
#' @return A validated [MediaPlan].
#' @examples
#' df <- data.frame(
#'   week    = as.Date(c("2026-07-06", "2026-07-06", "2026-07-06")),
#'   channel = c("TV", "Search", "Social"),
#'   planned_spend = c(100, 80, 60)
#' )
#' media_plan_from_df(df, grain = "channel", time = "week", name = "Q3 plan",
#'                    advertiser = "Acme", status = "in development")
#'
#' # A buy placed at a specific moment: a POSIXct column, basis "instant".
#' spots <- data.frame(
#'   airs   = as.POSIXct(c("2026-07-06 20:30:00", "2026-07-06 21:00:00"),
#'                       tz = "UTC"),
#'   daypart = c("primetime", "primetime"),
#'   planned_spend = c(45000, 52000)
#' )
#' media_plan_from_df(spots, grain = "daypart", time = "airs",
#'                    name = "Launch spots")
#' @export
media_plan_from_df <- function(df, grain, time = NULL, time_basis = NULL,
                               tz = NULL,
                               planned_spend = "planned_spend",
                               planned_units = NULL, planned_rate = NULL,
                               unit_type = NULL,
                               name, nickname = "", advertiser = "",
                               planner = "", status = "", approved_on = NULL,
                               objective = "", id = NULL,
                               parent_id = character(0)) {
  if (missing(name) || !length(name) || is.na(name[1]) || !nzchar(name[1])) {
    stop("`name` is required: every plan carries a formal name. Use ",
         "`nickname` for a short working handle.", call. = FALSE)
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  df <- .normalise_bound_cols(df)

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

  time <- if (is.null(time)) .infer_time_col(df) else as.character(time)
  if (length(time) != 1 || is.na(time) || !nzchar(time)) {
    stop("`time` must name a single column.", call. = FALSE)
  }
  if (!time %in% names(df)) {
    stop("time column '", time, "' not found in `df`. Every plan is planned ",
         "against a calendar, so `df` carries the week, day, month or moment ",
         "each row is planned for.", call. = FALSE)
  }
  # The plan's clock is settled BEFORE the column is read, so a string like
  # "2026-02-08 20:00" means that time on the plan's clock rather than on
  # whichever machine happens to be parsing it.
  # Unstated, either way round, means "whatever the data already says".
  tz <- if (is.null(tz)) "" else as.character(tz)[1]
  if (is.na(tz) || !nzchar(tz)) tz <- .tz_of(df[[time]])
  if (!.valid_tz(tz)) {
    stop("`tz` '", tz, "' is not a timezone this platform knows; see ",
         "OlsonNames().", call. = FALSE)
  }
  df[[time]] <- .stamp_tz(.as_time_col(df[[time]], time, tz), tz)
  for (nm in intersect(c("flight_start", "flight_end"), names(df))) {
    df[[nm]] <- .stamp_tz(df[[nm]], tz)
  }

  miss <- setdiff(grain, names(df))
  if (length(miss)) {
    stop("grain column(s) not found in `df`: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }

  # The time column belongs to the grain and goes last, whether or not the
  # caller named it: a row is a line item for one period, and the columns are
  # ordered coarsest-first so roll_up() can drop the rightmost.
  grain <- c(setdiff(grain, time), time)
  if (length(grain) < 2L) {
    stop("`grain` must name at least one line item column (channel, partner, ",
         "tactic); the time column is added to them automatically.",
         call. = FALSE)
  }

  basis <- if (is.null(time_basis)) {
    .infer_time_basis(df[[time]])
  } else {
    trimws(tolower(as.character(time_basis)[1]))
  }

  MediaPlan(
    data       = df,
    grain      = grain,
    time_col   = time,
    time_basis = basis,
    tz         = tz,
    id         = id %||% new_id("plan"),
    parent_id  = parent_id,
    name       = name,
    nickname   = nickname,
    advertiser = advertiser,
    planner    = planner,
    status     = .normalise_status(status),
    approved_on = .as_approved_on(approved_on),
    objective  = objective
  )
}

# An approval date as given -- a Date or an ISO string -- as a single Date, or
# the empty Date when none was given.
.as_approved_on <- function(x) {
  if (is.null(x) || !length(x)) return(as.Date(character(0)))
  d <- if (inherits(x, "Date")) x else
    suppressWarnings(tryCatch(as.Date(as.character(unlist(x))),
                              error = function(e) as.Date(NA)))
  if (length(d) != 1L || is.na(d)) {
    stop("`approved_on` must be a single date: a Date or an ISO string such ",
         "as \"2026-10-29\".", call. = FALSE)
  }
  d
}

#' Roll a plan up to a coarser grain
#'
#' Aggregates `planned_spend` to a subset of the plan's grain, returning a new
#' [MediaPlan] with `@parent_id` set. Use it to find the nearest level at which
#' a response model exists: a new partner with no model of its own rolls up to
#' its channel, which has one.
#'
#' Treat the line item columns as an ordered nesting (channel, then partner,
#' then tactic), so "the next coarsest level" means dropping the rightmost one.
#'
#' Time is **never** rolled up here: `@time_col` is kept whatever is asked for,
#' because a plan without a calendar is not a plan. To aggregate over time — to
#' see a weekly plan by month — use [calendarize()], the other half of the pair.
#'
#' @param plan A [MediaPlan].
#' @param grain Character vector; the line item columns to aggregate to, a
#'   subset of [line_item_grain()]. The time column is kept automatically.
#' @param name Optional name for the resulting plan; defaults to the source
#'   plan's name, since a rollup is the same plan viewed at a coarser grain.
#' @return A new [MediaPlan] at the coarser grain. Any subplans are dropped:
#'   a rollup is a coarser *view*, and the cells they backed may no longer
#'   exist at the new grain.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "TV", "Search"),
#'              partner = c("NBC", "ESPN", "Google"),
#'              planned_spend = c(30, 20, 50)),
#'   grain = c("channel", "partner"), time = "week", name = "Q3 plan"
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
  grain <- c(setdiff(grain, plan@time_col), plan@time_col)
  if (length(grain) < 2L) {
    stop("`grain` must name at least one line item column to roll up to (",
         paste(line_item_grain(plan), collapse = ", "), "); the time column ",
         "is kept automatically. To aggregate over time, use calendarize().",
         call. = FALSE)
  }

  out <- .aggregate_to(plan@data, grain)

  # A rollup is a coarser VIEW, so it drops the subplans: the cells they back
  # may not exist at the new grain, and a view does not own anything. It
  # records no edits and no rationale: it changed nothing, and the source's
  # edits would not replay at this grain. Nobody approved the view itself, so
  # it carries no approval date.
  .copy_plan(
    plan,
    data        = out,
    grain       = grain,
    id          = new_id("plan"),
    parent_id   = plan@id,
    name        = name %||% plan@name,
    subplans    = list(),
    edits       = list(),
    rationale   = list(),
    approved_on = as.Date(character(0))
  )
}

#' Revise a plan's metadata without changing what it plans
#'
#' The metadata-only edit verb. Changes any of `name`, `nickname`,
#' `advertiser`, `planner`, `status`, `approved_on`, `objective` and
#' `rationale`, and leaves everything else — `@data`, `@grain`, `@id`, `@parent_id`,
#' `@subplans`, `@edits` — exactly as it was. `rationale` is here because it
#' describes the plan, not its spend: an author or a forecast can be added
#' after the fact. Because `@id` is kept, the result is *the same plan*,
#' revised, rather than a derivative of it; that is the difference from
#' [build_scenario()], which mints a new id and lineage.
#'
#' This exists so that a consumer never has to rebuild a plan by naming its
#' slots by hand — the habit that silently drops any slot added later. Use
#' `revise()` for metadata, [build_scenario()] for spend, and
#' [attach_subplan()] / [detach_subplan()] for structure.
#'
#' Approval is set here: `revise(status = "approved", approved_on =
#' "2026-10-29")`. The date is optional and never defaulted to today, and
#' moving the status off `"approved"` clears it. There is no revision number
#' to set: planners say *Rev 3* meaning "the third approved version", which is
#' a fact about the plan's lineage rather than the plan, so [lineage()]
#' derives it, and [current_approved()] finds the latest.
#'
#' @param plan A [MediaPlan].
#' @param ... Named metadata fields to change: `name`, `nickname`,
#'   `advertiser`, `planner`, `status`, `approved_on` (a `Date` or ISO
#'   string; only on an approved plan), `objective`, `rationale` (see
#'   [build_scenario()]). At least one.
#' @return The same plan (same `@id`) with the named fields changed.
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(week = as.Date("2026-07-06"),
#'              channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", time = "week", name = "Q3 plan"
#' )
#' q <- revise(p, status = "approved", approved_on = "2026-10-29")
#' identical(q@id, p@id)
#' q@approved_on
#'
#' # sending it back for review withdraws the approval and its date
#' revise(q, status = "to review")@approved_on
#' @export
revise <- function(plan, ...) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  changes <- list(...)
  allowed <- c("name", "nickname", "advertiser", "planner", "status",
               "approved_on", "objective", "rationale")
  if ("revision" %in% names(changes)) {
    stop("`revision` is no longer set by hand: a plan's revision is its place ",
         "among the approved plans in its lineage. Approve it with ",
         "revise(status = \"approved\", approved_on = ) and read the revision ",
         "from lineage().", call. = FALSE)
  }
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
  if ("status" %in% names(changes)) {
    changes$status <- .normalise_status(changes$status)
    # Leaving "approved" withdraws the approval, and its date with it.
    if (!identical(changes$status, "approved") &&
        !"approved_on" %in% names(changes)) {
      changes$approved_on <- as.Date(character(0))
    }
  }
  if ("approved_on" %in% names(changes)) {
    changes$approved_on <- .as_approved_on(changes$approved_on)
  }
  if ("rationale" %in% names(changes)) {
    changes$rationale <- .as_rationale(changes$rationale)
  }
  do.call(.copy_plan, c(list(plan), changes))
}
