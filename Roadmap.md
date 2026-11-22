# Roadmap

What is deliberately not built yet, and the reasoning already settled about it.
Design decisions recorded here are conclusions, not opinions to re-litigate —
several were reached by building the alternative first.

For what the package *is*, see the README and
`vignette("plan_concepts")`.

---

## Agentic planner: responsibility split

The package's next job is to be the substrate an **agentic media planner**
works on: an agent inspects a plan compactly, acts on it only through
validated ops, never violates a commercial commitment, is scored by `mrmopt`
at the right grain, checks itself against the same constraints the optimizer
uses, and leaves an auditable record of what it changed and why.

Three owners, one job each:

- **mediaplanr** — plan state, legal actions, constraints, checks, history.
- **mrmopt** — scoring and optimization.
- **The app** — the agent loop and the human approval gate.

The loop this supports, and which step each owner takes:

```
describe        describe_plan(plan)                         mediaplanr
propose ops     op_*() / JSON against plan_ops_schema(plan) agent (app)
validate        build_scenario(plan, edits, rationale = )   mediaplanr
score           spend_by_model() -> response models         mrmopt
check           check_constraints(scenario, constraints)    mediaplanr
record why      @rationale, edit_log()                      mediaplanr
approve         revise(status = "approved")                 human (app)
```

Much of this is already in place, and it is the reason the package suits the
job: value semantics, a validator on every construction, ops as data, errors
that list the alternatives, lineage and status. An agent cannot corrupt a plan,
and every proposal it makes is an inspectable scenario rather than an edit in
place.

What was missing, and its status:

1. **Commitments the edit path respects** — row-level spend bounds, so money
   that cannot move is a fact in the plan rather than something an agent has
   to be told. *Built in 0.2.0.*
2. **A compact, bounded plan summary** for the agent's context —
   `describe_plan()`. *Built in 0.2.0.*
3. **A deterministic map from line items to `mrmopt` response models**, which
   may be fitted at a different (and mixed) grain — `model_map()`,
   `spend_by_model()`. *Built in 0.3.0.*
4. **One constraint object** read by both the agent's self-check and the
   optimizer — `PlanConstraints`, `check_constraints()`. *Built in 0.3.0.*
5. **Structured rationale on each proposal** — who proposed it, toward what
   goal, under which constraints. *Built in 0.2.0, as `@rationale`.*

The agent loop itself is the app's, not this package's;
`vignette("agentic_planning")` runs one turn of it with real calls.

---

## Sections and scopes

Built in 0.4.0. A client keeps **one master plan per fiscal year**, worked
on by several planners at once. The client's organization -- brand and
performance, lines of business, channels -- is a tree of **sections**, and
each planner is **scoped** to some of them.

### Decided

- **A section is a target**: the same named list of grain columns and values
  an op, a `check_budget()` row and a `PlanConstraints` rule already use. A
  **scope** is a list of targets. A section's envelope is a `check_budget()`
  row. Nothing new is stored.
- **A draft is a scenario** under a base revision. It is approved by
  replaying its `@edits` on the *current* revision, so approved revisions
  stay one chain and `current_approved()` returns one plan. `rebase_check()`
  says whether the replay does what the draft did.
- **Every organization level is a grain column**, because a target may only
  name grain columns. A grouping the plan lacks (funnel over `channel`) is
  added with `regrain()`, which keeps the plan's id, lineage and approval.
- **The app does not match rows itself.** `match_rows()`, `ops_within()` and
  the rest resolve rows through the matcher the edits use, so a scope check
  cannot disagree with what an edit would touch. They read: they do not
  refuse subplan-owned rows the way every edit door still does.

---

## API style

### Decided

The consumers of the edit path are LLM agents — emitting JSON tool calls or
generating R — and the humans reviewing what they did. That decides the style.

**In:**

- Plan-first arguments, and pure functions that return the same class.
- Standard evaluation: column names are strings, targets are named lists
  (`list(channel = "TV")`).
- `op_*()` constructors, each returning the **same plain list** a hand-written
  or JSON-parsed op is, so the three are interchangeable.
- One JSON Schema for the edits array, `plan_ops_schema()`.

