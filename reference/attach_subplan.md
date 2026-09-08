# Attach a subplan to the cell of the plan it refines

A **subplan** is a full
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
owned by the team that plans one line item's detail — the TV plan by
partner and daypart, daily, beneath a `channel + week` topline.
Attaching it makes the parent's rows for that cell *derived from* the
subplan: they are replaced by the subplan's rollup and become read-only,
so there is one number with one owner. To change TV's total, change the
TV plan and attach it again; re-attaching **is** the reconcile.

## Usage

``` r
attach_subplan(parent, subplan)

detach_subplan(parent, key)

is_topline(plan)
```

## Arguments

- parent:

  The topline
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- subplan:

  The
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  refining one of its cells.

- key:

  For `detach_subplan()`, the cell to release — a name from
  `names(parent@subplans)`, e.g. `"TV"` or `"TV | NBC"`.

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Value

`attach_subplan()` and `detach_subplan()` return the parent with its
`@subplans` and rows updated. `is_topline()` returns `TRUE` when the
plan holds any subplan.

## Which cell

The subplan says which cell it backs through its **data**, not through
an argument. Its
[`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
must *contain* the parent's — the same columns or more — and across the
parent's columns its rows must hold exactly one combination:
`channel == "TV"` on every row. That is the cell. A subplan whose rows
span two channels is refused; it would be a plan, not a refinement.

## Cadence

A weekly parent needs a subplan with a week column; its spend is re-cut
onto the parent's weeks with
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
before the rollup, so daily flights or a different week start land
correctly. A parent with no time dimension accepts any subplan and
collapses time as
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
would.

## What attaching changes

Only the parent. It keeps its `@id` and `@revision`; its rows at the
cell are replaced — weeks the subplan does not plan disappear, weeks it
adds appear — and the subplan is held in `@subplans` under the cell's
key. The subplan itself is untouched, `@parent_id` included: lineage
records what a plan was *derived from*, and a subplan is authored, not
derived. Attaching to a cell the parent does not yet have simply adds
it.

The parent's backed rows refuse every edit —
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
errors *"channel TV is planned in a subplan; edit the subplan and
re-attach"* — which means a whole-plan op like `list(total = 200)`
errors on a topline. Ops that avoid backed rows work, and the scenario
carries the subplans.
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
drops them, since a rollup is a coarser view.

A subplan is a `MediaPlan`, so it may hold subplans of its own. A plan
cannot be attached beneath itself.

## Examples

``` r
topline <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(100, 40)),
  grain = "channel", name = "Q3 topline"
)
tv <- media_plan_from_df(
  data.frame(channel = "TV", partner = c("NBC", "ESPN"),
             planned_spend = c(70, 50)),
  grain = c("channel", "partner"), name = "TV detail"
)
p <- attach_subplan(topline, tv)
p@data                      # TV is now 120, from the subplan
#>   channel planned_spend
#> 1  Search            40
#> 2      TV           120
is_topline(p)
#> [1] TRUE

# TV is owned by its subplan
try(build_scenario(p, list(target = list(channel = "TV"), scale = 2),
                   name = "double TV"))
#> Error : edit op 1: channel TV is planned in a subplan; edit the subplan and re-attach.

detach_subplan(p, "TV")@subplans
#> list()
```
