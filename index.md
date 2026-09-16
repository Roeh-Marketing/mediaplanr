# mediaplanr

A thin R package that defines a structure capturing the anatomy of a
media plan and media planning operations.

## Install

``` r

# install.packages("S7")
devtools::install_github("Roeh-Marketing/mediaplanr")
```

## Quick start

``` r

library(mediaplanr)

# 1. Define a media plan 
my_media_plan <- media_plan_from_df(
  plan_df,
  grain      = c("channel", "partner", "week"),
  week       = "week",
  name       = "Q2 2026 Brand Plan",
  nickname   = "baseline",
  advertiser = "Acme Corp",
  status     = "approved"
)

# 2. Build a scenario by editing the plan via a set of operations; R does the arithmetic.
reduced_budget <- build_scenario(
  my_media_plan,
  edits    = list(target = list(channel = "TV"), scale = 0.8),
  name     = "Q2 2026 Brand Plan — TV trim",
  nickname = "TV -20%"
)

# 3. Collect a set of scenario options for comparison and review.
set <- add_scenario(scenario_set(my_media_plan), reduced_budget)

compare_scenarios(set)
```

### What you can change in a scenario

A comprehensive set of opperations are avalible to mutate the media
plan. Every edit says **what to change** and **how**.

**Pick what to change** - `target` — any mix of channel, partner, week:
“all TV”, “Google in March”, or leave it out for the whole plan -
`during` — anything in market between two dates, including a buy that
started earlier and is still running

**Change the budget** - `total` — make it add up to this - `delta` — add
or take away this much overall ← *the everyday one* - `scale` — up or
down by a percentage (1.2 = +20%) - `set` — this exact amount on every
week you picked - `delta_each` — add this to every week you picked

> **Note.** `delta -50,000` takes 50k out of TV. `delta_each -50,000`
> takes 50k out of *every TV week* — 1.3m on a 26-week plan.

**Change what’s in the plan** - `add` — a new line item, for a week or
with in-market dates - `drop` — take it out altogether (not the same as
setting it to zero) - `shift` — move a buy a number of days earlier or
later - `restage` — move a buy to new dates

Moving a buy keeps it recognisable as the *same* buy, so you can compare
before and after.

**Not edits.** Pacing (even or hand-shaped) is read off the numbers,
never set. Names, status and approvals change separately. Anything
planned in a detail plan is locked — edit that plan instead.

``` r

list(target = list(channel = "TV"), delta = -50000)   # take 50k out of TV
list(target = list(channel = "OOH"), shift = 7)       # push the buy a week
list(add = list(channel = "Audio", week = "2026-04-06", planned_spend = 25000))
list(target = list(channel = "Search"), drop = TRUE)
list(during = list(from = "2026-04-20", to = "2026-05-31"), scale = 0.5)
```

## Core model

| Class | What it is |
|----|----|
| `MediaPlan` | One plan at a chosen level of granularity, and following a chosen nomenclature. A flat `@data` table of grain columns + `planned_spend`; any other columns ride along untouched |
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
| Change one | [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md) (spend), [`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md) (metadata) |
| Nest one | [`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md), [`detach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md), [`is_topline()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md) |
| See the structure | [`plan_tree()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_tree.md), [`subplan_map()`](https://roeh-marketing.github.io/mediaplanr/reference/subplan_map.md), [`ownership_map()`](https://roeh-marketing.github.io/mediaplanr/reference/ownership_map.md), [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md), [`plan_mermaid()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_mermaid.md) |
| Look at it | [`line_item_summary()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_summary.md), [`grain_values()`](https://roeh-marketing.github.io/mediaplanr/reference/grain_values.md), [`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md), [`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md), [`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md), [`cost_per_unit()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md), [`cpm()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md) |
| Aggregate it | [`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md) (dimensions), [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md) (time) |
| Compare | [`scenario_set()`](https://roeh-marketing.github.io/mediaplanr/reference/scenario_set.md), [`add_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/add_scenario.md), [`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md) |
| Vocabularies | [`status_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/status_levels.md), [`unit_type_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/unit_type_levels.md), [`period_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/period_basis_levels.md), [`pacing_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/pacing_levels.md) |
| Pair with a decomp | [`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md) |

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
