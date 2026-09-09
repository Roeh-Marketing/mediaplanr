# Who owns each cell of a plan

One row per line item per period — the plan's own rows, labelled with
the subplan that owns each one. A cell backed by a subplan is **locked**
on this plan: its number is the subplan's rollup and every edit door
refuses it. The rest are the plan's own, editable here. This is the
projection behind an ownership grid — line items across, weeks down,
coloured by owner — and the planner's answer to *where can I still
change things?*

## Usage

``` r
ownership_map(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

A data frame with the plan's line item columns, its week column when it
has one, and:

- `key`:

  The line item, as
  [`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
  names it.

- `owner`:

  The subplan key that owns the cell; `NA` when the plan does.

- `owner_name`:

  That subplan's `@name`; `NA` when the plan owns it.

- `locked`:

  `TRUE` when a subplan owns the cell.

- `planned_spend`:

  The cell's spend.

Ordered by period, then line item.

## Details

Ownership is one level deep by construction: a cell belongs to the
subplan attached *here*, whatever that subplan holds beneath it. Ask the
subplan for its own map.

## See also

[`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md),
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
ownership_map(attach_subplan(topline, tv))
#>   channel    key owner owner_name locked planned_spend
#> 1  Search Search  <NA>       <NA>  FALSE            40
#> 2      TV     TV    TV  TV detail   TRUE           120
```
