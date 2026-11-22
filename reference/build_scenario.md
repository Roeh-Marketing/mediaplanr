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
  rationale = list(),
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

- rationale:

  Optional structured reasons for the derivation, kept as `@rationale`
  beside the `objective` headline: a named list with any of `author`
  (`"human"`, `"agent"` or `"optimizer"`), `goal` (text),
  `constraints_id` (the `@id` of the
  [PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md)
  it was checked against), `forecast` (a named list of numbers the
  caller supplies – the package never computes them) and `notes` (text).
  Never inherited.

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

Each op is `list(<exactly one operation>, <selection>)`, a plain list
that can be written by hand, built by an [op
constructor](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
such as
[`op_scale()`](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
or parsed from an agent's JSON tool call – all three are the same
object. The constructors check an op where it is written;
[`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
gives the same rules as a JSON Schema.

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

- `transfer`:

  Move this amount from the `from` cells to the `to` cells, leaving the
  plan's total unchanged. Takes `from` and `to` in place of `target`,
  and `from_during` / `to_during` to window one side. See
  [`op_transfer()`](https://roeh-marketing.github.io/mediaplanr/reference/op_transfer.md).

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

`delta` is almost always the one you want when the budget itself
changes: distributing in proportion rather than evenly per cell
preserves the channel's flighting shape, so a flight stays evenly paced
through it. When money moves *between* line items – "move 50k from TV to
Social" – reach for `transfer`. It spreads each side the same way
`delta` would, and keeps the two halves of the move together as one op.

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

## Spend bounds

Rows may carry `min_spend` and `max_spend`
([`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)):
an upfront commitment, a partner floor, a cap. Every edit respects them.

- `delta`, `total` and `transfer` spread a change across a group, and a
  row that reaches its bound **stops there** while the rest of the group
  takes up the slack. A cut to a channel with a committed line comes out
  of its other lines. Only when the group as a whole cannot absorb the
  change is the op refused, saying how much it could take.

- `set`, `scale`, `delta_each` and allocation edits name each row's
  value outright, so a row that would land outside its bounds is
  refused.

- `drop` refuses a row with a floor. `shift` and `restage` carry each
  period's bounds with it, and refuse a move that changes a bounded
  flight's period structure.

Bounds change only through `rebound`
([`op_rebound()`](https://roeh-marketing.github.io/mediaplanr/reference/op_rebound.md)),
never as a side effect of moving money: to cut committed spend, lower
the commitment and then cut, in that order, in one edits list.

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

`@subplans` **carry**: the scenario is still a topline. Rows a subplan
backs are read-only, so an edit reaching one — including a whole-plan op
like `list(total = 200)` — errors naming the subplan to edit instead.
See
[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md).
`@approved_on` is cleared with the status: whether and when the scenario
is approved is its own business; see
[`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md).

`@edits` records exactly what was applied, in a canonical form: the ops
with their fields in a fixed order and dates as text on the plan's
clock, or the allocation as given. The scenario is derived by replaying
that record, so replaying it on the parent reproduces the scenario.
`@rationale` holds the `rationale` given here. Both belong to this
derivation and are never inherited;
[`edit_log()`](https://roeh-marketing.github.io/mediaplanr/reference/edit_log.md)
lays them out across a set.

## Examples

``` r
base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search", "Social"),
             planned_spend = c(80, 40, 40)),
  grain = "channel", time = "week", name = "base"
)

# "Increase Search by 20%" — the caller states intent, R does the math
build_scenario(base, edits = op_scale(1.2, target = list(channel = "Search")),
               name = "Search +20%")
#> <MediaPlan> Search +20%  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       168
#>   id          plan_c45205   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            80
#>    2026-07-06  Search            48
#>    2026-07-06  Social            40

# The same op written by hand, as an agent's JSON would arrive
build_scenario(base, edits = list(scale = 1.2,
                                  target = list(channel = "Search")),
               name = "Search +20%, by hand")
#> <MediaPlan> Search +20%, by hand  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       168
#>   id          plan_fe3218   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            80
#>    2026-07-06  Search            48
#>    2026-07-06  Social            40

# "Set the total budget to 200", holding the current mix
build_scenario(base, edits = op_total(200), name = "Budget 200")
#> <MediaPlan> Budget 200  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       200
#>   id          plan_4e104d   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV           100
#>    2026-07-06  Search            50
#>    2026-07-06  Social            50

# "Move 10 from TV to Search" — budget-neutral however many rows each has
build_scenario(base, edits = op_transfer(10, from = list(channel = "TV"),
                                         to = list(channel = "Search")),
               name = "move 10")
#> <MediaPlan> move 10  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       160
#>   id          plan_81f9be   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            70
#>    2026-07-06  Search            50
#>    2026-07-06  Social            40

# Ops in a list apply in order
build_scenario(base, edits = list(
  op_transfer(10, from = list(channel = "TV"), to = list(channel = "Search")),
  op_scale(0.5, target = list(channel = "Social"))
), name = "move 10, halve Social")
#> <MediaPlan> move 10, halve Social  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       140
#>   id          plan_36adab   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            70
#>    2026-07-06  Search            50
#>    2026-07-06  Social            20

# Absolute allocation (e.g. from mrmopt::opt_mix())
build_scenario(
  base,
  edits = data.frame(week = as.Date("2026-07-06"),
                     channel = c("TV", "Search"), planned_spend = c(50, 70)),
  name = "Optimized"
)
#> <MediaPlan> Optimized  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       160
#>   id          plan_3d322b   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            50
#>    2026-07-06  Search            70
#>    2026-07-06  Social            40

# Terse single-cell override, keyed by line_item() at the full grain
build_scenario(base, edits = c("Search | 2026-07-06" = 120),
               name = "Search boost")
#> <MediaPlan> Search boost  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       240
#>   id          plan_04bdd5   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            80
#>    2026-07-06  Search           120
#>    2026-07-06  Social            40

# A plan can gain and lose line items
build_scenario(base, edits = op_add(channel = "Audio", week = "2026-07-06",
                                    planned_spend = 25),
               name = "add audio")
#> <MediaPlan> add audio  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  4
#>     channel   Audio, Search, Social, TV
#>   rows        4
#>   spend       185
#>   id          plan_2b87bd   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            80
#>    2026-07-06  Search            40
#>    2026-07-06  Social            40
#>   ... 1 more row
build_scenario(base, edits = op_drop(target = list(channel = "TV")),
               name = "no TV")
#> <MediaPlan> no TV  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  2
#>     channel   Search, Social
#>   rows        2
#>   spend       80
#>   id          plan_21b046   derived from plan_e52cc9
#> 
#>          week channel planned_spend
#>    2026-07-06  Search            40
#>    2026-07-06  Social            40
```