**Out, with reasons:**

- **dplyr generics on `MediaPlan`** (`mutate()`, `filter()`, …). They would
  bypass everything that makes an edit legal: the validator, the units
  identity, subplan locks, flight identity and spend bounds. Each would have
  to re-route through the op machinery anyway, at which point it is an op
  with a misleading name.
- **Tidy evaluation / bare column names.** A quoted R expression is not
  JSON-serializable, so a tool-calling agent cannot produce one. A target has
  to be data.
- **Per-step mutating pipe verbs** (`plan |> scale_spend() |> shift()`). Each
  step would mint a lineage generation, so one intent would land as a chain of
  half-finished scenarios. One intent is one `build_scenario()` call with an
  edits list.

**Read-only projections may be piped freely** — `roll_up()`, `calendarize()`,
`line_item_summary()` and the like return views, not new generations.

---

## SubPlans

Built — `attach_subplan()`, `detach_subplan()`, `is_topline()`, `revise()`;
see *Already grown*. The design record stays here because the decisions were
argued, not assumed.

**Status: held.** Built and tested at one level. No further investment — no
depth testing, no staleness detection — and not exposed in the app until a
real multi-owner engagement needs it. The common case that *looks* like a
subplan is a signed budget envelope (channel × quarter authorizations checked
with a tolerated variance); that is `check_budget()`, not
ownership.

Known gaps, left as part of the hold: the validator's subplan invariant
compares spend, not spend bounds; and attaching a subplan replaces the cell's
bounds with the subplan's rollup, so a floor set on the topline cell is
dropped if the subplan carries none.

A channel team plans its own detail, at its own granularity, on its own
schedule, with its own objectives — and that detail rolls up into the weekly
plan everyone else looks at.

```
MediaPlan  "Q2 2026 Brand Plan"      the topline: channel + week, weekly
  └─ subplan "TV"                    campaign + partner + daypart, daily
```

### Decided

**A subplan is a `MediaPlan`. Composition, not inheritance.** S7 supports
inheritance, so this is a choice. Two things decide it. First, "subplan" is a
property of the *relationship*, not the object: in a master → TV → NBC nesting
the TV plan is a subplan *and* a topline at once, which a class hierarchy cannot
express without the same object being two types. Second, a `SubPlan` class would
add no behaviour — `build_scenario()`, `roll_up()`, `calendarize()` and
`flights()` all do what they already do. What changes is the *parent's*
behaviour. The package already answers this one level up: `ScenarioSet`
**contains** `MediaPlan`s rather than subclassing anything.

So this adds one slot and no class:

```r
subplans = S7::new_property(S7::class_list, default = quote(list()))
# names are parent line item keys; values are MediaPlans
```

**"Topline" is prose, not a type.** `is_topline(plan)` is a derived predicate —
true when `@subplans` is non-empty — in the same discipline as
`flight_window()`, `week_start()` and `pacing`. A plan does not become a
different kind of thing when something is attached beneath it.

**Naming.** `subplan` in code, `topline` in prose. Rejected: `channel_plan`
privileges a column name the package refuses to privilege anywhere (there is no
`channels()`, deliberately, and the nesting axis may be market or brand);
`schedule` reads as a timing concept in a package full of them, and understates
a thing carrying its own goals and revisions; `buy` is already spent — the docs
use it throughout to mean a *flight*.

**The subplan owns its numbers.** `attach_subplan()` replaces the parent's
rows for that line item with the subplan's rollup — weeks the subplan does not
plan disappear, weeks it adds appear — so there is one number with one owner.
Parent rows backed by a subplan become read-only, and an op reaching one errors
naming the right door — *"channel TV is planned in a subplan; edit the subplan
and re-attach."* A whole-plan op such as `total = 200` therefore errors on a
topline, deliberately. `detach_subplan()` leaves the last reconciled numbers as
ordinary editable rows, so detaching is never destructive.

**Re-attaching is the reconcile; there is no `reconcile()`.** An earlier draft
had one. It was dropped as redundant: with value semantics nothing changes
behind the caller's back, so the only way the parent and subplan can disagree
is a subplan edited after it was attached — and the fix for that *is* attaching
it again. What makes this safe is a **validator invariant**: the parent's rows
at each backed cell must equal that subplan's rollup, checked on every
construction and on `@<-`. Assigning a mismatched subplan straight into the
slot is refused, not merely discouraged.

