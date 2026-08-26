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
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
or a
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md),
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

## See also

[`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80000, 40000)),
  grain = "channel", name = "Q3"
)
plan_from_json(plan_to_json(p))
#> <MediaPlan> Q3
#>   grain       channel
#>     channel   Search, TV
#>   rows        2
#>   spend       120,000
#>   id          plan_7463a2
#> 
#>    channel planned_spend
#>         TV         80000
#>     Search         40000
plan_from_json(plan_to_json(scenario_set(p)))
#> <ScenarioSet>  1 scenario at channel
#> 
#>     scenario  status    spend  vs base
#>   * Q3        -       120,000        -
#> 
#>   * = baseline
```
