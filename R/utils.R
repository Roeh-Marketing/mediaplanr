#' NULL-coalescing operator
#'
#' Returns `x` unless it is `NULL` (or a zero-length vector), in which case it
#' returns `y`. Internal convenience used throughout the package.
#'
#' @param x,y Values; `y` is used when `x` is `NULL`/empty.
#' @return `x` if it has length, otherwise `y`.
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

#' Generate an opaque synthetic id
#'
#' Ids exist for identity and lineage only; they carry no external meaning.
#' Human-facing meaning lives in `@name` / `@objective`. The id combines a
#' prefix, a timestamp, and random hex so ids created in quick succession do
#' not collide.
#'
#' @param prefix Short character prefix naming the kind of object (e.g.
#'   `"plan"`, `"models"`, `"fcst"`, `"set"`).
#' @return A single character string.
#' @keywords internal
#' @noRd
new_id <- function(prefix = "obj") {
  stamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  rand <- sprintf("%06x", sample.int(16777215L, 1L))
  paste0(prefix, "_", stamp, "_", rand)
}

# The settable (non-getter) slots of an S7 class. S7::props() includes the
# getter-backed ones, which cannot be passed to the constructor.
.settable_props <- function(cls) {
  ps <- attr(cls, "properties")
  names(ps)[vapply(ps, function(p) is.null(p$getter), logical(1))]
}

# Rebuild a plan from its settable slots, overriding the ones named in `...`.
#
# THE ONE DOOR through which a plan is copied. A constructor call that names
# every slot by hand silently drops any slot added later -- which is how a
# status change would quietly detach every subplan. Going through the property
# list instead means a new slot is carried by default and dropped only on
# purpose.
#
# Whole-slot replacement, deliberately not modifyList(): that recurses into
# list-like values, and @data is a list. Clear a slot with list() /
# character(0), never NULL.
.copy_plan <- function(x, ...) {
  props   <- S7::props(x)[.settable_props(MediaPlan)]
  changes <- list(...)
  unknown <- setdiff(names(changes), names(props))
  if (length(unknown)) {
    stop("not a settable MediaPlan slot: ", paste(unknown, collapse = ", "),
         call. = FALSE)
  }
  props[names(changes)] <- changes
  do.call(MediaPlan, props)
}

#' Abbreviate a synthetic id for printing
#'
#' Keeps the human-readable prefix and the trailing random segment, collapsing
#' the timestamp in the middle to an ellipsis.
#'
#' @param id A character id produced by `new_id()`.
#' @return A short character string suitable for console output.
#' @export
short_id <- function(id) {
  if (length(id) == 0 || is.na(id[1]) || !nzchar(id[1])) return("<none>")
  parts <- strsplit(id[1], "_", fixed = TRUE)[[1]]
  if (length(parts) >= 3) {
    paste0(parts[1], "_", utils::tail(parts, 1))
  } else {
    id[1]
  }
}
