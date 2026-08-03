# Add a scenario to a set

Appends `plan` as a named scenario and returns a **new**
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md);
the input set is not mutated.

## Usage

``` r
add_scenario(set, plan, name = NULL)
```

## Arguments

- set:

  A
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  at the same grain as the set.

- name:

  Optional scenario label; defaults to the plan's `@nickname` if set,
  otherwise its `@name`. A unique suffix is appended on collision.

## Value

A new
[ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
with the scenario appended.