**Same grain or finer, and the data declares the cell.** A subplan's line item
grain must **contain** its parent's — parent keyed `channel`, subplan keyed
`channel + partner + daypart`, with `channel` constant at the attached cell.
`roll_up()` already requires its target grain to be a subset of the plan's, so a
superset-grained subplan rolls up to its parent through the aggregation as
written. The parent's key columns are carried in the subplan's data, not
implied by an attachment name, so `attach_subplan(parent, subplan)` takes no
key: the cell is one distinct combination across `line_item_grain(parent)`, a
fact in the table rather than a string to parse. Same-grain subplans are
allowed — ownership without refinement.

Cadence is the second axis. A weekly parent needs a subplan with a week
column; `calendarize(subplan, "week", week_start = week_start(parent))` re-cuts
its days onto the parent's weeks before the rollup, so daily flights and a
different week start land correctly. A parent whose weeks do not share a
weekday cannot host one. A parent keyed by moments has no calendar to gather a
subplan onto, and refuses.

**Depth is legal; one level is built and tested.** A subplan is a `MediaPlan`,
so it carries `@subplans` too, and master → TV → NBC costs nothing to permit.
Reconciliation is *local* — attaching NBC makes TV's row right, attaching that
TV makes the master's row right — so no machinery cares about depth. What depth
costs is staleness a planner cannot see; detecting it is a check, not a
cascade, and it is not built. A plan cannot be attached beneath itself: S7's
value semantics make an object cycle impossible to form, so the rule is an id
check — the parent's id must not appear among the subplan's descendants.

**Campaigns need no new machinery.** A campaign is a grain column in the
subplan, ordered coarsest-first exactly as `roll_up()` already expects. That is
the payoff of the configurable grain, and the reason this is smaller than it
looks.

**A subplan carries its own grain and schedule.** It is a full `MediaPlan`, so
it need not share the parent's grain or cadence: a daily
`channel + partner + daypart` plan can sit beneath a weekly `channel + week`
topline, and a `channel + market` plan can refine a national cell into markets.
`roll_up()` collapses the extra dimensions and `calendarize()` bridges the
cadence, so the subplan reconciles to the single parent cell it backs. The one
rule is that everything in the subplan must roll up to that cell — refining a
cell, never spanning several.

**Revisions.** *Superseded — see Already grown, Approvals.* Planners say
*Rev 2*, so the slot was `@revision` (integer, default 1), set by hand. It
turned out to be the opposite of what a planner means: it reset to 1 on every
derivation, while "Rev 2" means "the second approved version" of a plan that
was derived many times. The slot was removed; a revision is now derived by
`lineage()` from approvals along the branch.

### `revise()` landed with it

`@subplans` was the first genuinely new slot since `MediaPlan` was written, and
it walked into a known trap. A consumer that rebuilds a plan by naming its slots
by hand — as the MVP app does in `set_status_tool`, naming eleven — silently
drops any slot added later. Changing a scenario's status would quietly detach
every subplan. That is data loss, not cosmetics.

`revise(plan, ...)` is the metadata-only edit verb that closes it: same `@id`,
only the named fields change, and it refuses anything that is not metadata.
Inside the package, `.copy_plan()` is the one door through which a plan is
copied — it reads the settable properties off the class, so a new slot is
carried by default and dropped only on purpose. `roll_up()` drops subplans
(a coarser view owns nothing); `build_scenario()` carries them. The three
constructor sites that used to name every slot by hand now go through it.

`revise()` now sets approval (`status` and `approved_on`) rather than a
revision number. Note for the app: `set_status_tool` names slots by hand and
may still name `revision`, which no longer exists; it should call `revise()`.

---

## National and local: geo is a grain, not a feature

