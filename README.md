# mediaplanr

A thin R package that turns an uploaded media plan into a **validated, typed
object** at a configurable grain, derives scenarios from it, and collects them
into a comparable set.

It does not fit models, forecast, or optimize — and depends on nothing but
[S7](https://rconsortium.github.io/S7/).

## Scope

```
             mediaplanr                         mrmopt
   ┌──────────────────────────┐      ┌──────────────────────────┐
   │ plan object, grain,      │      │ response curves, fitting,│
   │ validation, lineage,     │      │ forecasting, budget      │
   │ scenarios, comparison    │      │ optimization (opt_mix)   │
   └──────────────────────────┘      └──────────────────────────┘
                    ↘                      ↙
                      the app wires them together
```

Response modeling and optimization belong to the `mrmopt` engine. A caller runs
those and joins the results back onto `compare_scenarios()` output by scenario
and grain. Keeping that boundary means a change to the modeling API cannot break
the plan object, and modeling decisions never leak into a container.

## Two ideas worth knowing first

**A plan holds intent, and is blind to past and future.** `planned_spend` is
what was *intended* for a row — including for weeks that have already passed.
It is never what actually happened; actualised spend and attributed KPI live in
the decomp. "Historical", "future", under-delivery and over-delivery are not
properties of a plan at all: they exist only for a **plan-decomp pairing**, and
[`check_coverage()`](#) is the one such operation the package provides. That is
also why editing a row for a past week is ordinary — you are revising what was
planned, and the plan cannot know that week has passed.

**A line item is the time-free identity**: channel + partner + tactic. It's what
the decomp constrains and what response models attach to. A row is a line item
for a given week. `line_item_grain(plan)` gives you those columns; `@grain`
describes the whole row.

## Install

```r
# install.packages("S7")
devtools::install_local("mediaplanr")
```

## Quick start

```r
library(mediaplanr)

# 1. Upload -> validated plan. Knows nothing about decomps.
base <- media_plan_from_df(
  plan_df,
  grain = c("channel", "partner", "week"),
  week  = "week",
  name  = "Q2 base"
)

# 1b. Pair it with a decomp: do the plan's pre-through-date rows account for
#     every line item the model measured? Warns and returns what is missing;
#     re-run on a decomp refresh without rebuilding the plan. New line items
#     after the through-date are expected and never flagged.
missing <- check_coverage(base, decomp_line_items,
                          through = as.Date("2026-03-15"))

# 2. Derive scenarios. The base is never mutated; each scenario records
#    its parent. State the operation -- the arithmetic happens in R.
#    `target` may name any subset of the grain, so this reaches every
#    line item in that week without enumerating them:
trim <- build_scenario(base, edits = list(target = list(week = as.Date("2026-04-06")),
                                          scale = 0.8), name = "Trim 20%")

#    "Set the budget", holding the current mix:
resized <- build_scenario(base, edits = list(total = 200000))

#    An allocation computed elsewhere comes in through the same door:
opt <- build_scenario(base, edits = allocation_from_opt_mix, name = "Optimized")

# 3. Find a model for a new line item by rolling up to a coarser grain
by_channel <- roll_up(base, c("channel", "week"))

# 4. Collect and compare
set <- scenario_set(base, name = "Base")
set <- add_scenario(set, trim)
set <- add_scenario(set, opt)

compare_scenarios(set)          # per scenario: total spend, delta vs base
compare_scenarios(set, "cell")  # per row: spend, share of total, delta vs base
```

A runnable end-to-end demo lives in
[`inst/examples/mvp-flow.R`](inst/examples/mvp-flow.R):

```r
source(system.file("examples", "mvp-flow.R", package = "mediaplanr"))
```

## Core model

| Class | What it is |
|---|---|
| `MediaPlan` | One plan at a configurable grain. A flat `@data` table of grain columns + `planned_spend` (intent, on every row); any other columns ride along untouched. `@week_col` names the week column when the plan is weekly. |
| `ScenarioSet` | A base plan plus named scenarios derived from it, all at one grain. The comparison registry. |

Verbs and helpers: `media_plan_from_df()`, `build_scenario()`, `roll_up()`,
`check_coverage()`, `scenario_set()`, `add_scenario()`, `compare_scenarios()`,
`line_item()`, `line_item_grain()`.

### Edit forms

`build_scenario(edits=)` takes three shapes:

| Shape | Use |
|---|---|
| **Operations** — `list(target=, set/scale/delta/total)` | UI and LLM-driven editing. State intent; R does the arithmetic. |
| **Data frame** — grain columns + `planned_spend` | Absolute allocations, e.g. optimizer output. |
| **Named vector** — `c("TV" = 100)` | Terse single-cell override; natural for an editable table. |

The operation form is the one to drive from chat, because the caller never does
the math. `target` may name any **subset** of the grain (a partial key), so
`list(week = "2026-04-06")` reaches every line item in that week. A target value
that doesn't exist is an error naming the valid alternatives — never a silent
no-op, which is the failure mode that matters when a model generates the calls.

`set` is per matched row; `total` is across them (`total` holds the group's
existing mix, so it's the "set the budget" operation). Ops apply in order, so a
budget-neutral shift is two ops.

## Key design decisions

- **S7 value semantics.** Each scenario is an immutable snapshot; deriving one
  leaves the parent untouched, so the thing being compared against is never
  corrupted.
- **Configurable grain, flat table.** A plan keyed by `channel`, or
  `channel + partner`, or `channel + partner + tactic + week` is the same class
  at different grains — not a nested object tree.
- **`@data` stays a plain data frame.** The class adds guarantees, identity, and
  a verb grammar at the boundaries; it does not take the data frame away.
- **Synthetic ids for identity/lineage** (`@id` + `@parent_id`), opaque on
  purpose; human meaning lives in `@name` / `@objective`.
- **Structural validity is enforced; external consistency is reported.**
  Negative spend, duplicate rows, and missing columns are hard errors, so an
  invalid plan cannot exist. Decomp coverage is a mismatch between two valid
  artifacts, so it warns — an upload surfaces it in the UI rather than locking
  the user out.
- **Past and future belong to the pairing, not the plan.** A plan holds intent
  only, so it cannot and does not classify its own rows. See above.

## Growth path (not now)

Nested Channel→Tactic→Flight hierarchy; a channel-type registry for an
extensible media taxonomy; attribution as a separate linked process; metrics
beyond spend (impressions, GRPs); arbitrary-depth lineage trees; ids as an
external join contract. The current flat grain and synthetic ids are the seeds
these grow from.
