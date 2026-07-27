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
