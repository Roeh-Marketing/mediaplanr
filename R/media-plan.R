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
    objective  = S7::new_property(S7::class_character, default = "")
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
#' @param decomp A data frame of the decomp's line items. May name any subset of
#'   [line_item_grain()] — a channel-only decomp checks channels and ignores
#'   partners.
#' @param through Optional `Date`. Only plan rows with `week < through` are
#'   considered. Without it (or on a plan with no week column) the whole plan is
#'   considered.
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
    if (!length(plan@week_col)) {
      warning("`through` was supplied but the plan has no week column; ",
              "checking the whole plan.", call. = FALSE)
    } else {
      d <- d[d[[plan@week_col]] < through, , drop = FALSE]
      if (!nrow(d)) {
        warning("no plan rows fall before ", format(through), "; not checked.",
                call. = FALSE)
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
                               name, nickname = "", advertiser = "",
                               planner = "", status = "", objective = "",
                               id = NULL, parent_id = character(0)) {
  if (missing(name) || !length(name) || is.na(name[1]) || !nzchar(name[1])) {
    stop("`name` is required: every plan carries a formal name. Use ",
         "`nickname` for a short working handle.", call. = FALSE)
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)

  if (!planned_spend %in% names(df)) {
    stop("planned-spend column '", planned_spend, "' not found in `df`.",
         call. = FALSE)
  }
  if (planned_spend != "planned_spend") {
    if ("planned_spend" %in% names(df)) df[["planned_spend"]] <- NULL
    names(df)[names(df) == planned_spend] <- "planned_spend"
  }

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
    objective  = objective
  )
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
#' @return A new [MediaPlan] at the coarser grain.
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

  d <- plan@data
  k <- line_item(d, grain)
  first <- !duplicated(k)
  out <- d[first, grain, drop = FALSE]
  sums <- tapply(d[["planned_spend"]], k, sum)
  out[["planned_spend"]] <- as.numeric(sums[k[first]])
  rownames(out) <- NULL

  MediaPlan(
    data       = out,
    grain      = grain,
    week_col   = intersect(plan@week_col, grain),
    id         = new_id("plan"),
    parent_id  = plan@id,
    name       = name %||% plan@name,
    nickname   = plan@nickname,
    advertiser = plan@advertiser,
    planner    = plan@planner,
    status     = plan@status,
    objective  = plan@objective
  )
}
