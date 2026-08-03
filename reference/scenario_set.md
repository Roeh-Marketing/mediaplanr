# Start a scenario set from a base plan

Start a scenario set from a base plan

## Usage

``` r
scenario_set(base, name = NULL)
```

## Arguments

- base:

  A base
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md),
  registered as the baseline scenario.

- name:

  Label for the baseline scenario. Defaults to the plan's `@nickname` if
  set, otherwise its `@name`.

## Value

A
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
containing one (baseline) scenario.

## Examples

``` r
base <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", name = "Q3 base"
)
scenario_set(base)
#> <ScenarioSet>  1 scenario at channel
#> 
#>     scenario  status  spend  vs base
#>   * Q3 base   -         120        -
#> 
#>   * = baseline
```
