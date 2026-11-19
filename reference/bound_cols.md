# The columns that record a row's spend bounds

Reserved column names carried on `@data` when some of a plan's spend
cannot move: an upfront commitment, a partner minimum, a cap. Like the
flighting and unit columns they ride along: the validator checks them,
and they never form part of `@grain`.

## Usage

``` r
bound_cols()
```

## Value

A character vector of the reserved column names.

## Details

- `min_spend` – the least the row may plan. `NA` means no floor.

- `max_spend` – the most the row may plan. `NA` means no cap.

A row whose `min_spend` and `max_spend` both equal its `planned_spend`
is **committed**: no edit can move it. Every edit respects the bounds,
and they change only through an explicit `rebound` op; see
[`op_rebound()`](https://roeh-marketing.github.io/mediaplanr/reference/op_rebound.md).

## Examples

``` r
bound_cols()
#> [1] "min_spend" "max_spend"

plan <- media_plan_from_df(
  data.frame(month = as.Date("2026-10-01"),
             channel = c("Streaming", "Search"),
             planned_spend = c(60000, 20000),
             min_spend = c(60000, NA), max_spend = c(60000, NA)),
  grain = "channel", time = "month", name = "Q4"
)
# Streaming is committed, so a cut comes entirely out of Search
build_scenario(plan, edits = op_delta(-5000), name = "trim")@data
#>        month   channel planned_spend min_spend max_spend
#> 1 2026-10-01 Streaming         60000     60000     60000
#> 2 2026-10-01    Search         15000        NA        NA
```
