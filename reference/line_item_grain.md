# The grain columns that identify a line item, excluding time

A plan's `@grain` describes a row, and every plan is keyed by time, so a
row is a line item *for one period*. This drops `@time_col`, leaving the
columns that identify the line item itself — the level the decomp
constrains and response models are fitted at.

## Usage

``` r
line_item_grain(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

Character vector of grain columns excluding `@time_col`.