A plan is national or local by *what it keys on*, not by any switch. National is a
plan with no geo column; local adds one — `market`, `region`, `dma`, whatever the
client calls it — exactly as `channel` is a dimension a user happened to key on.
Everything already follows: `roll_up()` collapses market -> national,
`grain_values()` lists the markets, and an op can target one. A geo *hierarchy*
(DMA -> region -> national) is coarsest-first grain ordering, which `roll_up()`
already treats as nesting.

So geo needs no new machinery. It arrives on the same two mechanisms channels do,
and which one fits is a property of the engagement, not the package:

- **A dimension in one plan** — national planners breaking spend down by market:
  one owner, one artifact. Supported today.
- **An owned subplan** — a regional team authoring its market at its own grain and
  schedule, rolling up into the national topline. This is the SubPlans work above,
  nesting on `market` instead of `channel`; the mechanism is already axis-agnostic
  ("the nesting axis may be market or brand").

### Decided

**No geo taxonomy.** The same rule as the channel-type registry: the package ships
no canonical list of DMAs, regions or markets, and no built-in geo hierarchy. A
market is a dimension the user keyed on; the client's own naming is the only naming.

---

## The consuming application

The package has grown a good deal that `mediaplanr-mvp-app` does not yet know
about. Its agent tools and system prompt currently describe spend edits on
weekly rows and nothing else:

- **Flights.** `media_plan_from_flights()`, `flights()`, and the fact that a
  plan can be authored as buys rather than weeks.
- **Structural ops.** `add`, `drop`, `shift`, `restage` and `during` targeting —
  the app cannot yet let a planner introduce or remove a line item through chat.
- **Units.** `unit_type`, `planned_units`, `planned_rate`, and the "any two give
  the third" authoring rule at upload.
- **`calendarize()`.** Monthly and daily views, which is what finance asks for.
- **Since 0.2.0.** `transfer` and `rebound`; spend bounds and the refusals
  they produce; `@rationale` (the app should pass `author = "agent"` on
  scenarios its agent proposes); `@approved_on` in place of `@revision`, and
  `current_approved()`; `@spend_basis`; `check_budget()`; and the two
  additions below, both now built.
- **Since 0.4.0.** The master-plan verbs: `match_rows()` in place of any
  row matching of its own, `assign_sections()` for the organization tree,
  `ops_within()` to enforce a planner's scope before building, and
  `rebase_check()` before replaying a draft onto the current revision.

Two package-side additions would make that integration deterministic rather than
prose-steered, and belong here because the app's own charter says all plan
semantics live in `mediaplanr`:

- **`describe_plan(plan)`** → a plain list: grain, each grain column's distinct
  values, the flight window, the line-item roster, units by type, and totals.
  The app has a `describe_plan` tool that rebuilds this by hand; making the
  package's version canonical means the model and R cannot drift apart. Phase
  1 and 3 already deliver the pieces, and the subplan map is now
  `subplan_map()` — built on the same argument, along with `ownership_map()`,
  `lineage()` and `plan_mermaid()`: projections the package owns so a renderer
  cannot drift. Anything that needs a graphics dependency belongs in the
  companion, `mediaplanr.viz`, which draws only from these projections.
  *Built* — capped rather than a full roster, so it fits an agent's context
  at any plan size; see *Already grown*. The app has not adopted it yet.
- **`plan_ops_schema()`** → the JSON Schema for the operations array. The app
  passes ops to the model as an unschema'd JSON *string*, because `ellmer`'s
  typed arguments cannot express the recursive shape, so a malformed op is
  discovered only when R throws. *Built* — see *Already grown*; the app has
  not adopted it yet.

---

## Serialization to JSON

A plan crosses the app boundary — saved, reloaded, handed to a model — so it
needs a JSON form. This is smaller than it looks, for the same reasons the copy
helper in `revise()` is: the class stores a flat table and a handful of scalars,
and everything else is derived.

### Decided

**Serialize the settable slots, nothing derived.** The write side filters
`MediaPlan`'s properties to the settable ones — the exact getter filter the
`revise()` copy helper uses — and emits those plus a `schema_version`:

```r
ps       <- attr(MediaPlan, "properties")
settable <- names(ps)[vapply(ps, function(p) is.null(p$getter), logical(1))]
# @data, @grain, @time_col, @time_basis, @id, @parent_id, and the metadata scalars
```

