# Derive a new scenario plan from a base plan

Produces a new
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
by changing `planned_spend` and leaving everything else untouched. The
returned plan carries `@parent_id` set to the base plan's id, so lineage
is preserved through every derivation, and the base plan is never
mutated.

## Usage

``` r
build_scenario(
  plan,
  edits,
  name,
  nickname = "",
  advertiser = NULL,
  planner = NULL,
  status = "in development",
  objective = "",
  ...
)
```

## Arguments

- plan:

  The base
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- edits:

  The edits to apply; see *Edit forms*.

- name:

  Formal name for the new scenario. **Required**.

- nickname:

  Optional short working handle. Preferred over `name` when labelling
  the scenario in a
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

- advertiser:

  Optional override; defaults to the parent's advertiser.

- planner:

  Optional override; defaults to the parent's planner.

- status:

  Workflow state for the new scenario; defaults to `"in development"`.
  Never inherited from the parent.

- objective:

  Human-facing objective / notes for the new scenario.

- ...:

  Unused; for method extension.

## Value

A new
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
at the base plan's grain, with `@parent_id` set.

## Details

`mediaplanr` deliberately does not forecast or optimize: it expresses
*plan intent*. To build a scenario from an optimizer, run the
optimization elsewhere (e.g. `mrmopt::opt_mix()`) and pass the resulting
planned_spend allocation in as an absolute `edits` data frame.

## Edit forms

`edits` accepts three shapes.

**1. Operations** — a list of ops, or a single op, applied in order.
This is the form to drive from a UI or an LLM tool call: the caller
states the *operation* and the arithmetic happens here, exactly.

Each op is
`list(target = <named list>, <one of set/scale/delta/total>)`.

- `target`:

  Named list of grain column = value(s), naming any **subset** of the
  grain — so `list(week = "2026-03-09")` hits every channel in that
  week. Values may be vectors. Omit `target` to match the whole plan.
  Targeting a value that does not exist is an error, never a silent
  no-op.

- `set`:

  Absolute planned_spend, applied to **each** matched cell.

- `scale`:

  Multiply each matched cell (e.g. `1.2` = +20%).

- `delta`:

  Add to each matched cell (may be negative).

- `total`:

  Make the matched cells **sum** to this, holding their current mix.
  This is the "set the budget" operation.

Note the deliberate split: `set` is per-cell, `total` is across cells.
So `list(target = list(channel = "TV"), set = 50)` sets every TV row to
50, while `list(target = list(channel = "TV"), total = 50)` makes TV's
rows add up to 50.

**2. Data frame** — grain columns + `planned_spend`; matched cells are
overridden with those absolute values. Natural for optimizer output.

**3. Named numeric vector** — keyed by
[`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md),
e.g. `c("TV" = 100)`. Terse for one or two cells at a simple grain.

## Metadata on a derived scenario

`advertiser` and `planner` are **inherited** from the parent — they
describe the engagement and the person working, not the individual
scenario — and can be overridden per call.

`status` is deliberately **not** inherited. A scenario derived from an
`"approved"` plan is not itself approved, and silently carrying that
forward would manufacture an approval nobody gave. It resets to
`"in development"`, which is what a freshly derived scenario actually
is, unless you say otherwise.

`name` is required and `nickname` is per-scenario, so neither is
inherited.

## Examples

``` r
base <- media_plan_from_df(
  data.frame(channel = c("TV", "Search", "Social"),
             planned_spend = c(80, 40, 40)),
  grain = "channel", name = "base"
)

# "Increase Search by 20%" — the caller states intent, R does the math
build_scenario(base, edits = list(target = list(channel = "Search"),
                                  scale = 1.2), name = "Search +20%")
#> <MediaPlan> Search +20%  [in development]
#>   grain       channel
#>   rows        3
#>   spend       168
#>   id          plan_cb283f   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV            80
#>     Search            48
#>     Social            40

# "Set the total budget to 200", holding the current mix
build_scenario(base, edits = list(total = 200), name = "Budget 200")
#> <MediaPlan> Budget 200  [in development]
#>   grain       channel
#>   rows        3
#>   spend       200
#>   id          plan_e47766   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV           100
#>     Search            50
#>     Social            50

# "Move 10 from TV to Search" — ops apply in order
build_scenario(base, edits = list(
  list(target = list(channel = "TV"),     delta = -10),
  list(target = list(channel = "Search"), delta =  10)
), name = "shift 10")
#> <MediaPlan> shift 10  [in development]
#>   grain       channel
#>   rows        3
#>   spend       160
#>   id          plan_6e4a2f   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV            70
#>     Search            50
#>     Social            40

# Absolute allocation (e.g. from mrmopt::opt_mix())
build_scenario(
  base,
  edits = data.frame(channel = c("TV", "Search"), planned_spend = c(50, 70)),
  name = "Optimized"
)
#> <MediaPlan> Optimized  [in development]
#>   grain       channel
#>   rows        3
#>   spend       160
#>   id          plan_9ec5c4   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV            50
#>     Search            70
#>     Social            40

# Terse single-cell override
build_scenario(base, edits = c("Search" = 120), name = "Search boost")
#> <MediaPlan> Search boost  [in development]
#>   grain       channel
#>   rows        3
#>   spend       240
#>   id          plan_e52cc9   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV            80
#>     Search           120
#>     Social            40
```
