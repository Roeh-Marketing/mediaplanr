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

  Character vector; a subset of `plan@grain` to aggregate to.

- name:

  Optional name for the resulting plan; defaults to the source plan's
  name, since a rollup is the same plan viewed at a coarser grain.

## Value

A new
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
at the coarser grain.

## Details

Treat `@grain` as an ordered nesting (channel, then partner, then
tactic), so "the next coarsest level" means dropping the rightmost
column.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("TV", "TV", "Search"),
             partner = c("NBC", "ESPN", "Google"),
             planned_spend = c(30, 20, 50)),
  grain = c("channel", "partner"), name = "Q3 plan"
)
roll_up(p, "channel")@data
#>   channel planned_spend
#> 1      TV            50
#> 2  Search            50
```
