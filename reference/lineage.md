# The derivation tree of a scenario set

Each scenario records the plan it was derived from in `@parent_id`; a
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
is where enough of those plans sit together for the edges to be drawn.
One row per scenario, pointing at its parent **within the set** and
carrying what changed against it. A scenario whose parent is not in the
set is a root here — lineage as far as the set records it.

## Usage

``` r
lineage(set)
```

## Arguments

- set:

  A
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

## Value

A data frame with one row per scenario:

- `scenario`, `id`, `parent_id`:

  Its label and identity.

- `parent`:

  The label of its parent in the set; `NA` for a root.

- `depth`:

  0 for a root, parent's depth + 1 otherwise.

- `status`, `revision`, `spend`:

  The scenario's own.

- `spend_vs_parent`, `spend_pct_vs_parent`:

  Against its parent; `NA` for a root.

## Details

The baseline is not privileged:
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
measures every scenario against the baseline, this measures each against
the plan it actually came from. On a set built by deriving from the base
they agree; on a chain — base, a scenario from it, a scenario from
*that* — they do not, and this is the one that reads as a tree.

## See also

[`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md),
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)

## Examples

``` r
base <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", name = "base"
)
s1  <- build_scenario(base, c(Search = 60), name = "Search up")
s2  <- build_scenario(s1, c(TV = 70), name = "and TV down")
set <- add_scenario(add_scenario(scenario_set(base), s1), s2)
lineage(set)
#>      scenario                         id                  parent_id    parent
#> 1        base plan_20260916002725_95c3ff                       <NA>      <NA>
#> 2   Search up plan_20260916002725_09fda0 plan_20260916002725_95c3ff      base
#> 3 and TV down plan_20260916002725_7463a2 plan_20260916002725_09fda0 Search up
#>   depth         status revision spend spend_vs_parent spend_pct_vs_parent
#> 1     0                       1   120              NA                  NA
#> 2     1 in development        1   140              20          0.16666667
#> 3     2 in development        1   130             -10         -0.07142857
```
