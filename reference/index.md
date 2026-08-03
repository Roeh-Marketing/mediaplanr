# Package index

## The plan

Turn an uploaded table into a validated plan. A plan holds planned spend
on every row – intent, never actuals – at a configurable grain.

- [`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
  : Build a validated media plan from a data frame
- [`MediaPlan()`](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  : A media plan at a configurable grain

## Line items and grain

A line item is a channel / partner / tactic combination: the time-free
identity a decomp constrains and response models attach to. The grain
describes a whole row, which at a weekly grain is a line item for one
week.

- [`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
  : Line item identifier for each row
- [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
  : The grain columns that identify a line item, excluding the week
- [`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
  : Roll a plan up to a coarser grain

## Scenarios

Derive a new plan by changing spend, then collect the results into a set
to compare. Deriving never modifies the original, and every scenario
records the plan it came from.

- [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
  : Derive a new scenario plan from a base plan
- [`scenario_set()`](https://roeh-marketing.github.io/mediaplanr/reference/scenario_set.md)
  : Start a scenario set from a base plan
- [`add_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/add_scenario.md)
  : Add a scenario to a set
- [`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
  : Compare the scenarios in a set
- [`ScenarioSet()`](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md)
  : A base plan plus named scenarios derived from it

## Workflow status

The fixed vocabulary a plan’s status is validated against, so a UI
dropdown and the validator cannot disagree.

- [`status_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/status_levels.md)
  : The allowed plan workflow states

## Pairing a plan with a decomp

A plan alone is blind to past and future. Pair it with a decomp – which
reports actuals through a date – and questions about history become
answerable.

- [`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  : Check a plan against a decomp (the one pairing operation)

## Utilities

- [`short_id()`](https://roeh-marketing.github.io/mediaplanr/reference/short_id.md)
  : Abbreviate a synthetic id for printing
- [`print`](https://roeh-marketing.github.io/mediaplanr/reference/print.md)
  : Print methods for mediaplanr objects
