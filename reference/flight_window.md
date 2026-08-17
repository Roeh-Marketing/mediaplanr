# The plan's flight window

The first and last dates on which the plan has any line item in market —
the plan's own **extent**, derived from `@data`. A weekly row runs from
its week start through the following six days, so a plan whose last week
begins `2026-04-06` is in market through `2026-04-12`.

## Usage

``` r
flight_window(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

A `Date` vector of length 2, named `start` and `end`. Length 0 when the
plan has no time dimension, no rows, or no non-missing dates — never
`NA`, so absence is tested with
[`length()`](https://rdrr.io/r/base/length.html), exactly as for
`@week_col`.

## Details

This is a property of the plan alone: it changes only when the plan
changes. It is emphatically **not** the `through` date of
[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md),
which is the boundary of what a decomp has measured. That one belongs to
a *pairing* rather than to either artifact, and it moves every time the
decomp refreshes. The rule the package follows, and the reason one is a
property while the other is an argument: *if a value can change without
the plan changing, it does not belong on the plan.*

`@flight_start` and `@flight_end` on a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
read from here.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week    = as.Date(c("2026-03-02", "2026-04-06")),
             channel = c("TV", "TV"),
             planned_spend = c(30, 35)),
  grain = c("channel", "week"), week = "week", name = "Q2 plan"
)

flight_window(p)   # ends 2026-04-12: the last week runs a full seven days
#>        start          end 
#> "2026-03-02" "2026-04-12" 
p@flight_start
#> [1] "2026-03-02"
p@flight_days
#> [1] 42
```
