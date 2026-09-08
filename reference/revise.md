# Revise a plan's metadata without changing what it plans

The metadata-only edit verb. Changes any of `name`, `nickname`,
`advertiser`, `planner`, `status`, `objective` and `revision`, and
leaves everything else — `@data`, `@grain`, `@id`, `@parent_id`,
`@subplans` — exactly as it was. Because `@id` is kept, the result is
*the same plan*, revised, rather than a derivative of it; that is the
difference from
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md),
which mints a new id and lineage.

## Usage

``` r
revise(plan, ...)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- ...:

  Named metadata fields to change: `name`, `nickname`, `advertiser`,
  `planner`, `status`, `objective`, `revision`. At least one.

## Value

The same plan (same `@id`) with the named fields changed.

## Details

This exists so that a consumer never has to rebuild a plan by naming its
slots by hand — the habit that silently drops any slot added later. Use
`revise()` for metadata,
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
for spend, and
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
/
[`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
for structure.

`@revision` is never bumped automatically. Planners say *Rev 2* when
they mean it, so it is set here explicitly. It prints in the header once
above 1.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", name = "Q3 plan"
)
q <- revise(p, status = "approved", revision = 2)
identical(q@id, p@id)
#> [1] TRUE
q@revision
#> [1] 2
```
