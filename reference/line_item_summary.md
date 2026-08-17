# The roster of line items in a plan

One row per line item — the time-free identity of what is being bought —
with its total planned spend, how many plan rows it occupies, and its
own flight window. Where
[`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
returns the key for every row, this returns the distinct roster.

## Usage

``` r
line_item_summary(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

A data frame: the
[`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
columns, then `line_item` (the key), `planned_spend` (the item's total),
`n_rows`, and — only when the plan has a time dimension — `flight_start`
and `flight_end`. The date columns are absent rather than `NA` on a
timeless plan.

## Details

The grain columns come back as **columns**, not folded into the key,
because that is the shape both consumers need: a UI renders them as its
left-hand rows, and the `target` of an edit operation is
column-and-value pairs. The pasted key is included as `line_item` for
the callers that want it.

Ordered by planned spend descending, ties broken by key, so the head of
the table is the part of the plan worth looking at first and the order
is stable between calls.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week    = as.Date(c("2026-03-02", "2026-03-02", "2026-04-06")),
             channel = c("TV", "Search", "TV"),
             partner = c("NBC", "Google", "NBC"),
             planned_spend = c(30, 20, 35)),
  grain = c("channel", "partner", "week"), week = "week", name = "Q2 plan"
)

line_item_summary(p)
#>   channel partner       line_item planned_spend n_rows flight_start flight_end
#> 1      TV     NBC        TV | NBC            65      2   2026-03-02 2026-04-12
#> 2  Search  Google Search | Google            20      1   2026-03-02 2026-03-08
```
