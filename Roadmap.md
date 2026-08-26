# Roadmap

What is deliberately not built yet, and the reasoning already settled
about it. Design decisions recorded here are conclusions, not opinions
to re-litigate — several were reached by building the alternative first.

For what the package *is*, see the README and
[`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md).

------------------------------------------------------------------------

## Next: SubPlans

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

**The subplan owns its numbers.** `attach_subplan()` recomputes the
parent’s rows for that line item from the subplan’s rollup, so there is
one number with one owner. Parent rows backed by a subplan become
read-only, and an op targeting one errors naming the right door —
*“channel TV is planned in a subplan; edit the subplan and re-attach.”*
`reconcile()` is always explicit; nothing recomputes behind the caller’s
back. `detach_subplan()` leaves the last reconciled numbers as ordinary
editable rows, so detaching is never destructive.

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

### `revise()` must land with it

`@subplans` is the first genuinely new slot since `MediaPlan` was
written, and it walks into a known trap. A consumer that rebuilds a plan
by naming its slots by hand — as the MVP app does in `set_status_tool`,
naming eleven — silently drops any slot added later. Changing a
scenario’s status would quietly detach every subplan. That is data loss,
not cosmetics.

`revise(plan, ...)` is the metadata-only edit verb that closes it. Note
that
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
includes getter-backed properties, so a copy helper must filter to
settable ones:

``` r

ps <- attr(MediaPlan, "properties")
settable <- names(ps)[vapply(ps, function(p) is.null(p$getter), logical(1))]
do.call(MediaPlan, S7::props(x)[settable])
```

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
  type, totals, and later the subplan map. The app has a `describe_plan`
  tool that rebuilds this by hand; making the package’s version
  canonical means the model and R cannot drift apart. Phase 1 and 3
  already deliver the pieces.
- **`plan_ops_schema()`** → the JSON Schema for the operations array.
  The app passes ops to the model as an unschema’d JSON *string*,
  because `ellmer`’s typed arguments cannot express the recursive shape,
  so a malformed op is discovered only when R throws.

------------------------------------------------------------------------

## Serialization to JSON

A plan crosses the app boundary — saved, reloaded, handed to a model —
so it needs a JSON form. This is smaller than it looks, for the same
reasons the copy helper in `revise()` is: the class stores a flat table
and a handful of scalars, and everything else is derived.

### Decided

**Serialize the settable slots, nothing derived.** The write side
filters `MediaPlan`’s properties to the settable ones — the exact getter
filter the `revise()` copy helper uses — and emits those plus a
`schema_version`:

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

**Subplans recurse.** `@subplans` is a list of `MediaPlan`s, so a
subplan is the same object serialized the same way, one level down; the
writer and reader recurse and need nothing new per level.

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