`flight_window()`, `pacing`, `week_start()` are **not** written. They are
recomputed on load, which keeps the JSON small and — more importantly — makes it
impossible to persist a stale derived fact, the same rule that keeps them off the
class.

**Read back through `media_plan_from_df()`, not the raw constructor.** The
constructor round-trips, but the from-df door re-runs validation and re-solves
the units identity, so a hand-edited or drifted file rebuilds *clean* rather than
merely reconstructed. `media_plan_from_df()` already takes `id` and `parent_id`,
so identity and lineage survive the trip — the rebuild is faithful, not fresh.

**A `schema_version` from v1.** The one thing that is cheap now and expensive
later. It rides on the top-level object so the reader can branch on shape.

**The encoding conventions, all minor.** Dates have no JSON type, so the week
column goes out ISO 8601 and is reparsed on load; `auto_unbox` collapses a
length-1 `grain` and an empty `parent_id` becomes `[]`, so both are coerced back
to character on the way in. None of this is structural.

**Subplans recurse, but only the writer gets it free.** `.plan_payload()`
derives its fields from the class's settable properties, so `@subplans` is
picked up with one recursive `lapply` so children are emitted as payloads. The
key is omitted when empty, so a flat plan serializes exactly as it did; the
parent's `@data` is still written in full, so a reader that ignores `subplans`
gets the right totals. `schema_version` went to `2`, which also added
`revision`.

The reader needs more than recursion. It rebuilds through
`media_plan_from_df()`, which knows nothing of subplans, so children are
rebuilt first and then **attached** through `attach_subplan()`, never assigned
into the slot. A hand-edited parent row is corrected rather than trusted, and a
file describing an illegal tree is refused with the same error an interactive
attach gives. The reader is also the one place uncapped depth is a hazard — a
written tree is finite, a parsed one need not be — so it carries a nesting
limit of 32 with a clear error, a parser's bound rather than a constraint on
the model.

### Flights needed no special path

The first worry here was flight identity: `media_plan_from_df()` looked like the
wrong door for a flighted plan, so it seemed a reader would have to branch to the
flights door on `flight_id`. It does not. The flight columns (`flight_id`,
`flight_start`, `flight_end`, `period_basis`, `pacing`) live in `@data`, so they
travel with it, and the validator accepts them once the two date columns are
reparsed — no branch, no separate flights-door path. A **mixed** plan, where only
some rows belong to an authored flight and the rest carry `NA`, rebuilds the same
way. And `media_plan_from_flights()` forwards `...` to `media_plan_from_df()`,
which already takes `id` and `parent_id`, so lineage survives either door.

`plan_to_json()` and `plan_from_json()` implement this, covered by a round-trip
suite over weekly, geo, units, flighted and mixed plans.

---

## Already grown

Listed because earlier revisions of the README named these as future work:

- **Metrics beyond spend** — built. `unit_type`, `planned_units`,
  `planned_rate`, bound by one identity, with the rate as the invariant under
  an edit.
- **Flighting** — built. Plans can be authored as flights and are held as weeks;
  `flights()` inverts it exactly, and `calendarize()` re-cuts onto any calendar.
- **Adding and dropping line items** — built, via the structural ops.
- **`check_coverage()` scoping on spans** — built. It now selects rows through
  the same `.row_span()` every other date question uses, so it follows a flight
  that starts mid-week rather than the week it happens to sit in. The rule is
  **overlap**, which preserves every previous answer for weekly plans, and it is
  documented on `?check_coverage` and in `vignette("plan_concepts")` — which was
  the actual gap, since the behaviour was defensible but unstated.
- **Serialization to JSON** — built. `plan_to_json()` and `plan_from_json()`
  round-trip a `MediaPlan` or a whole `ScenarioSet`, through
  `media_plan_from_df()` so the rebuild is re-validated and lineage preserved;
  flighted and mixed plans need no special path. Covered by a round-trip suite
  and shown in `vignette("getting_started")`. The design reasoning is above,
  under *Serialization to JSON*.
