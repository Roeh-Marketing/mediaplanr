# A base plan plus named scenarios derived from it

`ScenarioSet` is the comparison registry: a base plan and the scenarios
derived from it, all at one grain. Each entry is a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md);
the set adds names, a designated baseline, and comparison over
planned_spend.

## Usage

``` r
ScenarioSet(
  scenarios = list(),
  grain = character(0),
  base_name = "base",
  id = new_id("set")
)
```

## Arguments

- scenarios:

  Named list of
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  objects, all at the same grain.

- grain:

  Character vector; the common plan grain.

- base_name:

  Name of the baseline scenario (used for deltas).

- id:

  Opaque synthetic id.

## Value

A `ScenarioSet` S7 object.

## Details

Build one with
[`scenario_set()`](https://roeh-marketing.github.io/mediaplanr/reference/scenario_set.md)
and grow it with
[`add_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/add_scenario.md);
both return new objects (value semantics — the set being compared
against is never mutated).

The set holds **plan intent only**. Predicted outcomes come from a
separate modeling process (e.g. `mrmopt`); join them to
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
output by scenario name and grain columns.
