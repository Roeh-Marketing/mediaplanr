# The spend each response model scores, period by period

The input a response-model forecast needs: the plan's spend summed to
each model (as
[`model_map()`](https://roeh-marketing.github.io/mediaplanr/reference/model_map.md)
assigns line items to models) for each period of a calendar. Spend no
model covers is kept, under `model_id = NA`, so the totals always
reconcile to the plan – it is never dropped silently.

## Usage

``` r
spend_by_model(
  plan,
  models,
  basis = c("week", "day", "month"),
  week_start = NULL
)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- models:

  A data frame of fitted models: a `model_id` column (unique) and any of
  the plan's
  [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
  columns. `NA` or a blank cell means the model covers any value of that
  column; a row with no line item columns set covers the whole plan.

- basis:

  The calendar to sum over: `"week"`, `"day"` or `"month"`.

- week_start:

  For `basis = "week"`, the weekday the models' weeks start on; the
  plan's own by default. See
  [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md).

## Value

A long data frame, one row per model per period: `model_id`, a column
named after `basis` holding each period's start, and `planned_spend`.
When a model's rows are all one unit type, its `unit_type`,
`planned_units` and blended `planned_rate` too. Ordered by model,
unmodeled spend last, then by period.

## Details

The plan is first re-cut onto the calendar with
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md),
so a weekly model can score a monthly plan and the other way round, and
a plan keyed by moments lands on the days its spots air.

## See also

[`model_map()`](https://roeh-marketing.github.io/mediaplanr/reference/model_map.md)
for the mapping itself.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(week = rep(as.Date(c("2026-07-06", "2026-07-13")), each = 2),
             channel = c("TV", "Search"),
             planned_spend = c(50, 40, 60, 40)),
  grain = "channel", time = "week", name = "Q3"
)
models <- data.frame(model_id = c("tv", "search"),
                     channel = c("TV", "Search"))
spend_by_model(plan, models)
#>   model_id       week planned_spend
#> 1   search 2026-07-06            40
#> 2   search 2026-07-13            40
#> 3       tv 2026-07-06            50
#> 4       tv 2026-07-13            60
spend_by_model(plan, models, basis = "month")
#>   model_id      month planned_spend
#> 1   search 2026-07-01            80
#> 2       tv 2026-07-01           110

if (FALSE) { # \dontrun{
# The hand-off to a response model:
mrmopt::forecast(fitted_models, spend_by_model(plan, models))
} # }
```
