# The weekday a plan's weeks begin on

Derived from the week column rather than stored, so it cannot disagree
with the data. US broadcast weeks begin on a Monday; some advertisers
plan Sunday-start, and a plan read from a workbook may be either.

## Usage

``` r
week_start(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

The weekday name, or `NA_character_` when the plan has no time
dimension, no rows, or weeks that do not all fall on the same weekday.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week = as.Date(c("2026-04-06", "2026-04-13")),
             channel = c("TV", "TV"), planned_spend = c(1, 2)),
  grain = c("channel", "week"), week = "week", name = "Q2 plan"
)
week_start(p)
#> [1] "Monday"
```