- **SubPlans** — built. One slot, no class: `attach_subplan()` replaces the
  cell's rows with the subplan's rollup and locks them, `detach_subplan()`
  releases them, `is_topline()` is the derived predicate, and a validator
  invariant holds parent rows equal to each subplan's rollup so the two cannot
  drift. The subplan declares its cell through its data (same-or-finer grain,
  parent keys constant); `calendarize()` bridges cadence. `revise()` and the
  `.copy_plan()` door landed with it, closing the drop-a-slot trap, and JSON
  went to schema 2 with a recursive writer and a re-attaching reader. Depth is
  legal; one level is tested. The design reasoning is above, under *SubPlans*.
- **Op constructors and the ops schema** — built. One registry in `R/ops.R`
  names every op, its fields and their types; `.apply_op()`, the `op_*()`
  constructors and `plan_ops_schema()` all read it, so they cannot disagree.
  A constructor returns the same plain list a hand-written or JSON op is, and
  every op -- however it was made -- gets the same plan-free checks when
  applied. With a plan, the schema narrows targets to its grain values and
  dates to its basis. The style reasoning is above, under *API style*.
- **`transfer`** — built. The commonest real edit, a zero-sum move between
  line items, as one op rather than two deltas whose pairing is lost. Each
  side spreads like `delta`; a destination that plans nothing fills evenly by
  in-market days, the rule an even flight follows. All three of `delta`,
  `total` and `transfer` spread money through one helper, `.distribute()`,
  which is where spend bounds are enforced.
- **Spend bounds** — built. Optional `min_spend` / `max_spend` per row
  (`bound_cols()`) record commitments, floors and caps; the validator holds
  `min <= spend <= max` to the cent. Group edits water-fill around a bound
  in `.distribute()`; per-row edits are refused at one; `drop`, `shift` and
  `restage` respect them; `roll_up()`, `calendarize()`, flight import and
  subplan rollups carry them. "Committed" / "floor" / "capped" is derived by
  `.commitment()`, never stored. Bounds change only through the `rebound`
  op. Line-total commitments ("$300K upfront, phasing flexible") are group
  rules, planned with `PlanConstraints`.
