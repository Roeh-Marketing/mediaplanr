# mediaplanr — Implementation Plan (Nov 2026, rev 2)

Hand-off plan for Claude Code. Read this whole file, then `Roadmap.md` and
`vignette("plan_concepts")`, before writing code. The Roadmap's "Decided"
sections are binding unless this plan explicitly amends them.

**Goal of this run:** make mediaplanr the plan-state and action layer of an
**agentic media planner**: an agent can inspect a plan compactly, act on it
only through validated ops, never violate commercial commitments, be scored
by mrmopt at the right grain, check itself against the same constraints the
optimizer uses, and leave an auditable record of what it changed and why.

Rev 2 adds: spend bounds (commitments), structured rationale,
`describe_plan()`, a model-to-plan grain map, and a shared constraint object.

---

## 0. Why this plan exists

The package was stress-tested against a real agency national digital plan
(Q4 2026, ~266 monthly line items across streaming, programmatic and YouTube;
27 workbook tabs), then reviewed for fitness as an agent's substrate.

Plan-modelling findings:

- **Validated:** the flat table at a configurable grain. Every flowchart,
  finance pivot and QA tab in the workbook is a `roll_up()` + `calendarize()`
  view of one long table.
- **Most common real edit is a zero-sum transfer** ("move $X from partner A in
  Feb to partner B in Feb"). The workbook keeps a 230-row change log of exactly
  these. Today that is two `delta` ops whose pairing is lost.
- **Much of the spend is not movable.** Upfront direct-IO commitments,
  partner minimums and already-spent months are fixed. Nothing in the model
  says so.
- **Approvals form a dated chain** (five approved versions in one year). The
  package cannot say which approved version is current, and `@revision`
  resets to 1 on every derivation — the opposite of what a planner means by
  "Rev 2".
- **The real "topline" is a budget envelope**, not a subplan: signed channel ×
  quarter authorizations checked with tolerated variance.
- **Spend has two bases** (media net vs. client net incl. fees); nothing
  declares which one a plan holds.
- **Credit rows are negative.** The non-negative validator is correct —
  credits are billing reconciliation, not intent — but the docs must say so.

Agent-readiness findings:

- **Strong already:** value semantics, validator on every construction, ops
  as data, errors that list alternatives, lineage + status. An agent cannot
  corrupt a plan, and every proposal is an inspectable scenario.
- **Missing:** (1) commitments the edit path respects; (2) a compact,
  bounded plan summary for the agent's context; (3) a deterministic map from
  plan line items to mrmopt response models; (4) one constraint object both
  the agent's self-check and the optimizer read; (5) structured rationale on
  each proposal.
- **API style:** consumers are LLM agents (JSON tool calls, or generated R).
  Tidy-eval / dplyr methods / per-step pipe verbs are rejected (Phase 0
  records why). Op constructors + one JSON Schema are the chosen interface.

Responsibility split (record in the Roadmap, Phase 0):
**mediaplanr** = plan state, legal actions, constraints, checks, history.
**mrmopt** = scoring and optimization. **The app** = the agent loop and the
human approval gate.

---

## 1. Standing rules (apply to every phase)

- Read the existing code before changing it. Follow its conventions; do not
  restyle untouched code.
- Explicit `S7::` namespacing. No new hard dependencies (current Imports:
  `S7`, `jsonlite`, `stats`, `utils` — keep it that way).
- **Every copy goes through `.copy_plan()`.** New slots are carried by
  default; any constructor that must *reset* a slot does so explicitly and
  has a test proving it.
- **Nothing derived is stored; nothing from `Sys.Date()`.** If a value can
  change without the plan changing, it is a function argument or a projection,
  never a slot.
- Errors name the fix. Mistyped targets error with alternatives. Pairing
  checks (plan vs. external artifact: decomp, budget, models, constraints)
  **warn** and return a table; structural problems **error**.
- No guessing: where intent is ambiguous, error naming the explicit form.
- Everything an agent receives or sends is JSON-representable: plain lists
  and data frames, ISO dates, no closures, no environments.
- Tests written alongside code (testthat 3e). Run `devtools::test()` after
  every phase and `devtools::check()` at the end of every phase; both clean
  before moving on. One commit per phase (or per sub-step if large), message
  prefixed with the phase number.
- New settable slots are serialized automatically via `.settable_props()`;
  verify the JSON round-trip for each one. **Bump `.plan_schema_version` to 4
  exactly once** (first phase that adds a slot, Phase 4) and keep all new
  fields optional on read so v1–v3 files still load.
- Reserved `@data` columns (like `flight_id`, `pacing`, `unit_type`) travel
  through JSON with `@data`; confirm round-trip for any new one.
- Use synthetic fixtures only. No client names anywhere — this repo is public.
- `describe_plan()` (Phase 5) is the agent's view of a plan: every later
  phase that adds a plan fact adds it there too, with a test.

---

## 2. Decisions Ben confirms before the run

Defaults below are what to implement if unchanged.

| # | Decision | Default |
|---|----------|---------|
| D1 | `@revision` | **Remove the slot**; revision becomes a lineage projection (Phase 6). |
| D2 | `transfer` into a destination whose current spend is 0 | **Spread evenly by in-market days** across matched rows (same rule as an even flight). |
| D3 | Provenance for data-frame / named-vector edits | **Store the allocation as given**, so every derivation is replayable. |
| D4 | `@spend_basis` vocabulary | **Free text**, documented common values; strict equality where plans combine. |
| D5 | Group ops (`delta`, `total`, `transfer`) touching bounded rows | **Bounds-aware:** distribute proportionally across rows with headroom, clipping at bounds (water-filling); error only if infeasible. Single-row ops (`set`, `scale`, `delta_each`) that breach a bound error. |
| D6 | Granularity of commitments | **Row-level bounds in `@data`** (per line item per period). Flight- or line-total commitments ("$300K upfront, phasing flexible") are group constraints in Phase 10. |
| D7 | Release split | **0.2.0** after Phase 8; **0.3.0** after Phase 10. |

---

## Release 0.2.0 — the agent can act safely

### Phase 0 — Roadmap & doc housekeeping (docs only)

1. `Roadmap.md`
   - Replace the stray, indented `## Tydification` stub with an **"API style —
     decided"** section:
     - In: plan-first arguments, pure functions returning the same class,
       standard evaluation, `op_*()` constructors, one JSON Schema.
     - Out, with reasons: dplyr generics on `MediaPlan` (bypass validation,
       units identity, subplan locks, flight identity, spend bounds);
       tidy-eval / bare column names (not JSON-serializable, unusable by
       tool-calling agents); per-step mutating pipe verbs (each step would
       mint a lineage generation — one intent must be one scenario).
       Read-only projections may be piped freely.
   - Add an **"Agentic planner: responsibility split"** section (text in §0
     above), and the agent loop it supports: describe → propose ops →
     validate → score (mrmopt, via the model map) → check constraints →
     record rationale → human approves.
   - **SubPlans:** add a "Status: held" note — built and tested at one level;
     no further investment (depth, staleness detection) and not exposed in
     the app until a real multi-owner engagement needs it. Point to
     `check_budget()` (Phase 8) as the common envelope case.
   - Move items to "Already grown" as phases land.
2. `vignette("plan_concepts")`: fix "imports nothing but S7" (jsonlite,
   stats, utils are imported). Add a short **"Credits are not intent"**
   subsection: negative billing adjustments stay out of `@data`; net them into
   the line's planned spend only if they change planned media, otherwise keep
   them in a separate adjustments table outside the plan.

Done when: `devtools::check()` clean, vignettes build.

---

### Phase 1 — Op registry, `op_*()` constructors, `plan_ops_schema()`

Pure refactor + additions; no behavior change to existing ops.

1. **Registry.** In `R/verbs.R` (or new `R/ops.R`, add to `Collate`), define
   `.op_registry`: one entry per op key with its family (value/structural),
   fields, field types, required/optional, and one-line description.
   Derive `.value_ops`, `.structural_ops`, `.op_keys`, and the allowed-field
   check in `.apply_op()` from it, so there is one source of truth.
2. **Constructors** (exported, documented, examples):
   `op_set()`, `op_scale()`, `op_delta()`, `op_delta_each()`, `op_total()`,
   `op_add()`, `op_drop()`, `op_shift()`, `op_restage()` (and `op_transfer()`
   in Phase 2).
   - Each returns a **plain list identical** to the hand-written op (no
     class attribute), so constructor-built, hand-built and JSON-parsed ops
     are interchangeable.
   - Validate plan-independent arguments at construction (types, lengths,
     `during` shape, ISO date strings parse). Plan-dependent validation stays
     in `.apply_op()`.
   - Signature pattern: `op_scale(by, target = NULL, during = NULL)`.
3. **`plan_ops_schema(plan = NULL, as_json = FALSE)`** → JSON Schema for the
   `edits` array, built from the registry (`oneOf` over op shapes).
   - With `plan` supplied, narrow `target` property names to
     `line_item_grain(plan)` and their values to `grain_values()` enums, and
     the time format to the plan's basis. This is the agent-facing contract.
4. Update `?build_scenario` examples to show constructors alongside raw lists.

Tests: every constructor `identical()` to its raw-list equivalent; invalid
args error at construction; registry-derived `.op_keys` equals the old
constant; schema validates a corpus of known-good ops and rejects known-bad
ones (a small recursive checker in the test helper — no new dependency);
plan-aware schema enumerates the fixture's grain values.

---

### Phase 2 — `transfer` op

Shape (constructor `op_transfer(amount, from, to, during = NULL,
from_during = NULL, to_during = NULL)`):

```r
list(transfer = 37419,
     from = list(partner = "DSP A"),
     to   = list(tactic  = "Regional"),
     during = list(from = "2026-10-01", to = "2026-10-31"))
```

Semantics:
- `amount` > 0, single number. `from` / `to` are targets (same rules as
  `target`). `transfer` takes no `target`.
- `during` applies to both sides; `from_during` / `to_during` override per
  side. Supplying `during` and a per-side override for the same side errors.
- Source side behaves like `delta = -amount`; destination like
  `delta = +amount` when its current sum > 0; when it is 0, apply **D2**
  (even by in-market days across matched rows, using the flights' day-span
  helper). Document on `?op_transfer`.
- **Implement distribution through one internal helper** (e.g.
  `.distribute(ps, change, weights, lower, upper)`) used by `delta`, `total`
  and `transfer`. In this phase `lower = 0`, `upper = Inf`; Phase 3 feeds it
  real bounds. This keeps D5 a one-place change.
- Source and destination row sets must be disjoint → else error.
- Destination matching no rows → error naming `add` (introduce the line item
  first, in the same edits list).
- Subplan-backed rows on either side → the existing `.stop_if_backed()` error.
- Post-condition: total planned spend unchanged within cent tolerance
  (internal assertion — a failure is a bug).
- Units and pacing re-derive in `.apply_edits()` already — verify, do not
  duplicate.

Tests: budget neutrality across grains; proportional source; zero-destination
spread (weekly with ragged flight, daily, monthly); per-side windows; overlap
error; below-zero error; no-match destination error; subplan lock; units
follow at held rate; flight stays `"even"` under proportional moves;
`compare_scenarios(level = "flight")` unaffected. Replace the "Move 10 from TV
to Search" two-`delta` example with `op_transfer()`.

---

### Phase 3 — Spend bounds (commitments)

Make "this money cannot move" a fact in the plan that every edit respects.

1. **Reserved optional `@data` columns `min_spend` and `max_spend`**
   (numeric, `NA` = unbounded). Authored at import
   (`media_plan_from_df()`, `media_plan_from_flights()` pass them through) or
   via `op_add()`. Nothing else is stored.
   - Validator: `0 <= min_spend <= planned_spend <= max_spend` wherever
     bounds are present (cent tolerance). Negative or inverted bounds error.
2. **Commitment is derived, not stored.** Internal `.commitment()` labels
   each row: `"committed"` (min == max == spend), `"floor"` (min > 0),
   `"capped"` (finite max), `"flexible"` (none). Surfaced in
   `line_item_summary()` (committed spend / flexible headroom per line) and
   later in `describe_plan()`.
3. **Edit enforcement (D5):**
   - `.distribute()` water-fills: allocate the change proportionally across
     matched rows, clip any row at its bound, redistribute the remainder over
     rows with headroom, repeat. If the change cannot be absorbed, error
     naming the binding rows and the absorbable amount.
   - `set`, `scale`, `delta_each`: compute, then error if any matched row
     would breach its bound — name the rows and their bounds.
   - `drop` of a row with `min_spend > 0` errors (a floor cannot be dropped;
     the fix is to lower the floor via a data-frame edit that also supplies
     bounds — see 5).
   - `shift` / `restage`: bounds move with their rows; restaging a committed
     flight errors unless the flight's per-row bounds map 1:1.
   - Data-frame allocation edits (optimizer output) that breach a bound
     error; the optimizer must be given the bounds (Phase 10 makes that one
     object).
4. **Interactions:** even-pacing snapping must not push a row past a bound
   (skip snapping rows whose bound binds; test it). `roll_up()` sums
   `min_spend` (NA treated as 0) and sums `max_spend` (NA if any NA).
   `calendarize()` splits bounds by the same day weights as spend.
   Subplan rollups carry summed bounds. `compare_scenarios()` unaffected.
5. **Changing a bound is an explicit act**, never a side effect of a spend
   op. Add op `rebound` (`op_rebound(target, min = , max = , during = )`)
   to set bounds on matched rows; it changes no spend, and errors if the new
   bounds exclude current spend. Register it in the Phase 1 registry/schema.

Tests: validator matrix; water-fill (partial absorption, full binding,
infeasible error message); each op family against committed, floor, capped
rows; snapping near a bound; roll_up/calendarize of bounds; JSON round-trip of
bound columns; transfer that must route around committed rows; `rebound`
legality.

---

### Phase 4 — Provenance: `@edits`, `@rationale`, `edit_log()`

1. New settable slot `@edits` (`S7::class_list`, default `list()`): the edits
   that produced this plan from `@parent_id`, in canonical form:
   - op form → `list(form = "ops", ops = <normalized op list>)` (dates as ISO
     strings; single op wrapped into a list).
   - data frame / named vector → per **D3**:
     `list(form = "allocation", data = <grain cols + planned_spend df>)`.
2. New settable slot `@rationale` (`S7::class_list`, default `list()`):
   structured reasons for a derivation, alongside the human headline in
   `@objective`. Allowed keys (validator rejects others):
   `author` (`"human"` / `"agent"` / `"optimizer"`), `goal` (string),
   `constraints_id` (string, Phase 10 id), `forecast` (named list of numeric
   KPIs supplied by the caller — the package never computes them), `notes`
   (string). Set via a `rationale =` argument on `build_scenario()`.
3. Both are set by `build_scenario()`. Explicit resets to `list()`: roots
   (`media_plan_from_df()`, `_from_flights()`) and `roll_up()`. `revise()`
   and `attach_subplan()` / `detach_subplan()` carry them (same id);
   `revise()` may set `rationale` (it describes the plan, not its spend).
4. Validator: `@edits` empty or canonical; non-empty `@edits` requires
   non-empty `@parent_id`.
5. Serialization (bump schema to **4** here): include both; reader restores
   structure (parse these subtrees with `simplifyVector = FALSE` or coerce
   explicitly; length-1 target vectors must stay vectors).
6. **`edit_log(set)`** → one row per op across the set, in lineage order:
   `scenario`, `parent`, `author`, `op`, `from` (target label via the
   `.cell_label()` labeller), `to`, `amount`, `window`, `objective`.
   Transfers fill both sides; one-sided ops fill one; allocations report one
   row (`op = "allocation"`, `amount` = net change).
7. **Replay property:** internal `.replay(parent, edits)`;
   `.replay(parent, child@edits)` reproduces `child@data` exactly.

Tests: provenance set/reset matrix across every constructor and verb; replay
property over all op forms incl. transfer and rebound; rationale key
validation; JSON round-trip incl. multi-value targets and moments with `@tz`;
`edit_log()` on a three-generation chain with mixed authors.

---

### Phase 5 — `describe_plan(plan, top_n = 10)`

The agent's compact, stable view of a plan. Returns a **plain named list**,
JSON-ready, bounded in size regardless of plan size:

- identity: `name`, `nickname`, `id` (short), `parent_id`, `status`,
  `objective`, `rationale$author`
- shape: grain (coarsest-first), `time_col`, `time_basis`, flight window,
  number of line items and rows, `is_topline` + subplan cells
- money: total spend; spend by the coarsest grain column; for each finer
  column, the `top_n` values by spend plus an `other` bucket
- commitments: committed / floor-locked / flexible spend and the number of
  bounded line items; total headroom (flexible + above-floor)
- units: totals by `unit_type`, blended rate per type
- time: spend by calendar month (via `calendarize()`)
- `targetable`: the grain values an op may target (truncated to `top_n` per
  column with a count of the rest — the full list comes from
  `plan_ops_schema(plan)`)

Later phases append fields (approval, basis, budget, model coverage,
constraints). Optional args are added as those phases land:
`describe_plan(plan, budget = NULL, models = NULL, constraints = NULL)`.

Tests: structure snapshot on fixtures (`expect_snapshot` of the JSON);
size bound on a synthetic 5,000-row plan (serialized length under a fixed
budget); every number reconciles to `@data`.

---

### Phase 6 — Approvals: `@approved_on`, revision as projection, current approved

1. **`@revision` removal (D1).** Remove the slot; grep all uses (~38 in `R/`,
   plus print header, `subplan_map()`, `lineage()`, serialize, tests) and
   update. `revise(revision = )` → error naming `lineage()`. v2/v3 files
   carrying `revision` load with it ignored. Note in the Roadmap that the
   consuming app may reference `@revision` (`set_status_tool`); do not edit
   the app here.
2. **`@approved_on`** (`S7::class_Date`, default length-0 = unset).
   Validator: length 0 or 1; non-empty only when `@status == "approved"`.
   `revise()` clears it automatically when status leaves "approved"; the
   validator is the backstop. Settable via
   `revise(status = "approved", approved_on = "2026-10-29")` (Date or ISO).
   Optional even when approved — never defaulted from `Sys.Date()`.
   `build_scenario()` and `roll_up()` reset it. Printed in the header.
3. **`lineage(set)`** gains `approved_on`; `revision` = ordinal among
   approved plans on the root → self path (`NA` if not approved); `current`
   = approved with no approved descendant in the set.
4. **`current_approved(set)`** → name(s) flagged `current`. None →
   `character(0)` with a message; several (parallel branches) → all, with a
   warning. Never break ties by date.
5. **`compare_scenarios(set, level, against = c("base", "parent",
   "current_approved"))`** — default preserves behavior;
   `"current_approved"` errors unless exactly one exists.
6. `describe_plan()` adds `approved_on`.

Tests: five-version approval chain with a rejected branch; current
detection; parallel-approved warning; status change clears date; derived
scenarios never inherit it; `against` options reconcile with `lineage()`;
old JSON with `revision` loads.

---

### Phase 7 — `@spend_basis`

1. Settable character scalar, default `""` (undeclared). Free text (D4);
   document common values `"media_net"`, `"client_net"`, `"gross"`.
2. Set at construction (`media_plan_from_df(..., spend_basis = )`;
   `_from_flights()` forwards) or via `revise()` (a declaration correction,
   never a conversion — say so).
3. Carried by `build_scenario()` and `roll_up()` (test it).
4. Strict equality where plans combine: `ScenarioSet` validator and
   `attach_subplan()` error on mismatch, naming `revise(spend_basis = )`.
5. Header + `describe_plan()` show it. Serialized (schema 4).

Out of scope: fee schedules or basis conversion (record in Roadmap: belongs
in the caller or a companion package).

---

### Phase 8 — `check_budget(plan, budget, tolerance = 0.5)`

The envelope check, by analogy with `check_coverage()`.

- `budget`: data frame with zero or more columns from
  `line_item_grain(plan)`, plus `from`, `to` (Date or ISO), and `amount`.
  Rows may overlap. Unknown columns error with alternatives.
- Planned spend per budget row = sum of the plan's spend inside `[from, to]`
  for matching grain values, via `calendarize(plan, "day")` (works for every
  basis). Budget values absent from the plan → planned 0 (reported).
- Returns budget rows plus `planned`, `variance = planned - amount`,
  `variance_pct`. **Warns** listing rows with `abs(variance) > tolerance`.
- Works unchanged on toplines.
- Help pages for `check_budget()` and `attach_subplan()` contrast them: an
  envelope is a target checked with tolerance; a subplan is ownership with
  equality.
- `describe_plan(budget = )` adds a compact variance summary.

Tests: quarterly channel envelope vs. a monthly plan; month boundary mid-week
on a weekly plan; whole-plan envelope; missing grain value; tolerance edge;
instant-basis plan.

**Then release 0.2.0** (see Phase 11 checklist, applied to Phases 0–8).

---

## Release 0.3.0 — the agent can be scored and checked

### Phase 9 — Model-to-plan grain map: `model_map()`, `spend_by_model()`

mrmopt models are fitted at a grain that may differ from the plan's — and may
be mixed (some channel-level, some partner-level). Make the mapping explicit
and deterministic.

- `models`: data frame, one row per fitted response model, columns a subset
  of `line_item_grain(plan)` plus `model_id`. A coarser model leaves finer
  columns `NA` (e.g. `channel = "YouTube", partner = NA`). Unknown columns
  error with alternatives. Duplicate keys error.
- **`model_map(plan, models)`** → one row per plan line item: grain columns,
  `model_id`, `match_level` (the columns matched), `spend`. Resolution:
  **most specific matching model wins**; two equally specific matches →
  error naming both; no match → `model_id = NA`. **Warns** with unmodeled
  spend and its share (pairing check: plan and models are each valid).
- **`spend_by_model(plan, models, basis = "week")`** → long data frame
  `model_id × period × planned_spend` (and units where single-typed): the
  exact input a response-model forecast needs. Unmapped spend is returned
  under `model_id = NA`, never dropped silently. Uses `calendarize()` then
  aggregation over the map.
- Pure data frames in and out; no dependency on mrmopt. Document the hand-off
  in the vignette with an `eval = FALSE` mrmopt example.
- `describe_plan(models = )` adds coverage: modeled share and the top
  unmodeled line items.

Tests: exact-grain match; mixed-grain resolution; ambiguity error; unmodeled
warning and share; NA bucket retained; totals reconcile to the plan for every
basis; flighted and instant plans.

---

### Phase 10 — Shared constraint object: `plan_constraints()`, `check_constraints()`

One definition of "allowed" that the agent's self-check (here) and the
optimizer (mrmopt, later) both read.

1. **`PlanConstraints`** S7 class (thin): `@id`, `@name`, and `@rules`, a data
   frame with one row per rule:
   - `target` (list-column of grain targets; empty = whole plan), `during`
     (optional `from` / `to`),
   - `type` ∈ `min_spend`, `max_spend`, `min_share`, `max_share`,
     `max_change_abs`, `max_change_pct`, `fixed_total` (covers D6's
     flight-level commitments: total fixed, phasing free),
   - `value` (numeric), `note`.
   Validator: known types, shares in [0, 1], `max_change_*` non-negative,
   targets well-formed. Row-level bounds stay in `@data` (Phase 3); this
   object holds **group** rules.
2. Constructors: `plan_constraints(rules, name)` from a data frame, plus
   `rule_*()` helpers mirroring the op-constructor pattern
   (`rule_min_share(target, value, during)` …). JSON round-trip via
   `plan_to_json()` / `plan_from_json()` (add an object tag).
   `constraints_schema()` for agents, built like `plan_ops_schema()`.
3. **`check_constraints(plan, constraints, reference = NULL)`** → one row per
   rule: `actual`, `limit`, `slack`, `ok`. Share rules are relative to the
   whole plan within the same `during` window. `max_change_*` rules need
   `reference` (normally the parent or current approved plan) and error
   naming the argument if it is missing. Also reports row-level bound
   violations (should be none — validator — but keep the report complete).
   **Warns** on any violation; never errors on a violation.
4. Targets validated against the plan exactly as op targets are (typos error
   with alternatives).
5. `rationale$constraints_id` (Phase 4) references `@id`;
   `describe_plan(constraints = )` adds a pass/fail summary with the binding
   rules.
6. Roadmap: add "mrmopt reads `PlanConstraints`" as the next cross-package
   step; do **not** modify mrmopt in this run.

Tests: each rule type pass/fail/edge; share within windows; change rules
against a reference; missing-reference error; JSON round-trip; schema
validates good rules and rejects bad; constraints checked on a scenario built
by transfers that respect row bounds but break a share rule.

---

## Phase 11 — Fixture, docs, finish (run at each release boundary)

1. `fix_agency_plan()` in `tests/testthat/helper-fixtures.R` (add in Phase 2,
   extend as phases land): synthetic, monthly, grain
   `channel + partner + campaign + tactic`, impressions with CPM rates; one
   zero-spend line; one added-value line (tiny rate); committed upfront rows
   (`min_spend == max_spend`); a partner with a floor; three channels, two
   quarters. Companion `fix_agency_models()` (mixed-grain) and
   `fix_agency_constraints()`.
2. `vignette("getting_started")`: end-to-end — import the agency fixture,
   approve it, two transfers that route around commitments in one scenario,
   `edit_log()`, `check_budget()`, `compare_scenarios(against =
   "current_approved")`. In 0.3.0 add `model_map()` / `spend_by_model()` and
   `check_constraints()`.
3. New `vignette("agentic_planning")` (0.3.0): the loop from Phase 0 with
   real calls — `describe_plan()` → ops validated against
   `plan_ops_schema(plan)` → `build_scenario(rationale = )` →
   `spend_by_model()` (mrmopt call `eval = FALSE`) → `check_constraints()` →
   `revise(status = "to review")`. Explain what the agent may and may not do,
   and why commitments live in the plan.
4. `vignette("plan_concepts")`: transfers & provenance; commitments as
   bounds (and why the label is derived); approvals as a lineage projection;
   spend basis.
5. `Roadmap.md`: move shipped items to "Already grown"; keep in "Not yet
   built": mrmopt consuming `PlanConstraints`; a spreadsheet importer as a
   companion package (`mediaplanr.io`: declarative column map + regex rules
   → `MediaPlan` + lint report; keeps readxl out of this package).
6. `NEWS.md`; version bump (0.2.0, then 0.3.0); pkgdown reference index for
   new exports (`op_*`, `plan_ops_schema`, `edit_log`, `describe_plan`,
   `current_approved`, `check_budget`, `model_map`, `spend_by_model`,
   `PlanConstraints`, `plan_constraints`, `rule_*`, `constraints_schema`,
   `check_constraints`).
7. Final `devtools::check()` clean.

---

## Out of scope for this run

Forecasting, optimization, fee/basis conversion, an Excel importer, geo
taxonomies, external ID joins, any change to `mediaplanr-mvp-app` or
`mrmopt`, the agent loop itself, and further subplan work.
