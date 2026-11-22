# mediaplanr 0.4.0

One master plan, several planners: the plan can say which rows a section of
the client's organization holds, whether a planner's ops stay inside their
scope, and whether a draft written under one revision still means the same
thing on the current one. A section is a target and a scope is a list of
targets, so nothing new is stored; and every verb resolves rows through the
matcher the edits use, so the app never has to match rows itself.

## New features

* **`match_rows()`** returns the rows a target selects, exactly as an op's
  `target` and `during` resolve them. It takes one target or a list of
  targets (AND within a target, OR across the list). `strict = TRUE` errors
  as an op does; `strict = FALSE` lets a value the plan no longer has match
  nothing. It reads rows a subplan owns rather than refusing them.
* **`assign_sections()`** places every line item in the leaves of an
  organization tree. Line items in two sections, or in none, are listed
  beneath the table and in attributes -- never an error.
* **`ops_within()`** checks that every row a list of ops would touch lies
  inside a scope, in order, so an `add` creates rows a later op may target.
  One row per op side that reaches outside; zero rows means every op stays
  in. Takes ops however written, or a scenario's `@edits`.
* **`rebase_check()`** compares the rows a draft's ops touch on the revision
  it was written under and on the current one: spend, bounds and flight
  columns, plus rows present on only one. Zero rows means replaying the ops
  on the current revision does what they did on the base.
* **`regrain()`** adds an organization level -- a funnel over channels -- as
  a grain column read off an existing one, refusing values with no group or
  two. The plan keeps its id, lineage, approval and provenance; stored
  `add`s and allocations gain the column, so `@edits` still replay.
* `vignette("agentic_planning")` gains a section running the master-plan
  case end to end: a plan regrained by funnel, two scoped drafts, one op
  refused, approvals replayed onto one chain, and a stale draft caught.

## Internal

* The op matcher's read path is split from its subplan refusal
  (`.find_rows()` / `.select_rows()`), so `match_rows()` and its kin read
  what every edit door still refuses.

# mediaplanr 0.3.0

The agent can be scored and checked: its proposals map onto the response
models that score them, and are checked against one shared definition of
"allowed".

## New features

* **`model_map()`** assigns every line item exactly one response model from
  a list fitted at mixed grains: of the models whose named values match, the
  most specific wins. A tie is an error naming both models; a line item no
  model covers is warned about, with the unmodeled share. Blank cells in the
  model list mean "any value".
* **`spend_by_model()`** sums each model's spend by day, week or month -- the
  input a response-model forecast needs. Unmodeled spend is kept under
  `model_id = NA`, so totals always reconcile. Data frames in and out; no
  dependency on `mrmopt`.
* **`PlanConstraints`**, built with **`plan_constraints()`** from the
  **`rule_*()`** constructors or a rules sheet, holds the group rules a plan
  lives under: minimum and maximum spend or share, a fixed total with free
  phasing, and maximum change (an amount or a fraction) from a reference
  plan.
* **`check_constraints()`** measures a plan against those rules, day by day,
  reporting each rule's actual, limit, slack and whether it holds. A
  violation is warned about, never refused. **`constraints_schema()`** gives
  the rules as a JSON Schema, and `plan_to_json()` / `plan_from_json()`
  round-trip a `PlanConstraints`.
* `describe_plan()` gains `models` (coverage, and the largest unmodeled line
  items) and `constraints` / `reference` (rules broken, and rules holding
  with no slack left).
* The agency example ships with its response models and rules:
  `agency_models.csv` and `agency_constraints.csv` in `extdata`.
* New `vignette("agentic_planning")`: one turn of an agent's loop on the
  agency plan -- describe, propose, a refusal and a retry, score, check, and
  hand to a person to approve.

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
