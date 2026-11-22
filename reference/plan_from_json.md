# Rebuild a media plan or scenario set from JSON

Inverse of
[`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md).
A plan is reconstructed through
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md),
so it is re-validated and its unit identity re-solved on the way in: a
hand-edited or drifted file rebuilds *clean*, not merely reconstructed.
`@id` and `@parent_id` are carried through, so identity and lineage
survive.

## Usage

``` r
plan_from_json(txt)
```

## Arguments

- txt:

  A JSON string produced by
  [`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md),
  or a path to a file containing one.

## Value

A
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md),
a
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
or a
[PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md),
matching what was serialized.

## Details

Flighted and mixed plans need no special handling. The flight columns
(`flight_id`, `flight_start`, `flight_end`, `period_basis`, `pacing`)
travel inside `@data`; their dates are reparsed and the validator
accepts them. Non-flight rows keep `NA` in those columns.

A
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
is detected from its `object` tag (or, for tagless JSON, from the
presence of `scenarios`) and each scenario is rebuilt the same way, with
the baseline and scenario names preserved.

Subplans are rebuilt first and then **attached** through
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md),
never assigned into the slot. Attaching recomputes the parent's rows for
each cell, so a hand-edited parent row is corrected rather than trusted,
and a file describing an illegal tree — a subplan at the wrong grain, or
a plan beneath itself — is refused with the same error an interactive
attach would give. A file nesting more than 32 levels deep is refused
outright: a written tree is always finite, a parsed one need not be.

## See also

[`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search"), planned_spend = c(80000, 40000)),
  grain = "channel", time = "week", name = "Q3"
)
plan_from_json(plan_to_json(p))
#> <MediaPlan> Q3
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  2
#>     channel   Search, TV
#>   rows        2
#>   spend       120,000
#>   id          plan_0a3fa1
#> 
#>          week channel planned_spend
#>    2026-07-06      TV         80000
#>    2026-07-06  Search         40000
plan_from_json(plan_to_json(scenario_set(p)))
#> <ScenarioSet>  1 scenario at channel + week
#> 
#>     scenario  status    spend  vs base
#>   * Q3        -       120,000        -
#> 
#>   * = baseline
```
