# mediaplanr

A thin R package that turns an uploaded media plan into a **validated, typed
object** at a configurable grain, derives scenarios from it, and collects them
into a comparable set.

It holds **plan intent only**. It does not fit models, forecast, or optimize —
and depends on nothing but [S7](https://rconsortium.github.io/S7/).

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
and grain cell. Keeping that boundary means a change to the modeling API cannot
break the plan object, and modeling decisions never leak into a container.

## Install

```r
# install.packages("S7")
devtools::install_local("mediaplanr")
```

## Quick start

```r
library(mediaplanr)

# 1. Upload -> validated plan. `valid_keys` rejects cells the decomp
#    has never seen, at upload time.
base <- media_plan_from_df(
  data.frame(channel = c("TV", "Search", "Social"),
             planned_spend = c(80, 40, 40)),
  grain = "channel", name = "Q3 base",
  valid_keys = decomp_distinct_keys
)

# 2. Derive scenarios by editing planned spend. The base is never mutated;
#    each scenario records its parent.
manual <- build_scenario(base, edits = c("Search" = 120), name = "+Search")

#    An allocation computed elsewhere comes in through the same door:
opt <- build_scenario(base, edits = allocation_from_opt_mix, name = "Optimized")

# 3. Collect and compare
set <- scenario_set(base, name = "Base")
set <- add_scenario(set, manual)
set <- add_scenario(set, opt)

compare_scenarios(set)          # per scenario: total spend, delta vs base
compare_scenarios(set, "cell")  # per cell: spend, share of total, delta vs base
```

A runnable end-to-end demo lives in
[`inst/examples/mvp-flow.R`](inst/examples/mvp-flow.R):

```r
source(system.file("examples", "mvp-flow.R", package = "mediaplanr"))
```

## Core model

| Class | What it is |
|---|---|
| `MediaPlan` | One plan at a configurable grain. A flat `@data` table of key columns + `planned_spend`; any other columns ride along untouched. Intent only — no actuals. |
| `ScenarioSet` | A base plan plus named scenarios derived from it, all at one grain. The comparison registry. |

Verbs and helpers: `media_plan_from_df()`, `build_scenario()`, `scenario_set()`,
`add_scenario()`, `compare_scenarios()`, `grain_key()`.

## Key design decisions

- **S7 value semantics.** Each scenario is an immutable snapshot; deriving one
  leaves the parent untouched, so the thing being compared against is never
  corrupted.
- **Configurable grain, flat table.** A plan keyed by `channel`, or
  `channel + partner`, or `channel + partner + tactic` is the same class at
  different grains (a composite key) — not a nested object tree.
- **`@data` stays a plain data frame.** The class adds guarantees, identity, and
  a verb grammar at the boundaries; it does not take the data frame away.
- **Synthetic ids for identity/lineage** (`@id` + `@parent_id`), opaque on
  purpose; human meaning lives in `@name` / `@objective`.
- **Validation is the point.** The validator runs on construction and on every
  edit, so an invalid plan cannot exist and every consumer can assume clean
  input.
- **Plan holds intent only.** Actualized/attributed data comes from the decomp,
  a separate process, and is not stored on the plan.

## Growth path (not now)

Nested Channel→Tactic→Flight hierarchy; a channel-type registry for an
extensible media taxonomy; actuals/attribution as a separate linked process;
arbitrary-depth lineage trees; ids as an external join contract. The current
flat grain and synthetic ids are the seeds these grow from.
