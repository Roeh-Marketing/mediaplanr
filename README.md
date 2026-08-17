# mediaplanr <a href="https://roeh-marketing.github.io/mediaplanr/"><img src="man/figures/logo.png" align="right" height="139" alt="mediaplanr website" /></a>

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
                      a caller wires them together
```

Response modeling and optimization belong to the `mrmopt` engine. A caller runs
those and joins the results back onto `compare_scenarios()` output by scenario
and grain. Keeping that boundary means a change to the modeling API cannot break
the plan object, and modeling decisions never leak into a container.

## Install

```r
# install.packages("S7")
devtools::install_github("Roeh-Marketing/mediaplanr")
```

## Quick start

```r
library(mediaplanr)

# 1. A validated plan. `name` is required; the week column is typed as a Date.
base <- media_plan_from_df(
  plan_df,
  grain      = c("channel", "partner", "week"),
  week       = "week",
  name       = "Q2 2026 Brand Plan",
  nickname   = "baseline",
  advertiser = "Acme Corp",
  status     = "approved"
)

# 2. Fork a scenario. State the operation; R does the arithmetic.
#    `target` may name any subset of the grain.
trim <- build_scenario(
  base,
  edits    = list(target = list(channel = "TV"), scale = 0.8),
  name     = "Q2 2026 Brand Plan — TV trim",
  nickname = "TV -20%"
)

# 3. Collect and compare.
set <- add_scenario(scenario_set(base), trim)

compare_scenarios(set)          # per scenario: total spend, delta vs base
compare_scenarios(set, "cell")  # per cell: spend, share, delta vs base
```

`build_scenario(edits =)` also takes a data frame of absolute values (natural
for optimizer output) or a named vector keyed by `line_item()` (natural for an
editable table).

## Core model

| Class | What it is |
|---|---|
| `MediaPlan` | One plan at a configurable grain. A flat `@data` table of grain columns + `planned_spend` (intent, on every row); any other columns ride along untouched. `@week_col` names the week column when the plan is weekly. |
| `ScenarioSet` | A base plan plus named scenarios derived from it, all at one grain. The comparison registry. |

Verbs and helpers: `media_plan_from_df()`, `build_scenario()`, `roll_up()`,
`check_coverage()`, `scenario_set()`, `add_scenario()`, `compare_scenarios()`,
`line_item()`, `line_item_grain()`, `line_item_summary()`, `grain_values()`,
`flight_window()`, `status_levels()`.

### When it runs, and what is in it

```r
base@flight_start      # first day in market
base@flight_end        # last day -- the final week's last day, not its start
base@flight_days

grain_values(base, "channel")   # the channels present, ready to use as a target
line_item_summary(base)         # one row per line item: spend, rows, own flight
```

Both are derived from `@data` on every read, so neither can go stale. A plan's
flight window is its own **extent** and is not the through-date
`check_coverage()` takes — that one belongs to a plan-decomp pairing and moves
every time the decomp refreshes.

## Learn more

- **[Getting started](https://roeh-marketing.github.io/mediaplanr/articles/getting_started.html)**
  — the whole path, from a data frame to a compared set of scenarios, including
  the three shapes `edits` accepts and when each is natural.
- **[The plan model](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.html)**
  — what a plan *is*, why it is blind to past and future, how scenarios and
  lineage work, and which boundaries keep the package small. Read this before
  extending it.

Two ideas the rest of the design hangs on, in one line each:

- **A plan holds intent, on every row** — including weeks already past. It is
  never a record of what happened; actuals live in a decomp.
- **A line item** (channel / partner / tactic) is the time-free identity that
  models attach to. A row is a line item for one week.

## Growth path

Nested **SubPlans** are next: a channel team's detailed plan, at its own
granularity, rolling up into the weekly topline. See
[Roadmap.md](https://github.com/Roeh-Marketing/mediaplanr/blob/main/Roadmap.md)
for that design and for what is deliberately staying out — a channel-type
registry, attribution, and anything derived from `Sys.Date()`.
