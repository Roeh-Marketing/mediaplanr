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
  : The grain columns that identify a line item, excluding time
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
  : Build a plan from flights rather than periods
- [`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
  : The flights a plan was authored from
- [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
  : Re-cut a plan onto a different calendar
- [`flight_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_cols.md)
  : The columns that record flighting
- [`period_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/period_basis_levels.md)
  : The allowed buying cadences
- [`time_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/time_basis_levels.md)
  : What one value of a plan's time column stands for
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

## Describing a plan to an agent

A compact, capped summary of a plan – what it spends and on what, what
cannot move, when it spends, what an op may target – that stays the same
size however big the plan is, and reconciles to its rows.

- [`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md)
  : A compact description of a plan, for an agent's context

## Edit operations

The operations build_scenario() applies, as constructors and as one JSON
Schema. An op is a plain list, so one built by a constructor, one
written by hand and one parsed from an agent’s tool call are the same
object; the schema, narrowed to a plan, is the contract to hand an
agent.

- [`op_set()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_scale()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_delta()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_delta_each()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_total()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_add()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_drop()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_shift()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  [`op_restage()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  : Build an edit op
- [`op_transfer()`](https://roeh-marketing.github.io/mediaplanr/reference/op_transfer.md)
  : Build a transfer op: move money between line items
- [`op_rebound()`](https://roeh-marketing.github.io/mediaplanr/reference/op_rebound.md)
  : Build a rebound op: change what spend rows may hold
- [`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
  : JSON Schema for the edits an agent may send

## Spend that cannot move

An upfront commitment, a partner floor, a cap: recorded per row as
min_spend and max_spend, respected by every edit, and changed only by an
explicit rebound. Whether a row is committed is derived from its bounds,
never stored.

- [`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)
  : The columns that record a row's spend bounds

## Subplans and revising a plan

A channel team plans its own detail, at its own grain and cadence, and
it rolls up into one cell of the topline. Attaching makes that cell’s
rows the subplan’s rollup and locks them, so there is one number with
one owner; re-attaching is the reconcile. revise() edits metadata –
status and approval among it – on the same plan without touching what it
plans.

- [`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  [`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  [`is_topline()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  : Attach a subplan to the cell of the plan it refines
- [`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md)
  : Revise a plan's metadata without changing what it plans

## Structure and lineage

What hangs beneath a plan, and where a scenario came from. Projections
for something else to render – a table a UI builds a tree from, a
lineage table over a set, a Mermaid string – plus a console tree,
because the console is where a planner looks first.

- [`plan_tree()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_tree.md)
  : Print a plan's subplan tree
- [`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md)
  : The subplan tree as a table
- [`ownership_map()`](https://roeh-marketing.github.io/mediaplanr/reference/ownership_map.md)
  : Who owns each cell of a plan
- [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
  : The derivation tree of a scenario set
- [`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md)
  : The approved plan a set is currently buying against
- [`edit_log()`](https://roeh-marketing.github.io/mediaplanr/reference/edit_log.md)
  : The edits behind every scenario in a set, one row per op
- [`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md)
  : A plan's structure, or a set's lineage, as a Mermaid diagram

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

## Pairing a plan with a decomp or a budget

A plan alone is blind to past and future, and to what it was authorised
to spend. Pair it with a decomp – which reports actuals through a date –
and questions about history become answerable; pair it with a budget
envelope and it can be checked against its signed limits. Both warn
rather than error: each artifact is valid, it is the pairing that
disagrees.

- [`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  : Check a plan against a decomp (the one pairing operation)
- [`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md)
  : Check a plan against a budget envelope

## Handing spend to response models

Response models are fitted at whatever grain the data supported, often
not the plan’s, and sometimes several at once. Map each line item to
exactly one model – the most specific that matches – and sum its spend
by period: the input a forecast needs. Unmodeled spend is kept, and
said.

- [`model_map()`](https://roeh-marketing.github.io/mediaplanr/reference/model_map.md)
  : Which response model scores each line item
- [`spend_by_model()`](https://roeh-marketing.github.io/mediaplanr/reference/spend_by_model.md)
  : The spend each response model scores, period by period

## Rules a plan must keep

The group rules a plan lives under – a share floor, a fixed upfront
total, a cap on how far a channel may move from the approved plan –
written once, so the agent checking its own proposal and the optimizer
read the same definition of “allowed”. A violation is reported, never
refused.

- [`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md)
  : Build a set of plan rules
- [`rule_min_spend()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  [`rule_max_spend()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  [`rule_fixed_total()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  [`rule_min_share()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  [`rule_max_share()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  [`rule_max_change_abs()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  [`rule_max_change_pct()`](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
  : Build a plan rule
- [`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md)
  : Check a plan against its rules
- [`constraints_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/constraints_schema.md)
  : JSON Schema for the rules an agent may write
- [`PlanConstraints()`](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md)
  : A set of rules a plan must keep

## Saving and reloading

Persist a plan or a whole scenario set as JSON and rebuild it. The
rebuild goes back through media_plan_from_df(), so it is re-validated
and its unit identity re-solved; id and lineage survive, and flighted or
mixed plans need no special path.

- [`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)
  : Serialize a media plan or scenario set to JSON
- [`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
  : Rebuild a media plan or scenario set from JSON

## Utilities

- [`short_id()`](https://roeh-marketing.github.io/mediaplanr/reference/short_id.md)
  : Abbreviate a synthetic id for printing
- [`print`](https://roeh-marketing.github.io/mediaplanr/reference/print.md)
  : Print methods for mediaplanr objects
