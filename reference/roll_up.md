# Roll a plan up to a coarser grain

Aggregates `planned_spend` to a subset of the plan's grain, returning a
new
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
with `@parent_id` set. Use it to find the nearest level at which a
response model exists: a new partner with no model of its own rolls up
to its channel, which has one.

## Usage

``` r
roll_up(plan, grain, name = NULL)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- grain:

  Character vector; the line item columns to aggregate to, a subset of
  [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md).
  The time column is kept automatically.

- name:

  Optional name for the resulting plan; defaults to the source plan's
  name, since a rollup is the same plan viewed at a coarser grain.

## Value

A new
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
at the coarser grain. Any subplans are dropped: a rollup is a coarser
*view*, and the cells they backed may no longer exist at the new grain.

## Details

Treat the line item columns as an ordered nesting (channel, then
partner, then tactic), so "the next coarsest level" means dropping the
rightmost one.

Time is **never** rolled up here: `@time_col` is kept whatever is asked
for, because a plan without a calendar is not a plan. To aggregate over
time — to see a weekly plan by month — use
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md),
the other half of the pair.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "TV", "Search"),
             partner = c("NBC", "ESPN", "Google"),
             planned_spend = c(30, 20, 50)),
  grain = c("channel", "partner"), time = "week", name = "Q3 plan"
)
roll_up(p, "channel")@data
#>   channel       week planned_spend
#> 1      TV 2026-07-06            50
#> 2  Search 2026-07-06            50
```
