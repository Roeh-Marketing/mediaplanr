# Changelog

## mediaplanr 0.3.0

The agent can be scored and checked: its proposals map onto the response
models that score them, and are checked against one shared definition of
“allowed”.

### New features

- **[`model_map()`](https://roeh-marketing.github.io/mediaplanr/reference/model_map.md)**
  assigns every line item exactly one response model from a list fitted
  at mixed grains: of the models whose named values match, the most
  specific wins. A tie is an error naming both models; a line item no
  model covers is warned about, with the unmodeled share. Blank cells in
  the model list mean “any value”.
- **[`spend_by_model()`](https://roeh-marketing.github.io/mediaplanr/reference/spend_by_model.md)**
  sums each model’s spend by day, week or month – the input a
  response-model forecast needs. Unmodeled spend is kept under
  `model_id = NA`, so totals always reconcile. Data frames in and out;
  no dependency on `mrmopt`.
- **`PlanConstraints`**, built with
  **[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md)**
  from the **`rule_*()`** constructors or a rules sheet, holds the group
  rules a plan lives under: minimum and maximum spend or share, a fixed
  total with free phasing, and maximum change (an amount or a fraction)
  from a reference plan.
- **[`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md)**
  measures a plan against those rules, day by day, reporting each rule’s
  actual, limit, slack and whether it holds. A violation is warned
  about, never refused.
  **[`constraints_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/constraints_schema.md)**
  gives the rules as a JSON Schema, and
  [`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)
  /
  [`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
  round-trip a `PlanConstraints`.
- [`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md)
  gains `models` (coverage, and the largest unmodeled line items) and
  `constraints` / `reference` (rules broken, and rules holding with no
  slack left).
- The agency example ships with its response models and rules:
  `agency_models.csv` and `agency_constraints.csv` in `extdata`.
- New
  [`vignette("agentic_planning")`](https://roeh-marketing.github.io/mediaplanr/articles/agentic_planning.md):
  one turn of an agent’s loop on the agency plan – describe, propose, a
  refusal and a retry, score, check, and hand to a person to approve.

## mediaplanr 0.2.0

The agent can act safely: a plan can be inspected compactly, edited only
through validated operations, held to its commitments, checked against
its budget, and audited afterwards.

### Breaking changes

- `@revision` is gone. A plan’s revision is now derived from its lineage
  – its place among the approved plans on its branch – by
  [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md).
  `revise(revision = )` errors pointing there, and
  [`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
  no longer takes `revision`. Record an approval with
  `revise(status = "approved", approved_on = )` instead.
- JSON is now schema version 4. Files from versions 1-3 still read; a
  stored `revision` is ignored.
- Every op is checked before any is applied, so in a list of ops a
  malformed later op is reported before a plan-dependent problem in an
  earlier one.
- Op checking is stricter, and the same however the op was written:
  - `add` refuses `during`, which it used to ignore.
  - `set`, `scale` and `total` refuse negative values up front.
  - A `during` or `restage` window refuses fields other than `from` and
    `to`.
  - `add` needs both `flight_start` and `flight_end`, or neither.
- A `flight_id` named on a single-period `add` no longer attaches the
  new row to an existing flight.
- A `ScenarioSet` and
  [`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  refuse plans whose `@spend_basis` differs.

### New features

- **Op constructors and schema.**
  [`op_set()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_scale()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_delta()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_delta_each()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_total()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_transfer()`](https://roeh-marketing.github.io/mediaplanr/reference/op_transfer.md),
  [`op_add()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_drop()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_shift()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  [`op_restage()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
  and
  [`op_rebound()`](https://roeh-marketing.github.io/mediaplanr/reference/op_rebound.md)
  build the same plain list a hand-written op is, and check it where it
  is written.
  [`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
  gives the same rules as a JSON Schema; with a plan, it narrows targets
  to the plan’s values, the contract to hand an agent.
- **`transfer`** moves an amount between two sets of rows, leaving the
  plan’s total unchanged, as one op. A destination that plans nothing is
  filled evenly by in-market days.
- **Spend bounds.** Optional `min_spend` / `max_spend` columns
  ([`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md))
  record commitments, floors and caps. Every edit respects them: group
  edits route around a bound, per-row edits are refused at one, and
  `drop`, `shift` and `restage` respect them too. They change only
  through the new `rebound` op.
  [`line_item_summary()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_summary.md)
  reports `committed_spend` and `headroom`.
- **Provenance.** A derived plan records the edits that produced it in
  `@edits` – replaying them on the parent reproduces it exactly – and
  why, in `@rationale` (author, goal, constraints id, forecast, notes),
  set with `build_scenario(rationale = )`.
  [`edit_log()`](https://roeh-marketing.github.io/mediaplanr/reference/edit_log.md)
  reads a set’s records as a change log.
- **[`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md)**:
  a compact summary of a plan for an agent’s context – identity, shape,
  spend by column, commitments, units, spend by month, and what an op
  may target – capped so it stays a few kilobytes at any size.
- **Approvals.** `@approved_on` records when a plan was approved.
  [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
  gains `approved_on`, `revision` and `current`;
  [`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md)
  returns the plan the set is buying against; and
  [`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
  takes `against = "base" | "parent" | "current_approved"`.
- **`@spend_basis`** declares what the figures measure (`"media_net"`,
  `"client_net"`, `"gross"`, …). A declaration, never a conversion.
- **[`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md)**
  checks a plan against a budget envelope – windows and amounts naming
  any subset of the line item columns – day by day, warning on any row
  off by more than a tolerance. `describe_plan(budget = )` summarises
  it.
- The example agency plan used throughout the tests ships as
  `system.file("extdata", "agency_plan.csv", package = "mediaplanr")`,
  and
  [`vignette("getting_started")`](https://roeh-marketing.github.io/mediaplanr/articles/getting_started.md)
  walks through it end to end.

## mediaplanr 0.1.0

- First version: typed media plans at a configurable grain, flights,
  units, scenarios and comparison, subplans, and JSON serialization.
