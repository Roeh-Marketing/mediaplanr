# Roadmap

What is deliberately not built yet, and the reasoning already settled
about it. Design decisions recorded here are conclusions, not opinions
to re-litigate — several were reached by building the alternative first.

For what the package *is*, see the README and
[`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md).

------------------------------------------------------------------------

## SubPlans

Built —
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md),
[`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md),
[`is_topline()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md),
[`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md);
see *Already grown*. The design record stays here because the decisions
were argued, not assumed.

A channel team plans its own detail, at its own granularity, on its own
schedule, with its own objectives — and that detail rolls up into the
weekly plan everyone else looks at.

    MediaPlan  "Q2 2026 Brand Plan"      the topline: channel + week, weekly
      └─ subplan "TV"                    campaign + partner + daypart, daily

### Decided

**A subplan is a `MediaPlan`. Composition, not inheritance.** S7
supports inheritance, so this is a choice. Two things decide it. First,
“subplan” is a property of the *relationship*, not the object: in a
master → TV → NBC nesting the TV plan is a subplan *and* a topline at
once, which a class hierarchy cannot express without the same object
being two types. Second, a `SubPlan` class would add no behaviour —
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md),
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md),
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
and
[`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
all do what they already do. What changes is the *parent’s* behaviour.
The package already answers this one level up: `ScenarioSet`
**contains** `MediaPlan`s rather than subclassing anything.

So this adds one slot and no class:

``` r

subplans = S7::new_property(S7::class_list, default = quote(list()))
# names are parent line item keys; values are MediaPlans
```

**“Topline” is prose, not a type.** `is_topline(plan)` is a derived
predicate — true when `@subplans` is non-empty — in the same discipline
as
[`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md),
[`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md)
and `pacing`. A plan does not become a different kind of thing when
something is attached beneath it.

**Naming.** `subplan` in code, `topline` in prose. Rejected:
`channel_plan` privileges a column name the package refuses to privilege
anywhere (there is no `channels()`, deliberately, and the nesting axis
may be market or brand); `schedule` reads as a timing concept in a
package full of them, and understates a thing carrying its own goals and
revisions; `buy` is already spent — the docs use it throughout to mean a
*flight*.

**The subplan owns its numbers.**
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
replaces the parent’s rows for that line item with the subplan’s rollup
— weeks the subplan does not plan disappear, weeks it adds appear — so
there is one number with one owner. Parent rows backed by a subplan
become read-only, and an op reaching one errors naming the right door —
*“channel TV is planned in a subplan; edit the subplan and re-attach.”*
A whole-plan op such as `total = 200` therefore errors on a topline,
deliberately.
[`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
leaves the last reconciled numbers as ordinary editable rows, so
detaching is never destructive.

**Re-attaching is the reconcile; there is no `reconcile()`.** An earlier
draft had one. It was dropped as redundant: with value semantics nothing
changes behind the caller’s back, so the only way the parent and subplan
can disagree is a subplan edited after it was attached — and the fix for
that *is* attaching it again. What makes this safe is a **validator
invariant**: the parent’s rows at each backed cell must equal that
subplan’s rollup, checked on every construction and on `@<-`. Assigning
a mismatched subplan straight into the slot is refused, not merely
discouraged.

**Same grain or finer, and the data declares the cell.** A subplan’s
line item grain must **contain** its parent’s — parent keyed `channel`,
subplan keyed `channel + partner + daypart`, with `channel` constant at
the attached cell.
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
already requires its target grain to be a subset of the plan’s, so a
superset-grained subplan rolls up to its parent through the aggregation
as written. The parent’s key columns are carried in the subplan’s data,
not implied by an attachment name, so `attach_subplan(parent, subplan)`
takes no key: the cell is one distinct combination across
`line_item_grain(parent)`, a fact in the table rather than a string to
parse. Same-grain subplans are allowed — ownership without refinement.

Cadence is the second axis. A weekly parent needs a subplan with a week
column; `calendarize(subplan, "week", week_start = week_start(parent))`
re-cuts its days onto the parent’s weeks before the rollup, so daily
flights and a different week start land correctly. A parent whose weeks
do not share a weekday cannot host one. A timeless parent collapses time
as
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
does.

**Depth is legal; one level is built and tested.** A subplan is a
`MediaPlan`, so it carries `@subplans` too, and master → TV → NBC costs
nothing to permit. Reconciliation is *local* — attaching NBC makes TV’s
row right, attaching that TV makes the master’s row right — so no
machinery cares about depth. What depth costs is staleness a planner
cannot see; detecting it is a check, not a cascade, and it is not built.
A plan cannot be attached beneath itself: S7’s value semantics make an
object cycle impossible to form, so the rule is an id check — the
parent’s id must not appear among the subplan’s descendants.

**Campaigns need no new machinery.** A campaign is a grain column in the
subplan, ordered coarsest-first exactly as
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
already expects. That is the payoff of the configurable grain, and the
reason this is smaller than it looks.

**A subplan carries its own grain and schedule.** It is a full
`MediaPlan`, so it need not share the parent’s grain or cadence: a daily
`channel + partner + daypart` plan can sit beneath a weekly
`channel + week` topline, and a `channel + market` plan can refine a
national cell into markets.
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
collapses the extra dimensions and
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
bridges the cadence, so the subplan reconciles to the single parent cell
it backs. The one rule is that everything in the subplan must roll up to
that cell — refining a cell, never spanning several.

**Revisions.** Planners say *Rev 2*, so the slot is `@revision`
(integer, default 1). It composes with what exists: `@parent_id` gives
lineage, `@status` gives workflow, and a `ScenarioSet` is already a
registry, so a subplan’s revision history is a `ScenarioSet` if a team
wants one.

### `revise()` landed with it

`@subplans` was the first genuinely new slot since `MediaPlan` was
written, and it walked into a known trap. A consumer that rebuilds a
plan by naming its slots by hand — as the MVP app does in
`set_status_tool`, naming eleven — silently drops any slot added later.
Changing a scenario’s status would quietly detach every subplan. That is
data loss, not cosmetics.

`revise(plan, ...)` is the metadata-only edit verb that closes it: same
`@id`, only the named fields change, and it refuses anything that is not
metadata. Inside the package, `.copy_plan()` is the one door through
which a plan is copied — it reads the settable properties off the class,
so a new slot is carried by default and dropped only on purpose.
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
drops subplans (a coarser view owns nothing);
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
carries them. The three constructor sites that used to name every slot
by hand now go through it.

`@revision` is manual.
[`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md)
sets it; nothing bumps it; anything minting a new id — a scenario, a
rollup — starts again at 1.

------------------------------------------------------------------------

------------------------------------------------------------------------

## National and local: geo is a grain, not a feature

A plan is national or local by *what it keys on*, not by any switch.
National is a plan with no geo column; local adds one — `market`,
`region`, `dma`, whatever the client calls it — exactly as `channel` is
a dimension a user happened to key on. Everything already follows:
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
collapses market -\> national,
[`grain_values()`](https://roeh-marketing.github.io/mediaplanr/reference/grain_values.md)
lists the markets, and an op can target one. A geo *hierarchy* (DMA -\>
region -\> national) is coarsest-first grain ordering, which
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
already treats as nesting.

So geo needs no new machinery. It arrives on the same two mechanisms
channels do, and which one fits is a property of the engagement, not the
package:

- **A dimension in one plan** — national planners breaking spend down by
  market: one owner, one artifact. Supported today.
- **An owned subplan** — a regional team authoring its market at its own
  grain and schedule, rolling up into the national topline. This is the
  SubPlans work above, nesting on `market` instead of `channel`; the
  mechanism is already axis-agnostic (“the nesting axis may be market or
  brand”).

### Decided

**No geo taxonomy.** The same rule as the channel-type registry: the
package ships no canonical list of DMAs, regions or markets, and no
built-in geo hierarchy. A market is a dimension the user keyed on; the
client’s own naming is the only naming.

------------------------------------------------------------------------

## The consuming application

The package has grown a good deal that `mediaplanr-mvp-app` does not yet
know about. Its agent tools and system prompt currently describe spend
edits on weekly rows and nothing else:

- **Flights.**
  [`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md),
  [`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md),
  and the fact that a plan can be authored as buys rather than weeks.
- **Structural ops.** `add`, `drop`, `shift`, `restage` and `during`
  targeting — the app cannot yet let a planner introduce or remove a
  line item through chat.
- **Units.** `unit_type`, `planned_units`, `planned_rate`, and the “any
  two give the third” authoring rule at upload.
- **[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md).**
  Monthly and daily views, which is what finance asks for.

Two package-side additions would make that integration deterministic
rather than prose-steered, and belong here because the app’s own charter
says all plan semantics live in `mediaplanr`:

- **`describe_plan(plan)`** → a plain list: grain, each grain column’s
  distinct values, the flight window, the line-item roster, units by
  type, and totals. The app has a `describe_plan` tool that rebuilds
  this by hand; making the package’s version canonical means the model
  and R cannot drift apart. Phase 1 and 3 already deliver the pieces,
  and the subplan map is now
  [`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md)
  — built on the same argument, along with
  [`ownership_map()`](https://roeh-marketing.github.io/mediaplanr/reference/ownership_map.md),
  [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
  and
  [`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md):
  projections the package owns so a renderer cannot drift. Anything that
  needs a graphics dependency belongs in the companion,
  `mediaplanr.viz`, which draws only from these projections.
- **`plan_ops_schema()`** → the JSON Schema for the operations array.
  The app passes ops to the model as an unschema’d JSON *string*,
  because `ellmer`’s typed arguments cannot express the recursive shape,
  so a malformed op is discovered only when R throws.

------------------------------------------------------------------------

## Serialization to JSON

A plan crosses the app boundary — saved, reloaded, handed to a model —
so it needs a JSON form. This is smaller than it looks, for the same
reasons the copy helper in
[`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md)
is: the class stores a flat table and a handful of scalars, and
everything else is derived.

### Decided

**Serialize the settable slots, nothing derived.** The write side
filters `MediaPlan`’s properties to the settable ones — the exact getter
filter the
[`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md)
copy helper uses — and emits those plus a `schema_version`:

``` r

ps       <- attr(MediaPlan, "properties")
settable <- names(ps)[vapply(ps, function(p) is.null(p$getter), logical(1))]
# @data, @grain, @week_col, @id, @parent_id, and the metadata scalars
```

[`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md),
`pacing`,
[`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md)
are **not** written. They are recomputed on load, which keeps the JSON
small and — more importantly — makes it impossible to persist a stale
derived fact, the same rule that keeps them off the class.

**Read back through
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md),
not the raw constructor.** The constructor round-trips, but the from-df
door re-runs validation and re-solves the units identity, so a
hand-edited or drifted file rebuilds *clean* rather than merely
reconstructed.
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
already takes `id` and `parent_id`, so identity and lineage survive the
trip — the rebuild is faithful, not fresh.

**A `schema_version` from v1.** The one thing that is cheap now and
expensive later. It rides on the top-level object so the reader can
branch on shape.

**The encoding conventions, all minor.** Dates have no JSON type, so the
week column goes out ISO 8601 and is reparsed on load; `auto_unbox`
collapses a length-1 `grain` and an empty `parent_id` becomes `[]`, so
both are coerced back to character on the way in. None of this is
structural.

**Subplans recurse, but only the writer gets it free.**
`.plan_payload()` derives its fields from the class’s settable
properties, so `@subplans` is picked up with one recursive `lapply` so
children are emitted as payloads. The key is omitted when empty, so a
flat plan serializes exactly as it did; the parent’s `@data` is still
written in full, so a reader that ignores `subplans` gets the right
totals. `schema_version` went to `2`, which also added `revision`.

The reader needs more than recursion. It rebuilds through
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md),
which knows nothing of subplans, so children are rebuilt first and then
**attached** through
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md),
never assigned into the slot. A hand-edited parent row is corrected
rather than trusted, and a file describing an illegal tree is refused
with the same error an interactive attach gives. The reader is also the
one place uncapped depth is a hazard — a written tree is finite, a
parsed one need not be — so it carries a nesting limit of 32 with a
clear error, a parser’s bound rather than a constraint on the model.

### Flights needed no special path

The first worry here was flight identity:
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
looked like the wrong door for a flighted plan, so it seemed a reader
would have to branch to the flights door on `flight_id`. It does not.
The flight columns (`flight_id`, `flight_start`, `flight_end`,
`period_basis`, `pacing`) live in `@data`, so they travel with it, and
the validator accepts them once the two date columns are reparsed — no
branch, no separate flights-door path. A **mixed** plan, where only some
rows belong to an authored flight and the rest carry `NA`, rebuilds the
same way. And
[`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md)
forwards `...` to
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md),
which already takes `id` and `parent_id`, so lineage survives either
door.

[`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)
and
[`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
implement this, covered by a round-trip suite over weekly, geo, units,
flighted and mixed plans.

------------------------------------------------------------------------

## Already grown

Listed because earlier revisions of the README named these as future
work:

- **Metrics beyond spend** — built. `unit_type`, `planned_units`,
  `planned_rate`, bound by one identity, with the rate as the invariant
  under an edit.
- **Flighting** — built. Plans can be authored as flights and are held
  as weeks;
  [`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
  inverts it exactly, and
  [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
  re-cuts onto any calendar.
- **Adding and dropping line items** — built, via the structural ops.
- **[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  scoping on spans** — built. It now selects rows through the same
  `.row_span()` every other date question uses, so it follows a flight
  that starts mid-week rather than the week it happens to sit in. The
  rule is **overlap**, which preserves every previous answer for weekly
  plans, and it is documented on
  [`?check_coverage`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  and in
  [`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md)
  — which was the actual gap, since the behaviour was defensible but
  unstated.
- **Serialization to JSON** — built.
  [`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)
  and
  [`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
  round-trip a `MediaPlan` or a whole `ScenarioSet`, through
  [`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
  so the rebuild is re-validated and lineage preserved; flighted and
  mixed plans need no special path. Covered by a round-trip suite and
  shown in
  [`vignette("getting_started")`](https://roeh-marketing.github.io/mediaplanr/articles/getting_started.md).
  The design reasoning is above, under *Serialization to JSON*.
- **SubPlans** — built. One slot, no class:
  [`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  replaces the cell’s rows with the subplan’s rollup and locks them,
  [`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  releases them,
  [`is_topline()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
  is the derived predicate, and a validator invariant holds parent rows
  equal to each subplan’s rollup so the two cannot drift. The subplan
  declares its cell through its data (same-or-finer grain, parent keys
  constant);
  [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
  bridges cadence.
  [`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md)
  and the `.copy_plan()` door landed with it, closing the drop-a-slot
  trap, and JSON went to schema 2 with a recursive writer and a
  re-attaching reader. Depth is legal; one level is tested. The design
  reasoning is above, under *SubPlans*.

------------------------------------------------------------------------

## Deliberately not planned

- **A channel-type registry / media taxonomy.** The package hard-codes
  no column name anywhere. `channel` is a dimension a user happened to
  key on, and plans keyed on `media_type` or `vehicle` are equally
  valid.
- **Attribution, response curves, forecasting, optimization.** These
  live in the `mrmopt` engine. An earlier revision of this package
  included a `forecast()` and an optimizer; both were removed for
  reasons written down in
  [`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md)
  and should not be rebuilt by accident.
- **Anything derived from
  [`Sys.Date()`](https://rdrr.io/r/base/Sys.time.html)** —
  `weeks_remaining`, `is_active`, `pct_delivered`. The rule the package
  holds: *if a value can change without the plan changing, it does not
  belong on the plan.* This is what keeps the flight window legitimate
  and these out.
- **Ids as an external join contract.** `@id`, `@parent_id` and
  `flight_id` are opaque, exist for identity and lineage, and are scoped
  to a derivation tree. Do not build an external join on them.
