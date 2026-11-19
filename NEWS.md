# mediaplanr 0.2.0

The agent can act safely: a plan can be inspected compactly, edited only
through validated operations, held to its commitments, checked against its
budget, and audited afterwards.

## Breaking changes

* `@revision` is gone. A plan's revision is now derived from its lineage --
  its place among the approved plans on its branch -- by `lineage()`.
  `revise(revision = )` errors pointing there, and `media_plan_from_df()` no
  longer takes `revision`. Record an approval with
  `revise(status = "approved", approved_on = )` instead.
* JSON is now schema version 4. Files from versions 1-3 still read; a stored
  `revision` is ignored.
* Every op is checked before any is applied, so in a list of ops a malformed
  later op is reported before a plan-dependent problem in an earlier one.
* Op checking is stricter, and the same however the op was written:
  * `add` refuses `during`, which it used to ignore.
  * `set`, `scale` and `total` refuse negative values up front.
  * A `during` or `restage` window refuses fields other than `from` and `to`.
  * `add` needs both `flight_start` and `flight_end`, or neither.
* A `flight_id` named on a single-period `add` no longer attaches the new row
  to an existing flight.
* A `ScenarioSet` and `attach_subplan()` refuse plans whose `@spend_basis`
  differs.

## New features

* **Op constructors and schema.** `op_set()`, `op_scale()`, `op_delta()`,
  `op_delta_each()`, `op_total()`, `op_transfer()`, `op_add()`, `op_drop()`,
  `op_shift()`, `op_restage()` and `op_rebound()` build the same plain list a
  hand-written op is, and check it where it is written.
  `plan_ops_schema()` gives the same rules as a JSON Schema; with a plan, it
  narrows targets to the plan's values, the contract to hand an agent.
* **`transfer`** moves an amount between two sets of rows, leaving the plan's
  total unchanged, as one op. A destination that plans nothing is filled
  evenly by in-market days.
* **Spend bounds.** Optional `min_spend` / `max_spend` columns
  (`bound_cols()`) record commitments, floors and caps. Every edit respects
  them: group edits route around a bound, per-row edits are refused at one,
  and `drop`, `shift` and `restage` respect them too. They change only
  through the new `rebound` op. `line_item_summary()` reports
  `committed_spend` and `headroom`.
* **Provenance.** A derived plan records the edits that produced it in
  `@edits` -- replaying them on the parent reproduces it exactly -- and why,
  in `@rationale` (author, goal, constraints id, forecast, notes), set with
  `build_scenario(rationale = )`. `edit_log()` reads a set's records as a
  change log.
* **`describe_plan()`**: a compact summary of a plan for an agent's context --
  identity, shape, spend by column, commitments, units, spend by month, and
  what an op may target -- capped so it stays a few kilobytes at any size.
* **Approvals.** `@approved_on` records when a plan was approved.
  `lineage()` gains `approved_on`, `revision` and `current`;
  `current_approved()` returns the plan the set is buying against; and
  `compare_scenarios()` takes `against = "base" | "parent" |
  "current_approved"`.
* **`@spend_basis`** declares what the figures measure (`"media_net"`,
  `"client_net"`, `"gross"`, ...). A declaration, never a conversion.
* **`check_budget()`** checks a plan against a budget envelope -- windows and
  amounts naming any subset of the line item columns -- day by day, warning
  on any row off by more than a tolerance. `describe_plan(budget = )`
  summarises it.
* The example agency plan used throughout the tests ships as
  `system.file("extdata", "agency_plan.csv", package = "mediaplanr")`, and
  `vignette("getting_started")` walks through it end to end.

# mediaplanr 0.1.0

* First version: typed media plans at a configurable grain, flights, units,
  scenarios and comparison, subplans, and JSON serialization.
