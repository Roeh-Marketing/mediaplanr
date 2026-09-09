# Print a plan's subplan tree

The console view of
[`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md):
the plan on the first line, each subplan beneath the cell it backs, and
— under any plan that holds subplans — an `(editable)` line for the
cells no subplan owns. It answers the planner's question, *what is
locked, and who owns it?*, without leaving R.

## Usage

``` r
plan_tree(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

The printed lines, invisibly, as a character vector.

## See also

[`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md),
[`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md)

## Examples

``` r
topline <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(100, 40)),
  grain = "channel", name = "Q3 topline"
)
tv <- media_plan_from_df(
  data.frame(channel = "TV", partner = c("NBC", "ESPN"),
             planned_spend = c(70, 50)),
  grain = c("channel", "partner"), name = "TV detail"
)
plan_tree(attach_subplan(topline, tv))
#> Q3 topline                                        160
#> ├─ TV          TV detail  timeless  2 line items  120
#> └─ (editable)                       1 line item    40
```
