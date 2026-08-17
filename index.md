# mediaplanr

A thin R package that turns an uploaded media plan into a **validated,
typed object** at a configurable grain, derives scenarios from it, and
collects them into a comparable set.

It does not fit models, forecast, or optimize — and depends on nothing
but [S7](https://rconsortium.github.io/S7/).

## Scope

                 mediaplanr                         mrmopt
       ┌──────────────────────────┐      ┌──────────────────────────┐
       │ plan object, grain,      │      │ response curves, fitting,│
       │ validation, lineage,     │      │ forecasting, budget      │
       │ scenarios, comparison    │      │ optimization (opt_mix)   │
       └──────────────────────────┘      └──────────────────────────┘
                        ↘                      ↙
                          a caller wires them together

Response modeling and optimization belong to the `mrmopt` engine. A
caller runs those and joins the results back onto
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
output by scenario and grain. Keeping that boundary means a change to
the modeling API cannot break the plan object, and modeling decisions
never leak into a container.

## Install

``` r

# install.packages("S7")
devtools::install_github("Roeh-Marketing/mediaplanr")
```

## Quick start

``` r

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

compare_scenarios(set)            # per scenario: total spend, delta vs base
compare_scenarios(set, "cell")    # per cell: spend, share, delta vs base
compare_scenarios(set, "flight")  # per buy: moved, resized, added, dropped
```

`build_scenario(edits =)` also takes a data frame of absolute values
(natural for optimizer output) or a named vector keyed by
[`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
(natural for an editable table).

Operations do more than change spend. A plan can gain and lose line
items, and a buy can move:

``` r

list(target = list(channel = "TV"), delta = -50000)   # take 50k out of TV
list(target = list(channel = "OOH"), shift = 7)       # push the buy a week
list(add = list(channel = "Audio", week = "2026-04-06", planned_spend = 25000))
list(target = list(channel = "Search"), drop = TRUE)
list(during = list(from = "2026-04-20", to = "2026-05-31"), scale = 0.5)
```

The distinction that catches people out runs both ways: `total` and
`delta` act **across** the matched rows and hold their mix, `set` and
`delta_each` act on **each** row. On a 26-week plan those differ by a
factor of 26 — and because the two sides of a transfer usually cancel,
getting it wrong still reconciles.

## Core model

| Class | What it is |
|----|----|
| `MediaPlan` | One plan at a configurable grain. A flat `@data` table of grain columns + `planned_spend` (intent, on every row); any other columns ride along untouched. `@week_col` names the week column when the plan is weekly. |
| `ScenarioSet` | A base plan plus named scenarios derived from it, all at one grain. The comparison registry. |

Two optional column sets ride along on `@data`, validated but never part
of the grain: the **flighting** columns
([`flight_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_cols.md))
recording the buy a row belongs to, and the **unit** columns
([`unit_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/unit_cols.md))
recording what it buys.

|  |  |
|----|----|
| Build a plan | [`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md), [`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md) |
| Change one | [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md) |
| Look at it | [`line_item_summary()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_summary.md), [`grain_values()`](https://roeh-marketing.github.io/mediaplanr/reference/grain_values.md), [`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md), [`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md), [`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md), [`cost_per_unit()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md), [`cpm()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md) |
| Aggregate it | [`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md) (dimensions), [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md) (time) |
| Compare | [`scenario_set()`](https://roeh-marketing.github.io/mediaplanr/reference/scenario_set.md), [`add_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/add_scenario.md), [`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md) |
| Vocabularies | [`status_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/status_levels.md), [`unit_type_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/unit_type_levels.md), [`period_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/period_basis_levels.md), [`pacing_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/pacing_levels.md) |
| Pair with a decomp | [`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md) |

### Two doors in

A plan can be authored the way it is written down. By week:

``` r

media_plan_from_df(df, grain = c("channel", "week"), week = "week", name = "Q2")
```

…or as **flights** — in-market dates and a total — which expand onto the
weekly rows `@data` holds, exactly to the cent:

``` r

media_plan_from_flights(buys, grain = c("channel", "partner"), name = "Q2")
```

[`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
inverts that exactly, and reports nothing rather than guessing when a
plan records no flight identity.

### What it runs, and what it buys

``` r

base@flight_start               # first day in market
base@flight_end                 # last day -- the final week's last day
grain_values(base, "channel")   # ready to use as an edit target
line_item_summary(base)         # per line item: spend, units, rate, own flight
calendarize(base, "month")      # re-cut onto any calendar
```

Everything here is derived from `@data` on every read, so none of it can
go stale. That is the rule the package holds throughout: **if a value
can change without the plan changing, it does not belong on the plan.**
A plan’s flight window is its own extent; the through-date
[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
takes belongs to a plan-decomp pairing and moves every refresh.

## Learn more

- **[Getting
  started](https://roeh-marketing.github.io/mediaplanr/articles/getting_started.html)**
  — the whole path, from a data frame to a compared set of scenarios,
  including the three shapes `edits` accepts and when each is natural.
- **[The plan
  model](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.html)**
  — what a plan *is*, why it is blind to past and future, how scenarios
  and lineage work, and which boundaries keep the package small. Read
  this before extending it.

Two ideas the rest of the design hangs on, in one line each:

- **A plan holds intent, on every row** — including weeks already past.
  It is never a record of what happened; actuals live in a decomp.
- **A line item** (channel / partner / tactic) is the time-free identity
  that models attach to. A row is a line item for one week.

## Growth path

Nested **SubPlans** are next: a channel team’s detailed plan, at its own
granularity, rolling up into the weekly topline. See
[Roadmap.md](https://github.com/Roeh-Marketing/mediaplanr/blob/main/Roadmap.md)
for that design and for what is deliberately staying out — a
channel-type registry, attribution, and anything derived from
[`Sys.Date()`](https://rdrr.io/r/base/Sys.time.html).
