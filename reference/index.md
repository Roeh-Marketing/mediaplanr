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
- [`line_item_summary()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_summary.md)
  : The roster of line items in a plan
- [`grain_values()`](https://roeh-marketing.github.io/mediaplanr/reference/grain_values.md)
  : The values present on a grain column
- [`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
  : Roll a plan up to a coarser grain

## Flight dates

When the plan is in market. Derived from the plan’s own rows, so it is
true of the plan alone – unlike a decomp’s through-date, which belongs
to a pairing and moves every refresh.

- [`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md)
  : The plan's flight window
- [`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md)
  : The weekday a plan's weeks begin on

## Flighting

A flight is how a buy is authored – in-market dates and a total. A week
is how the plan is held. Build a plan from flights and it expands onto
weekly rows exactly to the cent; flights() recovers the flights it was
authored from, and reports none rather than guessing when a plan records
no flight identity.

- [`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md)
  : Build a plan from flights rather than weeks
- [`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
  : The flights a plan was authored from
- [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
  : Re-cut a plan onto a different calendar
- [`flight_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_cols.md)
  : The columns that record flighting
- [`period_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/period_basis_levels.md)
  : The allowed buying cadences
- [`pacing_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/pacing_levels.md)
  : The allowed pacing patterns

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

## What a line item buys

Spend is the common currency and stays mandatory. Alongside it a line
item may record what it buys, how much of it, and at what price – bound
by one identity, so any two of the three give the third. The rate is
what survives an edit: a cut budget buys fewer impressions, it does not
win a better CPM.

- [`cost_per_unit()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md)
  [`cpm()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md)
  : The cost of one unit, and the cost per thousand
- [`unit_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/unit_cols.md)
  : The columns that record what a line item buys
- [`unit_type_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/unit_type_levels.md)
  : Unit types with a conventional rate basis

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
