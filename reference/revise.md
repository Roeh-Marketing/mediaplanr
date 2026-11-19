# Revise a plan's metadata without changing what it plans

The metadata-only edit verb. Changes any of `name`, `nickname`,
`advertiser`, `planner`, `status`, `approved_on`, `objective`,
`spend_basis` and `rationale`, and leaves everything else — `@data`,
`@grain`, `@id`, `@parent_id`, `@subplans`, `@edits` — exactly as it
was. `rationale` is here because it describes the plan, not its spend:
an author or a forecast can be added after the fact.

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
  `planner`, `status`, `approved_on` (a `Date` or ISO string; only on an
  approved plan), `objective`, `spend_basis` (a correction, not a
  conversion), `rationale` (see
  [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)).
  At least one.

## Value

The same plan (same `@id`) with the named fields changed.

## Details

`spend_basis` is here as a **correction to a declaration**, never a
conversion. A plan imported as `"media_net"` whose figures were in fact
client net is corrected with `revise(spend_basis = "client_net")`, and
its numbers do not change. Turning media net into client net means
applying a fee schedule, which is the caller's job.

Because `@id` is kept, the result is *the same plan*, revised, rather
than a derivative of it; that is the difference from
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md),
which mints a new id and lineage.

This exists so that a consumer never has to rebuild a plan by naming its
slots by hand — the habit that silently drops any slot added later. Use
`revise()` for metadata,
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
for spend, and
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
/
[`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
for structure.

Approval is set here:
`revise(status = "approved", approved_on = "2026-10-29")`. The date is
optional and never defaulted to today, and moving the status off
`"approved"` clears it. There is no revision number to set: planners say
*Rev 3* meaning "the third approved version", which is a fact about the
plan's lineage rather than the plan, so
[`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
derives it, and
[`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md)
finds the latest.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", time = "week", name = "Q3 plan"
)
q <- revise(p, status = "approved", approved_on = "2026-10-29")
identical(q@id, p@id)
#> [1] TRUE
q@approved_on
#> [1] "2026-10-29"

# sending it back for review withdraws the approval and its date
revise(q, status = "to review")@approved_on
#> Date of length 0
```
