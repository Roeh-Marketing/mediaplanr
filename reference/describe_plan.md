# A compact description of a plan, for an agent's context

Summarises a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
as a plain named list an agent can read before it proposes an edit: what
the plan is, how it is keyed, what it spends and on what, what cannot
move, what it buys, when it spends, and the values an op may target.
Every section is capped – the `top_n` values by spend, plus a count and
total for the rest – so the description stays the same size whether the
plan has fifty rows or fifty thousand.

## Usage

``` r
describe_plan(
  plan,
  top_n = 10,
  budget = NULL,
  models = NULL,
  constraints = NULL,
  reference = NULL,
  as_json = FALSE
)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- top_n:

  How many values to list for each column before the rest are
  summarised. A whole number, 1 or more.

- budget:

  Optional budget envelope, as
  [`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md)
  takes it. Adds a `budget` section.

- models:

  Optional fitted response models, as
  [`model_map()`](https://roeh-marketing.github.io/mediaplanr/reference/model_map.md)
  takes them. Adds a `models` section.

- constraints:

  Optional
  [PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md).
  Adds a `constraints` section.

- reference:

  The plan change rules in `constraints` are measured against; see
  [`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md).

- as_json:

  `FALSE` (default) returns the nested list; `TRUE` returns it as JSON
  text.

## Value

A named list with the sections above, or a `json` string when
`as_json = TRUE`. Lists that can hold several values (`grain`, `edits`,
`subplan_cells`, `top` values) stay JSON arrays even with one element.

## Details

Everything is derived from the plan on the call, and the numbers
reconcile to `@data`: each column's breakdown, the commitments and the
months all add up to the total. Money is rounded to the cent, shares to
four places, and dates are ISO strings on the plan's clock, so the list
serializes to JSON as it stands.

## Sections

- `identity`:

  `name`, `nickname`, `id` and `parent_id` (short ids), `status`,
  `approved_on`, `objective`, the rationale's `author`, and `edits` –
  the ops that derived it from its parent, in order (`"allocation"` for
  an allocation edit; empty for a root).

- `shape`:

  `grain` (coarsest first, time last), `time_col`, `time_basis`, `tz`,
  the flight window, `n_line_items`, `n_rows`, `is_topline` and the
  `subplan_cells` a subplan owns.

- `money`:

  `spend_basis` – what every figure measures (`""` when undeclared) –
  `total`, and `spend_by` each line item column: its `top` values
  (`value`, `spend`, `share`) and an `other` bucket (`n_values`,
  `spend`).

- `commitments`:

  Spend that cannot move, from the spend bounds
  ([`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)):
  `committed` (rows whose min and max equal their spend), `floor_locked`
  (the floors under rows with a floor), `flexible` (rows with no floor),
  `headroom` (all spend an edit could take out: the flexible spend plus
  what sits above floors), and `n_bounded_line_items`. A plan with no
  bounds is all headroom.

- `units`:

  One row per unit type: `planned_units`, the `planned_spend` behind
  them, and the blended `rate` (a CPM for impressions).

- `time`:

  Spend by calendar month, via
  [`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md).

- `targetable`:

  What an op's `target` may name: for each line item column, its `top`
  values by spend and `n_more`; for the time column, the `first` and
  `last` value and how many there are. The full lists are in
  [`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
  for the plan.

- `budget`:

  Only when `budget` is given: how the plan sits against it, from
  [`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md)
  at its default tolerance – `n_rows`, `n_within`, and the envelopes
  `off` it, worst first (`envelope`, `amount`, `planned`, `variance`,
  `in_plan`), capped at `top_n` with `n_more_off` for the rest.

- `models`:

  Only when `models` is given: how much of the plan its response models
  cover, from
  [`model_map()`](https://roeh-marketing.github.io/mediaplanr/reference/model_map.md)
  – `modeled_share`, `unmodeled_spend`, `n_models_used`, and the largest
  `unmodeled` line items, capped at `top_n` with `n_more_unmodeled` for
  the rest.

- `constraints`:

  Only when `constraints` is given: how the plan stands against them,
  from
  [`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md)
  – the rule set's `id`, `n_rules`, `n_ok`, the `violated` rules (worst
  first) and the `binding` ones, which hold with no slack to spare, so
  the next edit that pushes on them breaks them. Each capped at `top_n`.

## See also

[`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
for the full contract an agent's ops are checked against;
[`line_item_summary()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_summary.md)
for the uncapped roster.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(month = rep(as.Date(c("2026-10-01", "2026-11-01")), each = 3),
             channel = c("Streaming", "Search", "Social"),
             planned_spend = c(60000, 20000, 10000, 40000, 20000, 10000),
             min_spend = c(60000, 15000, NA, 40000, 15000, NA),
             max_spend = c(60000, NA, NA, 40000, NA, NA)),
  grain = "channel", time = "month", name = "Q4"
)
d <- describe_plan(plan, top_n = 2)
d$money$spend_by$channel
#> $top
#>       value spend share
#> 1 Streaming 1e+05 0.625
#> 2    Search 4e+04 0.250
#> 
#> $other
#> $other$n_values
#> [1] 1
#> 
#> $other$spend
#> [1] 20000
#> 
#> 
d$commitments
#> $committed
#> [1] 1e+05
#> 
#> $floor_locked
#> [1] 30000
#> 
#> $flexible
#> [1] 20000
#> 
#> $headroom
#> [1] 30000
#> 
#> $n_bounded_line_items
#> [1] 2
#> 

cat(describe_plan(plan, as_json = TRUE))
#> {
#>   "identity": {
#>     "name": "Q4",
#>     "nickname": "",
#>     "id": "plan_b25aae",
#>     "parent_id": null,
#>     "status": "",
#>     "approved_on": null,
#>     "objective": "",
#>     "author": null,
#>     "edits": []
#>   },
#>   "shape": {
#>     "grain": ["channel", "month"],
#>     "time_col": "month",
#>     "time_basis": "month",
#>     "tz": "",
#>     "flight_start": "2026-10-01",
#>     "flight_end": "2026-11-30",
#>     "n_line_items": 3,
#>     "n_rows": 6,
#>     "is_topline": false,
#>     "subplan_cells": []
#>   },
#>   "money": {
#>     "spend_basis": "",
#>     "total": 160000,
#>     "spend_by": {
#>       "channel": {
#>         "top": [
#>           {
#>             "value": "Streaming",
#>             "spend": 100000,
#>             "share": 0.625
#>           },
#>           {
#>             "value": "Search",
#>             "spend": 40000,
#>             "share": 0.25
#>           },
#>           {
#>             "value": "Social",
#>             "spend": 20000,
#>             "share": 0.125
#>           }
#>         ],
#>         "other": {
#>           "n_values": 0,
#>           "spend": 0
#>         }
#>       }
#>     }
#>   },
#>   "commitments": {
#>     "committed": 100000,
#>     "floor_locked": 30000,
#>     "flexible": 20000,
#>     "headroom": 30000,
#>     "n_bounded_line_items": 2
#>   },
#>   "units": [],
#>   "time": [
#>     {
#>       "month": "2026-10",
#>       "spend": 90000
#>     },
#>     {
#>       "month": "2026-11",
#>       "spend": 70000
#>     }
#>   ],
#>   "targetable": {
#>     "values": {
#>       "channel": {
#>         "top": ["Streaming", "Search", "Social"],
#>         "n_more": 0
#>       }
#>     },
#>     "periods": {
#>       "column": "month",
#>       "first": "2026-10-01",
#>       "last": "2026-11-01",
#>       "n_values": 2
#>     }
#>   }
#> }
```
