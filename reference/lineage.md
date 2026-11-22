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

- `status`, `approved_on`:

  The scenario's own; `approved_on` is `NA` when unset.

- `revision`:

  Its place among the approved plans on its branch: 1 for the first
  approved, 2 for the next. `NA` unless approved.

- `current`:

  `TRUE` for an approved scenario with no approved descendant in the
  set.

- `spend`:

  Its total planned spend.

- `spend_vs_parent`, `spend_pct_vs_parent`:

  Against its parent; `NA` for a root.

## Details

The baseline is not privileged:
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
measures every scenario against the baseline, this measures each against
the plan it actually came from. On a set built by deriving from the base
they agree; on a chain — base, a scenario from it, a scenario from
*that* — they do not, and this is the one that reads as a tree.

## Revisions and the current approved plan

Planners say *Rev 3* meaning "the third approved version". That is a
fact about a plan's lineage, not about the plan, so it is derived here
rather than stored: an approved scenario's `revision` is how many
approved plans lie on the path from its root to it, itself included.
Plans that were drafted or sent back in between do not count.

The `current` approved plan is the one the agency is buying against: an
approved scenario with no approved scenario derived from it in the set.
When approvals happened on parallel branches, more than one can be
current; the set does not say which one won, and dates are not used to
guess. See
[`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md).

## See also

[`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md),
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)

## Examples

``` r
base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", time = "week", name = "base"
)
s1  <- build_scenario(base, list(target = list(channel = "Search"),
                                 total = 60), name = "Search up")
s2  <- build_scenario(s1, list(target = list(channel = "TV"), total = 70),
                      name = "and TV down")
set <- add_scenario(add_scenario(scenario_set(base), s1), s2)
lineage(set)
#>      scenario                         id                  parent_id    parent
#> 1        base plan_20261122212515_2599c4                       <NA>      <NA>
#> 2   Search up plan_20261122212515_e94a41 plan_20261122212515_2599c4      base
#> 3 and TV down plan_20261122212515_e6eb86 plan_20261122212515_e94a41 Search up
#>   depth         status approved_on revision current spend spend_vs_parent
#> 1     0                       <NA>       NA   FALSE   120              NA
#> 2     1 in development        <NA>       NA   FALSE   140              20
#> 3     2 in development        <NA>       NA   FALSE   130             -10
#>   spend_pct_vs_parent
#> 1                  NA
#> 2          0.16666667
#> 3         -0.07142857
```
