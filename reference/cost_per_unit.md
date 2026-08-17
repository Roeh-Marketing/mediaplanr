# The cost of one unit, and the cost per thousand

Derived from `planned_spend` and `planned_units`, never stored
separately, so neither can disagree with the plan's money.

## Usage

``` r
cost_per_unit(plan)

cpm(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

A numeric vector, one per row of `@data`. `NA` where a row records no
units.

## Details

`cost_per_unit()` is always the price of a single unit. `cpm()` is the
trade's cost per thousand — the figure actually quoted for impressions —
and is simply `cost_per_unit() * 1000`, reported for any unit type on
the assumption that you asked for a reason.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("Social", "Search"),
             unit_type = c("impression", "click"),
             planned_spend = c(140000, 95000),
             planned_units = c(28000000, 118750)),
  grain = "channel", name = "Q3 plan"
)

cost_per_unit(p)
#> [1] 0.005 0.800
cpm(p)
#> [1]   5 800
p@data$planned_rate      # the CPM for Social, the CPC for Search
#> [1] 5.0 0.8
```
