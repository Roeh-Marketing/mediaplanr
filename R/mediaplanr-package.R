#' @keywords internal
"_PACKAGE"

# mediaplanr — a thin backend that gives a media-mix app a typed media-plan
# object plus scenario construction and comparison.
#
# Scope notes (see vignette("plan_concepts") for the full rationale, and
# Roadmap.md for what is deliberately not built yet):
#
# * The object model is deliberately thin. `@data` stays a plain, directly
#   accessible data frame; the S7 classes add guarantees (validation),
#   identity (synthetic ids), provenance (parent lineage), and a verb grammar
#   at the boundaries. They do not take the data frame away from the user.
#
# * A plan is keyed at a **configurable grain** (a composite key of one or more
#   columns), held as a flat table — not a nested object hierarchy. A plan
#   keyed by `channel`, or `channel + partner`, or `channel + partner + tactic`
#   is the same class at different grains.
#
# * Value semantics: a plan is immutable in practice. Scenarios are new objects
#   derived from a parent, never mutations of it, so the thing being compared
#   against is never corrupted.
#
# * The package holds **plan intent only**. It does not fit models, forecast,
#   or optimize, and depends on nothing but S7. Response modeling and budget
#   optimization belong to the `mrmopt` engine; a caller runs those and joins
#   the results back to `compare_scenarios()` output by scenario + grain cell.
#   Keeping that boundary means a change to the modeling API cannot break the
#   plan object, and modeling decisions never leak into a container.

## usethis namespace: start
## usethis namespace: end
NULL
