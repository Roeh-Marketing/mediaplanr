# The approved plan a set is currently buying against

Of the approved scenarios in a set, the ones nothing approved has been
derived from since: the latest approval on each branch of the lineage.
On a chain of approvals – Rev 1, Rev 2, Rev 3 – that is one plan.

## Usage

``` r
current_approved(set)
```

## Arguments

- set:

  A
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

## Value

The scenario name(s) of the current approved plan(s).

## Details

It is not always one. With no approved scenario in the set there is
none, and this returns `character(0)` with a message. When plans were
approved on parallel branches, each is current on its own branch; the
set does not record which one superseded the other, so all of them are
returned with a warning. Approval dates are never used to break the tie
– a date says when someone signed, not which plan replaced which.

## See also

[`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md),
where the same plans are flagged `current` and every approved plan
carries its `revision`.

## Examples

``` r
base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", time = "week", name = "base",
  status = "approved", approved_on = "2026-06-01"
)
rev2 <- revise(build_scenario(base, op_scale(1.1), name = "Rev 2"),
               status = "approved", approved_on = "2026-06-20")
draft <- build_scenario(rev2, op_scale(0.9), name = "Draft cut")
set <- add_scenario(add_scenario(scenario_set(base), rev2), draft)

current_approved(set)
#> [1] "Rev 2"
lineage(set)[, c("scenario", "status", "revision", "current")]
#>    scenario         status revision current
#> 1      base       approved        1   FALSE
#> 2     Rev 2       approved        2    TRUE
#> 3 Draft cut in development       NA   FALSE
```
