# Roadmap

What is deliberately not built yet, and the reasoning already settled about it.
Design decisions recorded here are conclusions, not opinions to re-litigate —
several were reached by building the alternative first.

For what the package *is*, see the README and
`vignette("plan_concepts")`.

---

## Next: SubPlans

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

**The subplan owns its numbers.** `attach_subplan()` recomputes the parent's
rows for that line item from the subplan's rollup, so there is one number with
one owner. Parent rows backed by a subplan become read-only, and an op targeting
one errors naming the right door — *"channel TV is planned in a subplan; edit
the subplan and re-attach."* `reconcile()` is always explicit; nothing
recomputes behind the caller's back. `detach_subplan()` leaves the last
reconciled numbers as ordinary editable rows, so detaching is never destructive.

**Campaigns need no new machinery.** A campaign is a grain column in the
subplan, ordered coarsest-first exactly as `roll_up()` already expects. That is
the payoff of the configurable grain, and the reason this is smaller than it
looks.

**Revisions.** Planners say *Rev 2*, so the slot is `@revision` (integer,
default 1). It composes with what exists: `@parent_id` gives lineage, `@status`
gives workflow, and a `ScenarioSet` is already a registry, so a subplan's
revision history is a `ScenarioSet` if a team wants one.

### `revise()` must land with it

`@subplans` is the first genuinely new slot since `MediaPlan` was written, and
it walks into a known trap. A consumer that rebuilds a plan by naming its slots
by hand — as the MVP app does in `set_status_tool`, naming eleven — silently
drops any slot added later. Changing a scenario's status would quietly detach
every subplan. That is data loss, not cosmetics.

`revise(plan, ...)` is the metadata-only edit verb that closes it. Note that
`S7::props()` includes getter-backed properties, so a copy helper must filter to
settable ones:

```r
ps <- attr(MediaPlan, "properties")
settable <- names(ps)[vapply(ps, function(p) is.null(p$getter), logical(1))]
do.call(MediaPlan, S7::props(x)[settable])
```

---

## Carried over, not done

**`check_coverage()` filters on a point, not a span.** It selects rows with
`d[[week_col]] < through` — a comparison against the week *start* — while every
other date question now goes through `.row_span()`, which knows a row's real
in-market period.

This is not wrong today: `start < through` *is* the overlap rule, and a decomp
reporting through Wednesday has measured part of the week that began Monday. The
problems are that nothing says so, and that flights have made the gap
unbounded — a 28-day OOH flight starting the day before `through` passes the
filter while being 96% unmeasured.

To do: express the filter through `.row_span()`; choose and **document** the
rule for partially-measured flights (recommendation: overlap, which preserves
every current answer); update `plan_concepts.Rmd`, which says `check_coverage()`
is "scoped by `through`" without saying what `through` is compared against; and
add the test the suite lacks — a through-date falling *inside* a row's span,
the only case separating the two readings.

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

Two package-side additions would make that integration deterministic rather than
prose-steered, and belong here because the app's own charter says all plan
semantics live in `mediaplanr`:

- **`describe_plan(plan)`** → a plain list: grain, each grain column's distinct
  values, the flight window, the line-item roster, units by type, totals, and
  later the subplan map. The app has a `describe_plan` tool that rebuilds this
  by hand; making the package's version canonical means the model and R cannot
  drift apart. Phase 1 and 3 already deliver the pieces.
- **`plan_ops_schema()`** → the JSON Schema for the operations array. The app
  passes ops to the model as an unschema'd JSON *string*, because `ellmer`'s
  typed arguments cannot express the recursive shape, so a malformed op is
  discovered only when R throws.

---

## Already grown

Listed because earlier revisions of the README named these as future work:

- **Metrics beyond spend** — built. `unit_type`, `planned_units`,
  `planned_rate`, bound by one identity, with the rate as the invariant under
  an edit.
- **Flighting** — built. Plans can be authored as flights and are held as weeks;
  `flights()` inverts it exactly, and `calendarize()` re-cuts onto any calendar.
- **Adding and dropping line items** — built, via the structural ops.

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
- **Ids as an external join contract.** `@id`, `@parent_id` and `flight_id` are
  opaque, exist for identity and lineage, and are scoped to a derivation tree.
  Do not build an external join on them.
