# A plan's structure, or a set's lineage, as a Mermaid diagram

Emits a Mermaid `graph` definition as a single string. For a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
the nodes are the plans in its subplan tree and the edges are labelled
with the cell each subplan backs; for a
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
the nodes are the scenarios and each edge carries the spend change
against the parent it was derived from. No graphics dependency: the
string renders wherever Mermaid does — a GitHub README, Quarto, Shiny, a
notebook.

## Usage

``` r
plan_mermaid(x, direction = c("TD", "LR"))
```

## Arguments

- x:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  or a
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

- direction:

  Mermaid layout direction; `"TD"` (default) or `"LR"`.

## Value

A single string. [`cat()`](https://rdrr.io/r/base/cat.html) it, or pass
it to a Mermaid renderer.

## See also

[`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md),
[`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)

## Examples

``` r
base <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", name = "base"
)
s1  <- build_scenario(base, c(Search = 60), name = "Search up")
cat(plan_mermaid(add_scenario(scenario_set(base), s1)))
#> graph TD
#>   n1["base<br/>120"]:::base
#>   n2["Search up<br/>140 · in development"]
#>   classDef base stroke-width:3px
#>   n1 -->|+20 (+17%)| n2
```
