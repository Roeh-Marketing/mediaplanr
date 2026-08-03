# Compare the scenarios in a set

Collects the scenarios into a comparison table over **planned
planned_spend** at one of two levels:

## Usage

``` r
compare_scenarios(set, level = c("summary", "cell"))
```

## Arguments

- set:

  A
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

- level:

  One of `"summary"` or `"cell"`.

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

## Examples

``` r
base <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", name = "base"
)
set <- scenario_set(base)
set <- add_scenario(set, build_scenario(base, edits = c("Search" = 120),
                                        name = "Search boost"))
compare_scenarios(set)
#>       scenario                    plan_id                  parent_id
#> 1         base plan_20260803221135_fe3218                       <NA>
#> 2 Search boost plan_20260803221135_81f9be plan_20260803221135_fe3218
#>   total_planned_spend spend_vs_base spend_pct_vs_base
#> 1                 120             0         0.0000000
#> 2                 200            80         0.6666667
compare_scenarios(set, "cell")
#>       scenario channel planned_spend share_of_total spend_vs_base
#> 1         base      TV            80      0.6666667             0
#> 2         base  Search            40      0.3333333             0
#> 3 Search boost      TV            80      0.4000000             0
#> 4 Search boost  Search           120      0.6000000            80
```
