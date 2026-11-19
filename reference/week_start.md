# The weekday a plan's weeks begin on

Derived from the time column rather than stored, so it cannot disagree
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

The weekday name, or `NA_character_` when the plan is not weekly, has no
rows, or has weeks that do not all fall on the same weekday.

## Details

Only a weekly plan has one: on a plan whose `@time_basis` is `"day"`,
`"month"` or `"instant"` there is no such weekday and this is `NA`.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week = as.Date(c("2026-04-06", "2026-04-13")),
             channel = c("TV", "TV"), planned_spend = c(1, 2)),
  grain = "channel", time = "week", name = "Q2 plan"
)
week_start(p)
#> [1] "Monday"
```
