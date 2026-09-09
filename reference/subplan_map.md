# The subplan tree as a table

One row per plan in the tree — the plan itself at depth 0, then every
subplan in pre-order, each with the cell it backs, its depth, and the
facts a viewer needs to draw or list it. This is the projection a UI
builds a tree from;
[`plan_tree()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_tree.md)
and
[`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md)
are two renderings of it.

## Usage

``` r
subplan_map(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

A data frame with one row per plan in the tree:

- `depth`:

  0 for `plan`, 1 for its subplans, and so on.

- `key`:

  The parent cell this plan backs (`"TV"`, `"TV | NBC"`); `NA` for the
  root.

- `path`:

  Keys from the root joined with `" > "`; `""` for the root.

- `name`, `nickname`, `status`, `revision`, `id`:

  The plan's own.

- `grain`:

  Its grain columns joined with `" + "`.

- `cadence`:

  `"timeless"`, `"weekly"`, `"daily"`, `"monthly"` or `"flighted"`, read
  off the data.

- `line_items`, `rows`, `spend`:

  Its size.

- `subplans`:

  How many it holds directly.

## See also

[`plan_tree()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_tree.md),
[`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md),
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)

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
subplan_map(attach_subplan(topline, tv))
#>   depth  key path       name nickname             grain  cadence line_items
#> 1     0 <NA>      Q3 topline                    channel timeless          2
#> 2     1   TV   TV  TV detail          channel + partner timeless          2
#>   rows spend subplans revision status                         id
#> 1    2   160        1        1        plan_20260909171951_c0d89c
#> 2    2   120        0        1        plan_20260909171951_e03dc7
```
