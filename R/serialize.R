# JSON is how a plan crosses the app boundary: saved, reloaded, handed to a
# model. The shape is small because the class is small — a flat table and a
# handful of scalars — and everything derived is left off and recomputed on the
# way back in, so a serialized plan can never carry a stale derived fact. A
# ScenarioSet is the same idea one level up: its own scalars plus each scenario
# serialized exactly as a standalone plan is.

.plan_schema_version <- 1L

# The settable (non-getter) slots of an S7 class.
.settable_props <- function(cls) {
  ps <- attr(cls, "properties")
  names(ps)[vapply(ps, function(p) is.null(p$getter), logical(1))]
}

# A schema-free named list of a plan's settable slots. Wrapped with an object
# tag and schema_version for a standalone plan, or nested inside a set.
.plan_payload <- function(plan) {
  S7::props(plan)[.settable_props(MediaPlan)]
}

# Rebuild a MediaPlan from a parsed payload list (the inverse of .plan_payload).
# Reconstruction runs through media_plan_from_df(), so the plan is re-validated
# and its unit identity re-solved; flight columns ride in `data` and need no
# special path.
.plan_from_payload <- function(x) {
  if (is.null(x$data) || is.null(x$grain)) {
    stop("not a plan JSON: expected `data` and `grain`.", call. = FALSE)
  }
  df    <- as.data.frame(x$data, stringsAsFactors = FALSE)
  grain <- as.character(x$grain)
  wk    <- if (!is.null(x$week_col) && length(x$week_col) &&
               nzchar(as.character(x$week_col)[1])) {
    as.character(x$week_col)[1]
  } else {
    NULL
  }

  # JSON has no Date type, so reparse the week column and the two flight-date
  # columns. Everything else is already the right type as a string or number.
  for (dc in intersect(c(wk, "flight_start", "flight_end"), names(df))) {
    df[[dc]] <- as.Date(df[[dc]])
  }

  scal <- function(v) if (is.null(v) || !length(v)) "" else as.character(v)[1]
  uc   <- intersect(c("planned_units", "planned_rate", "unit_type"), names(df))
  id_v <- if (!is.null(x$id) && length(x$id) &&
              nzchar(as.character(x$id)[1])) as.character(x$id)[1] else NULL

  media_plan_from_df(
    df, grain = grain, week = wk,
    planned_units = if ("planned_units" %in% uc) "planned_units" else NULL,
    planned_rate  = if ("planned_rate"  %in% uc) "planned_rate"  else NULL,
    unit_type     = if ("unit_type"     %in% uc) "unit_type"     else NULL,
    name       = if (nzchar(scal(x$name))) scal(x$name) else "unnamed",
    nickname   = scal(x$nickname),
    advertiser = scal(x$advertiser),
    planner    = scal(x$planner),
    status     = scal(x$status),
    objective  = scal(x$objective),
    id         = id_v,
    parent_id  = as.character(if (is.null(x$parent_id)) character(0) else x$parent_id)
  )
}

