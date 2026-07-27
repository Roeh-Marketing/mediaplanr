#' Composite grain key for a data frame
#'
#' Collapses the active grain columns of a data frame into a single character
#' vector of composite keys, one per row. This is the canonical way the package
#' identifies grain cells and matches them to response models.
#'
#' @param df A data frame containing the grain columns.
#' @param grain Character vector of column names forming the grain.
#' @param sep Separator between key parts. Default `" | "`.
#' @return A character vector of composite keys, length `nrow(df)`.
#' @examples
#' d <- data.frame(channel = c("TV", "TV"), partner = c("A", "B"))
#' grain_key(d, c("channel", "partner"))
#' @export
grain_key <- function(df, grain, sep = " | ") {
  if (length(grain) == 0) {
    stop("`grain` must name at least one column.", call. = FALSE)
  }
  missing <- setdiff(grain, names(df))
  if (length(missing)) {
    stop("grain column(s) not found: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  parts <- lapply(grain, function(g) as.character(df[[g]]))
  do.call(paste, c(parts, list(sep = sep)))
}

#' A media plan at a configurable grain
#'
#' `MediaPlan` is a typed wrapper around a flat plan table. `@data` is a plain,
#' directly accessible data frame of the grain key columns plus a
#' `planned_spend` column; the class adds a validator, a synthetic identity
#' (`@id`), and lineage (`@parent_id`). It holds **intent only** — no actuals or
#' attribution.
#'
#' Any other columns on the supplied data frame are carried through untouched.
#'
#' Construct one with [media_plan_from_df()] rather than calling the constructor
#' directly.
#'
#' @param data A data frame with the grain columns + `planned_spend`. One row
#'   per grain cell.
#' @param grain Character vector naming the active key columns.
#' @param id Opaque synthetic id (identity/lineage only).
#' @param parent_id Id of the plan this one was derived from; empty for a root
#'   plan.
#' @param name Human-facing name.
#' @param objective Human-facing objective / notes.
#' @return A `MediaPlan` S7 object.
#' @export
MediaPlan <- S7::new_class(
  "MediaPlan",
  properties = list(
    data      = S7::new_property(S7::class_data.frame, default = quote(data.frame())),
    grain     = S7::new_property(S7::class_character, default = character(0)),
    id        = S7::new_property(S7::class_character, default = quote(new_id("plan"))),
    parent_id = S7::new_property(S7::class_character, default = character(0)),
    name      = S7::new_property(S7::class_character, default = ""),
    objective = S7::new_property(S7::class_character, default = "")
  ),
  validator = function(self) {
    d <- self@data
    g <- self@grain
    errs <- character(0)

    if (length(g) < 1) {
      errs <- c(errs, "@grain must name at least one key column.")
    }
    miss <- setdiff(g, names(d))
    if (length(miss)) {
      errs <- c(errs, paste0("grain column(s) not in @data: ",
                             paste(miss, collapse = ", ")))
    }

    if (!"planned_spend" %in% names(d)) {
      errs <- c(errs, "@data must contain a 'planned_spend' column.")
    } else {
      ps <- d[["planned_spend"]]
      if (!is.numeric(ps)) {
        errs <- c(errs, "'planned_spend' must be numeric.")
      } else if (anyNA(ps)) {
        errs <- c(errs, "'planned_spend' must not contain NA.")
      } else if (any(ps < 0)) {
        errs <- c(errs, "'planned_spend' must be non-negative.")
      }
    }

    # Grain cells must be unique: one row per cell.
    if (length(miss) == 0 && length(g) >= 1 && nrow(d) > 0) {
      k <- grain_key(d, g)
      if (anyDuplicated(k)) {
        dups <- unique(k[duplicated(k)])
        errs <- c(errs, paste0(
          "@data has duplicate grain cells at grain (", paste(g, collapse = ", "),
          "): ", paste(utils::head(dups, 5), collapse = "; "),
          ". One row per cell is required."))
      }
    }

    if (length(self@id) != 1 || is.na(self@id) || !nzchar(self@id)) {
      errs <- c(errs, "@id must be a single non-empty string.")
    }

    if (length(errs)) errs else NULL
  }
)

#' Build a validated media plan from a data frame
#'
#' The primary entry point for turning an uploaded plan into a [MediaPlan].
#' Normalizes the spend column name to the canonical `planned_spend`, optionally
#' checks the plan's grain cells against a set of known-valid keys (e.g. the
#' distinct keys of a decomp), and runs the full validator on construction.
#'
#' @param df A data frame holding the plan: grain columns plus a planned-spend
#'   column. All other columns are preserved on `@data` untouched.
#' @param grain Character vector naming the grain (key) columns.
#' @param planned_spend Name of the planned-spend column in `df`. Renamed to
#'   `planned_spend`. Default `"planned_spend"`.
#' @param name Human-facing plan name.
#' @param objective Human-facing objective / notes.
#' @param valid_keys Optional coverage check for the plan's grain cells. Either
#'   a character vector of composite keys (as produced by [grain_key()]) or a
#'   data frame containing the grain columns whose distinct rows are the allowed
#'   cells. Plan cells outside this set raise an error.
#' @param id Optional explicit id; generated when `NULL`.
#' @param parent_id Optional parent id for lineage.
#' @return A validated [MediaPlan].
#' @examples
#' df <- data.frame(
#'   channel = c("TV", "Search", "Social"),
#'   planned_spend = c(100, 80, 60)
#' )
#' media_plan_from_df(df, grain = "channel", name = "Q3 plan")
#' @export
media_plan_from_df <- function(df, grain,
                               planned_spend = "planned_spend",
                               name = "", objective = "",
                               valid_keys = NULL, id = NULL,
                               parent_id = character(0))
                               {
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

  if (!is.null(valid_keys)) {
    allowed <- if (is.data.frame(valid_keys)) {
      unique(grain_key(valid_keys, grain))
    } else {
      as.character(valid_keys)
    }
    cells <- unique(grain_key(df, grain))
    bad <- setdiff(cells, allowed)
    if (length(bad)) {
      stop("plan contains grain cells not present in `valid_keys`: ",
           paste(utils::head(bad, 5), collapse = "; "),
           if (length(bad) > 5) paste0(" (+", length(bad) - 5, " more)") else "",
           call. = FALSE)
    }
  }

  MediaPlan(
    data      = df,
    grain     = grain,
    id        = id %||% new_id("plan"),
    parent_id = parent_id,
    name      = name,
    objective = objective
  )
}
