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

Each op is `list(<selection>, <exactly one operation>)`.

**Selecting rows**

- `target`:

  Named list of grain column = value(s), naming any **subset** of the
  grain — so `list(week = "2026-03-09")` hits every channel in that
  week. Values may be vectors. Omit `target` to match the whole plan.
  Targeting a value that does not exist is an error, never a silent
  no-op.

- `during`:

  `list(from =, to =)`. Narrows to rows whose period **overlaps** that
  window — so "cut back April" reaches a flight that started in March
  and is still running. `during` *selects* rows; it never slices them,
  so a flight half inside the window is matched whole.

**Changing spend on rows that exist**

- `total`:

  Make the matched cells **sum** to this, holding their current mix.
  This is the "set the budget" operation.

- `delta`:

  Move the matched cells' **sum** by this, holding their mix. This is
  the "take 50k out of TV" operation.

- `scale`:

  Multiply each matched cell (e.g. `1.2` = +20%). Per cell and across
  cells mean the same thing for a multiplier.

- `set`:

  Absolute planned_spend, applied to **each** matched cell.

- `delta_each`:

  Add to **each** matched cell (may be negative).

Note the deliberate split, and that it runs both ways:

|          |                          |                      |
|----------|--------------------------|----------------------|
|          | across the matched cells | to each matched cell |
| absolute | `total`                  | `set`                |
| relative | `delta`                  | `delta_each`         |

So `list(target = list(channel = "TV"), total = 50)` makes TV's rows add
up to 50, while `set = 50` puts 50 on every TV row. Likewise
`delta = -50` takes 50 out of TV altogether, while `delta_each = -50`
takes 50 out of every TV row — which on a 26-week plan is 1,300.

`delta` is almost always the one you want, and it is the one to reach
for when a user says "move 50k from TV to Social": two ops,
`delta = -50000` on TV and `delta = 50000` on Social. Distributing in
proportion rather than evenly per cell preserves the channel's flighting
shape, so a flight stays evenly paced through it.

**Changing which rows there are**

- `add`:

  Named list: the line item's columns, a `planned_spend`, and either the
  week or `flight_start`/`flight_end`. A flight expands across the weeks
  it touches exactly as
  [`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md)
  would. Takes no `target` — the row does not exist yet. Adding onto a
  cell the plan already has is an error.

- `drop`:

  `TRUE`. Removes the matched rows entirely. Distinct from setting them
  to zero: a dropped line item is not bought at all, where a zeroed one
  is still in the plan at nothing.

- `shift`:

  A whole number of days, negative to move earlier. Moves the matched
  **flights**, re-spreading each total across its new dates. Rows that
  record no flight have their week moved instead, which must be a
  multiple of 7.

- `restage`:

  `list(from =, to =)`. Moves the matched flights to those dates. Needs
  flights; rows without one have no in-market dates to move.

A moved flight **keeps its `flight_id`**, so a scenario and its parent
can be read flight to flight rather than as a drop plus an add. Matching
one row of a flight moves the whole flight. A custom-paced flight keeps
its hand-set weekly figures when the move maps them 1:1 — a whole-week
shift of a week-aligned flight — and errors otherwise rather than
silently discarding them.

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
#>     channel   Search, Social, TV
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
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       200
#>   id          plan_e47766   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV           100
#>     Search            50
#>     Social            50

# "Move 10 from TV to Search" — ops apply in order. `delta` moves each
# group's TOTAL, so this is budget-neutral however many rows they have.
build_scenario(base, edits = list(
  list(target = list(channel = "TV"),     delta = -10),
  list(target = list(channel = "Search"), delta =  10)
), name = "shift 10")
#> <MediaPlan> shift 10  [in development]
#>   grain       channel
#>     channel   Search, Social, TV
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
#>     channel   Search, Social, TV
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
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       240
#>   id          plan_e52cc9   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV            80
#>     Search           120
#>     Social            40

# A plan can gain and lose line items
build_scenario(base, edits = list(add = list(channel = "Audio",
                                             planned_spend = 25)),
               name = "add audio")
#> <MediaPlan> add audio  [in development]
#>   grain       channel
#>     channel   Audio, Search, Social, TV
#>   rows        4
#>   spend       185
#>   id          plan_c45205   derived from plan_acd597
#> 
#>    channel planned_spend
#>         TV            80
#>     Search            40
#>     Social            40
#>   ... 1 more row
build_scenario(base, edits = list(target = list(channel = "TV"), drop = TRUE),
               name = "no TV")
#> <MediaPlan> no TV  [in development]
#>   grain       channel
#>     channel   Search, Social
#>   rows        2
#>   spend       80
#>   id          plan_fe3218   derived from plan_acd597
#> 
#>    channel planned_spend
#>     Search            40
#>     Social            40
```