#' Serialize a media plan or scenario set to JSON
#'
#' Writes a [MediaPlan] or a [ScenarioSet] to JSON that [plan_from_json()] can
#' rebuild faithfully. For a plan, only its *settable* slots are written —
#' `@data`, `@grain`, `@week_col`, `@id`, `@parent_id`, and the metadata scalars
#' — plus an `object` tag and a `schema_version`. Derived facts
#' (`flight_window()`, `pacing`, `week_start()`) are deliberately not stored;
#' they are recomputed on rebuild, so the JSON stays small and cannot persist a
#' stale value. A [ScenarioSet] writes its own scalars (`@grain`, `@base_name`,
#' `@id`) and each scenario serialized exactly as a standalone plan.
#'
#' Dates are written as ISO-8601 strings, since JSON has no date type, and
#' missing flight cells (rows that are not part of an authored flight) are
#' written as `null`.
#'
#' @param x A [MediaPlan] or [ScenarioSet].
#' @param path Optional file path. When supplied, the JSON is written there and
#'   `path` is returned invisibly; otherwise the JSON string is returned.
#' @param pretty Whether to pretty-print. Defaults to `TRUE`.
#' @return A JSON string (class `json`), or `path` invisibly when writing a file.
#' @seealso [plan_from_json()]
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80000, 40000)),
#'   grain = "channel", name = "Q3"
#' )
#' js <- plan_to_json(p)
#' identical(plan_from_json(js)@data, p@data)
#'
#' set <- scenario_set(p)
#' identical(plan_from_json(plan_to_json(set))@grain, set@grain)
#' @export
plan_to_json <- function(x, path = NULL, pretty = TRUE) {
  if (S7::S7_inherits(x, MediaPlan)) {
    payload <- c(list(object = "MediaPlan",
                      schema_version = .plan_schema_version),
                 .plan_payload(x))
  } else if (S7::S7_inherits(x, ScenarioSet)) {
    payload <- list(
      object         = "ScenarioSet",
      schema_version = .plan_schema_version,
      grain          = x@grain,
      base_name      = x@base_name,
      id             = x@id,
      scenarios      = lapply(x@scenarios, .plan_payload)
    )
  } else {
    stop("`x` must be a MediaPlan or a ScenarioSet.", call. = FALSE)
  }

  js <- jsonlite::toJSON(payload, dataframe = "rows", Date = "ISO8601",
                         na = "null", null = "null", auto_unbox = TRUE,
                         pretty = pretty)

  if (!is.null(path)) {
    writeLines(js, path)
    return(invisible(path))
  }
  js
}

#' Rebuild a media plan or scenario set from JSON
#'
#' Inverse of [plan_to_json()]. A plan is reconstructed through
#' [media_plan_from_df()], so it is re-validated and its unit identity re-solved
#' on the way in: a hand-edited or drifted file rebuilds *clean*, not merely
#' reconstructed. `@id` and `@parent_id` are carried through, so identity and
#' lineage survive.
#'
#' Flighted and mixed plans need no special handling. The flight columns
#' (`flight_id`, `flight_start`, `flight_end`, `period_basis`, `pacing`) travel
#' inside `@data`; their dates are reparsed and the validator accepts them.
#' Non-flight rows keep `NA` in those columns.
#'
#' A [ScenarioSet] is detected from its `object` tag (or, for tagless JSON, from
#' the presence of `scenarios`) and each scenario is rebuilt the same way, with
#' the baseline and scenario names preserved.
#'
#' @param txt A JSON string produced by [plan_to_json()], or a path to a file
#'   containing one.
#' @return A [MediaPlan] or a [ScenarioSet], matching what was serialized.
#' @seealso [plan_to_json()]
#' @examples
#' p <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80000, 40000)),
#'   grain = "channel", name = "Q3"
#' )
#' plan_from_json(plan_to_json(p))
#' plan_from_json(plan_to_json(scenario_set(p)))
#' @export
plan_from_json <- function(txt) {
  x <- jsonlite::fromJSON(txt, simplifyDataFrame = TRUE)

  if (!is.null(x$schema_version) &&
      isTRUE(x$schema_version > .plan_schema_version)) {
    warning("plan JSON schema_version ", x$schema_version,
            " is newer than this package supports (", .plan_schema_version,
            "); reading may be lossy.", call. = FALSE)
  }

  obj <- if (!is.null(x$object)) {
    as.character(x$object)[1]
  } else if (!is.null(x$scenarios)) {
    "ScenarioSet"
  } else {
    "MediaPlan"
  }

  if (identical(obj, "ScenarioSet")) {
    if (is.null(x$scenarios) || is.null(x$grain)) {
      stop("not a scenario-set JSON: expected `scenarios` and `grain`.",
           call. = FALSE)
    }
    nm   <- names(x$scenarios)
    scen <- lapply(x$scenarios, .plan_from_payload)
    names(scen) <- nm
    ScenarioSet(
      scenarios = scen,
      grain     = as.character(x$grain),
      base_name = as.character(x$base_name)[1],
      id        = as.character(x$id)[1]
    )
  } else {
    .plan_from_payload(x)
  }
}
