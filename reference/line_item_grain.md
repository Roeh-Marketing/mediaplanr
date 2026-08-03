# The grain columns that identify a line item, excluding the week

A plan's `@grain` describes a row. When the plan has a week column, a
row is a line item *per week*; this drops the week so what remains
identifies the line item itself — the level the decomp constrains and
response models are fitted at.

## Usage

``` r
line_item_grain(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

Character vector of grain columns excluding `@week_col`.
