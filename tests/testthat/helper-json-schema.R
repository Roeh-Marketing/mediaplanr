# A small JSON Schema checker, so plan_ops_schema() can be tested without a
# new dependency.
#
# It implements only the keywords that schema uses, and stops on any other --
# so if the schema grows a keyword, these tests fail loudly rather than
# silently ignoring it.
#
# `x` and `schema` are as jsonlite::fromJSON(simplifyVector = FALSE) parses
# them: a JSON object is a named list, a JSON array an unnamed list.

schema_keywords <- c(
  # annotations, ignored
  "$schema", "title", "description",
  # checked
  "type", "const", "enum", "pattern", "minimum", "minItems", "items",
  "properties", "required", "additionalProperties", "dependentRequired",
  "anyOf", "oneOf"
)

json_is_object <- function(x) is.list(x) && !is.null(names(x))
json_is_array  <- function(x) is.list(x) && is.null(names(x))

json_has_type <- function(x, type) {
  scalar <- !is.list(x) && length(x) == 1L
  switch(type,
    object  = json_is_object(x),
    array   = json_is_array(x),
    string  = scalar && is.character(x),
    number  = scalar && is.numeric(x),
    integer = scalar && is.numeric(x) && x == round(x),
    boolean = scalar && is.logical(x),
    stop("schema_problems(): unknown type '", type, "'.")
  )
}

# The problems with `x` against `schema`, as a character vector of
# "path: what is wrong". Empty means `x` is valid.
schema_problems <- function(x, schema, path = "$") {
  unsupported <- setdiff(names(schema), schema_keywords)
  if (length(unsupported)) {
    stop("schema_problems() does not support: ",
         paste(unsupported, collapse = ", "))
  }
  problems <- character(0)
  found <- function(...) problems <<- c(problems, paste0(path, ": ", ...))

  # A wrong type makes every other keyword meaningless, so stop there.
  types <- unlist(schema[["type"]])
  if (length(types) && !any(vapply(types, json_has_type, logical(1), x = x))) {
    return(paste0(path, ": expected ", paste(types, collapse = " or ")))
  }

  if (!is.null(schema[["const"]]) && !identical(x, schema[["const"]])) {
    found("expected ", format(schema[["const"]]))
  }
  if (!is.null(schema[["enum"]])) {
    if (is.list(x) || !x %in% unlist(schema[["enum"]])) {
      found("not one of the allowed values")
    }
  }
  if (!is.null(schema[["pattern"]]) && is.character(x) &&
      !grepl(schema[["pattern"]], x)) {
    found("'", x, "' does not match ", schema[["pattern"]])
  }
  if (!is.null(schema[["minimum"]]) && is.numeric(x) &&
      x < schema[["minimum"]]) {
    found(x, " is below the minimum of ", schema[["minimum"]])
  }

  if (json_is_array(x)) {
    if (!is.null(schema[["minItems"]]) && length(x) < schema[["minItems"]]) {
      found("fewer than ", schema[["minItems"]], " item(s)")
    }
    if (!is.null(schema[["items"]])) {
      for (i in seq_along(x)) {
        problems <- c(problems, schema_problems(
          x[[i]], schema[["items"]], paste0(path, "[", i, "]")))
      }
    }
  }

  if (json_is_object(x)) {
    for (req in unlist(schema[["required"]])) {
      if (!req %in% names(x)) found("missing required '", req, "'")
    }
    for (key in names(schema[["dependentRequired"]])) {
      needs <- unlist(schema[["dependentRequired"]][[key]])
      if (key %in% names(x) && !all(needs %in% names(x))) {
        found("'", key, "' also needs '", paste(needs, collapse = "', '"), "'")
      }
    }
    props <- schema[["properties"]]
    extra_schema <- schema[["additionalProperties"]]
    for (key in names(x)) {
      at <- paste0(path, ".", key)
      if (key %in% names(props)) {
        problems <- c(problems, schema_problems(x[[key]], props[[key]], at))
      } else if (isFALSE(extra_schema)) {
        found("unexpected property '", key, "'")
      } else if (is.list(extra_schema)) {
        problems <- c(problems, schema_problems(x[[key]], extra_schema, at))
      }
    }
  }

  matches <- function(subschemas) {
    vapply(subschemas, function(s) !length(schema_problems(x, s, path)),
           logical(1))
  }
  if (!is.null(schema[["anyOf"]]) && !any(matches(schema[["anyOf"]]))) {
    found("matches none of anyOf")
  }
  if (!is.null(schema[["oneOf"]])) {
    n <- sum(matches(schema[["oneOf"]]))
    if (n != 1L) found("matches ", n, " of oneOf, not exactly 1")
  }

  problems
}
