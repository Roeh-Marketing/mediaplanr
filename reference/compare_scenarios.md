# Compare the scenarios in a set

Collects the scenarios into a comparison table over **planned
planned_spend** at one of two levels:

## Usage

``` r
compare_scenarios(
  set,
  level = c("summary", "cell", "flight"),
  against = c("base", "parent", "current_approved")
)
```

## Arguments

- set:

  A
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

- level:

  One of `"summary"`, `"cell"` or `"flight"`.

- against:

  What each scenario is compared against: `"base"`, `"parent"` or
  `"current_approved"`. See *What each scenario is compared against*.

## Value

A data frame.

## Details

- `"summary"` (default): one row per scenario — total planned_spend and
  the delta versus the baseline.

- `"cell"`: one row per scenario x grain cell, over the **union** of
  grain cells across the whole set — planned spend, that cell's share of
  the scenario total, and the delta versus the same cell in the
  baseline.

The union matters when scenarios are authored independently rather than
derived — one plan per tab of a workbook, say — because their row sets
need not match. A cell absent from a scenario means it plans no spend
there, so it is zero-filled rather than omitted. Without that, a
scenario that *drops* a line item would simply have no row for it and
the cut would be invisible, while one that *adds* a line item would
report `NA` instead of the full amount. Scenarios built with
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
always share their parent's row set, so for those the result is
unchanged.

Predicted outcomes are not computed here. To compare modeled volume,
forecast the scenarios with `mrmopt` and join the result on `scenario` +
the grain columns.

## Comparing flights

`level = "flight"` compares the **buys** rather than the cells: one row
per scenario per flight, joined on `flight_id`, with what happened to it
named in a `change` column — `moved`, `resized`, `moved & resized`,
`added`, `dropped`, `repaced` or `unchanged`.

This is the thing cell-level cannot say. A flight pushed a week later
shows at cell level as money leaving one week and arriving in another,
which is true but leaves the reader to infer that a single buy moved.
Here it is one row saying so.

It works by **lineage**. `flight_id` is minted per import, so it
identifies the same buy across a plan and the scenarios derived from it,
and does *not* match across independently-authored plans — which would
report one buy as two. When the set shares no flight ids at all, this
warns rather than returning a table of spurious adds and drops. A set
whose plans record no flights returns no rows, the same way
[`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
does.

## What each scenario is compared against

`against` chooses the reference every delta is measured from:

- `"base"` (default) – the set's baseline, for every scenario.

- `"parent"` – each scenario's own parent in the set, the way
  [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
  reads it. A root has no parent here, so its deltas are `NA`.

- `"current_approved"` – the plan the set is currently buying against;
  see
  [`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md).
  It must be exactly one plan, or this errors: with none there is
  nothing to compare to, and with several the reference would be a
  guess.

The delta columns are named for the reference: `spend_vs_base`,
`spend_vs_parent` or `spend_vs_current_approved` (and the matching
`spend_pct_vs_*` at summary level).

## Examples

``` r
base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", time = "week", name = "base"
)
set <- scenario_set(base)
set <- add_scenario(set, build_scenario(
  base, edits = list(target = list(channel = "Search"), total = 120),
  name = "Search boost"))
compare_scenarios(set)
#>       scenario                    plan_id                  parent_id
#> 1         base plan_20261119173006_45a909                       <NA>
#> 2 Search boost plan_20261119173006_09fda0 plan_20261119173006_45a909
#>   total_planned_spend spend_vs_base spend_pct_vs_base
#> 1                 120             0         0.0000000
#> 2                 200            80         0.6666667
compare_scenarios(set, "cell")
#>       scenario channel       week planned_spend share_of_total spend_vs_base
#> 1         base      TV 2026-07-06            80      0.6666667             0
#> 2         base  Search 2026-07-06            40      0.3333333             0
#> 3 Search boost      TV 2026-07-06            80      0.4000000             0
#> 4 Search boost  Search 2026-07-06           120      0.6000000            80
```
