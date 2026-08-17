# The flights a plan was authored from

The inverse of
[`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md):
one row per flight, recovered by grouping the weekly rows on
`flight_id`.

## Usage

``` r
flights(plan)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

A data frame: the
[`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
columns (excluding the week), `flight_id`, `flight_start`, `flight_end`,
`period_basis`, `pacing`, `planned_spend` (the flight total) and
`n_weeks`. Zero rows when the plan records no flights.

## Details

This is **exact, never inferred**. A plan built by
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
has no flight identity recorded, and this returns no rows rather than
guessing — four consecutive equal weeks are equally consistent with one
long flight, four weekly buys, or two fortnightly ones, and nothing in
the data distinguishes them.

## Examples

``` r
buys <- data.frame(
  channel = "OOH",
  flight_start = as.Date("2026-04-06"),
  flight_end   = as.Date("2026-05-03"),
  planned_spend = 120000
)
p <- media_plan_from_flights(buys, grain = "channel", name = "Q2 flights")

flights(p)
#>   channel              flight_id flight_start flight_end period_basis pacing
#> 1     OOH fl_20260817005512_a2f0   2026-04-06 2026-05-03       flight   even
#>   planned_spend n_weeks
#> 1        120000       4
sum(flights(p)$planned_spend) == sum(p@data$planned_spend)
#> [1] TRUE
```