- **Provenance** — built. A derived plan carries `@edits`, the canonical
  record of what `build_scenario()` applied (ops operation-first with dates
  as text on the plan's clock, or the allocation as given), and
  `@rationale`, who proposed it and why. The scenario is derived by
  replaying its own record, so replaying `@edits` on the parent reproduces
  it exactly; an added flight's id is minted into the record for the same
  reason. Roots and rollups record none, nothing inherits it, `revise()` may
  set a rationale. `edit_log()` reads a set's records as a change log. JSON
  went to schema 4.
- **`describe_plan()`** — built. The agent's view of a plan: identity and
  provenance, shape, spend by each line item column, commitments, units,
  spend by month, and what an op may target. Every list is capped at
  `top_n` values plus a counted remainder, so the description stays a few
  kilobytes at any number of rows (only the by-month section grows, with the
  plan's duration), and every number reconciles to `@data`. Later phases add
  their facts to it.
- **Approvals** — built. `@revision` is gone. A plan carries its approval as
  `@status = "approved"` and an optional `@approved_on` date (never defaulted
  from today; cleared when the status moves on; never inherited by a derived
  scenario or a rollup). `lineage()` derives each approved plan's `revision`
  -- its place among the approved plans on its branch -- and flags the
  `current` one: approved, with nothing approved derived from it.
  `current_approved()` returns it, warning when parallel branches leave more
  than one and never breaking the tie by date. `compare_scenarios()` takes
  `against = "base" | "parent" | "current_approved"`. Older JSON carrying
  `revision` reads with it ignored.
- **Spend basis** — built. `@spend_basis` declares what `planned_spend`
  measures (`"media_net"`, `"client_net"`, `"gross"`, or anything else; `""`
  undeclared). Set at import or corrected with `revise()`; carried by
  scenarios and rollups. Plans combine -- in a `ScenarioSet`, or as a
  subplan -- only when their bases match exactly, undeclared included.
- **`check_budget()`** — built. The envelope check: a budget table of
  windows and amounts, each naming any subset of the line item columns (or
  none), compared with the plan's spend measured day by day through
  `calendarize()`, so a window may cut a week or month anywhere. Reports
  planned, variance and whether each row is within tolerance; a value the
  plan lacks reads as absent, not as an underspend. Warns, never errors, like
  `check_coverage()`. `describe_plan(budget = )` summarises it. The help
  pages contrast an envelope (a target, with tolerance) with a subplan
  (ownership, with equality).
- **The model map** — built (0.3.0). `model_map()` assigns every line
  item exactly one response model from a list fitted at mixed grains: of the
  models whose named values all match, the most specific wins; a tie is an
  error naming both, a gap is a warning with the unmodeled share.
  `spend_by_model()` sums each model's spend by period through
  `calendarize()`, keeping unmodeled spend under `model_id = NA` so totals
  reconcile. Data frames in and out; no dependency on `mrmopt`.
  `describe_plan(models = )` reports coverage.
- **The constraint object** — built (0.3.0). `PlanConstraints` holds the
  group rules a plan lives under -- min/max spend, min/max share, a fixed
  total with free phasing, max change (absolute or %) from a reference plan
  -- built from `rule_*()` constructors or a rules sheet, kept one canonical
  way, with a `constraints_schema()` for agents and a JSON round trip. Row
  rules stay spend bounds on the plan. `check_constraints()` measures each
  rule day by day (like `check_budget()`) and reports actual, limit, slack
  and ok, warning on a violation and never refusing one; change rules need a
  reference. `describe_plan(constraints = )` reports the broken and the
  binding rules, and a scenario's `rationale$constraints_id` names the rule
  set it was checked against.

- **Sections and scopes** -- built (0.4.0). `match_rows()` is the public
  face of the edit path's matcher: one target or a list of targets, `during`,
  strict or lenient. `assign_sections()` places line items in an
  organization tree's leaves, reporting overlaps and gaps without refusing
  them. `ops_within()` checks a list of ops against a scope in order, so an
  `add` creates rows a later op may target. `rebase_check()` compares the
  rows a draft touches on its base and on the current revision. `regrain()`
  adds an organization level as a grain column. The reasoning is above,
  under *Sections and scopes*.

---

## Not yet built

- **`mrmopt` reading `PlanConstraints`** — the next cross-package step, so
  the optimizer and the agent's self-check enforce the same definition of
  "allowed". `check_constraints()` documents the semantics it must match:
  spend measured day by day inside each rule's window, shares against the
  whole plan in the same window. Not started here; `mrmopt` is untouched.
- **`regrain()` beyond one flat plan.** It takes one plan: a set of
  revisions and drafts is regrained plan by plan with the same arguments
  (ids, and so lineage, are unchanged), and a topline is refused because its
  subplans would need the column too.
- **A spreadsheet importer, as a companion package** (`mediaplanr.io`): a
  declarative column map plus regex rules that turn an agency workbook into a
  `MediaPlan` and a lint report. A companion so that `readxl` and the long tail
  of workbook conventions stay out of this package.

---

## Deliberately not planned

- **A channel-type registry / media taxonomy.** The package hard-codes no column
  name anywhere. `channel` is a dimension a user happened to key on, and plans
  keyed on `media_type` or `vehicle` are equally valid.
- **Attribution, response curves, forecasting, optimization.** These live in the
  `mrmopt` engine. An earlier revision of this package included a `forecast()`
  and an optimizer; both were removed for reasons written down in
  `vignette("plan_concepts")` and should not be rebuilt by accident.
- **Anything derived from `Sys.Date()`** — `weeks_remaining`, `is_active`,
  `pct_delivered`. The rule the package holds: *if a value can change without
  the plan changing, it does not belong on the plan.* This is what keeps the
  flight window legitimate and these out.
- **Fee schedules and spend-basis conversion.** `@spend_basis` declares
  what the figures measure; it never converts one basis into another. Turning
  media net into client net means applying an agency's fee schedule, which
  differs by contract and by channel. That belongs in the caller, or in a
  companion package, not in the plan.
- **Ids as an external join contract.** `@id`, `@parent_id` and `flight_id` are
  opaque, exist for identity and lineage, and are scoped to a derivation tree.
  Do not build an external join on them.