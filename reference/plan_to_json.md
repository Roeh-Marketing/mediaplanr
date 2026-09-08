# Serialize a media plan or scenario set to JSON

Writes a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
or a
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
to JSON that
[`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
can rebuild faithfully. For a plan, only its *settable* slots are
written — `@data`, `@grain`, `@week_col`, `@id`, `@parent_id`, and the
metadata scalars — plus an `object` tag and a `schema_version`. Derived
facts
([`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md),
`pacing`,
[`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md))
are deliberately not stored; they are recomputed on rebuild, so the JSON
stays small and cannot persist a stale value. A
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
writes its own scalars (`@grain`, `@base_name`, `@id`) and each scenario
serialized exactly as a standalone plan.

## Usage

``` r
plan_to_json(x, path = NULL, pretty = TRUE)
```

## Arguments

- x:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  or
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

- path:

  Optional file path. When supplied, the JSON is written there and
  `path` is returned invisibly; otherwise the JSON string is returned.

- pretty:

  Whether to pretty-print. Defaults to `TRUE`.

## Value

A JSON string (class `json`), or `path` invisibly when writing a file.

## Details

Dates are written as ISO-8601 strings, since JSON has no date type, and
missing flight cells (rows that are not part of an authored flight) are
written as `null`.

**Subplans recurse.** A topline's `@subplans` is written as a `subplans`
object, each entry serialized exactly as a standalone plan is, one level
down. The key is omitted when there are none, so a flat plan's JSON is
unchanged. The parent's `@data` is still written in full, so a reader
that ignores `subplans` still gets the right totals. Schema version 2
added `revision` and `subplans`.

## See also

[`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80000, 40000)),
  grain = "channel", name = "Q3"
)
js <- plan_to_json(p)
identical(plan_from_json(js)@data, p@data)
#> [1] FALSE

set <- scenario_set(p)
identical(plan_from_json(plan_to_json(set))@grain, set@grain)
#> [1] TRUE
```
