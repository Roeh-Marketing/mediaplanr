# Build a validated media plan from a data frame

The primary entry point for turning an uploaded plan into a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).
Normalises the spend column name to `planned_spend`, coerces the week
column to `Date`, and runs the full validator on construction.

## Usage

``` r
media_plan_from_df(
  df,
  grain,
  week = NULL,
  planned_spend = "planned_spend",
  planned_units = NULL,
  planned_rate = NULL,
  unit_type = NULL,
  name,
  nickname = "",
  advertiser = "",
  planner = "",
  status = "",
  objective = "",
  id = NULL,
  parent_id = character(0)
)
```

## Arguments

- df:

  A data frame holding the plan: grain columns plus a spend column. All
  other columns are preserved on `@data` untouched.

- grain:

  Character vector naming the columns that identify a row, including the
  week column when the plan is weekly.

- week:

  Optional name of the week column. Must be among `grain`. Values are
  coerced to `Date` (the week start).

- planned_spend:

  Name of the planned-spend column in `df`. Renamed to `planned_spend`.
  Holds intent on every row, including past weeks. Default
  `"planned_spend"`.

- planned_units, planned_rate, unit_type:

  Optional names of the columns recording what the line item buys: how
  much of it, at what price, and of what (`"impression"`, `"click"`,
  `"grp"`, ...). Renamed to the canonical names. The three quantities
  are bound by
  `planned_spend = planned_units * planned_rate / rate_per(unit_type)`,
  where `rate_per` is 1000 for impressions and 1 otherwise, so **supply
  any two and the third is computed** — a budget and a negotiated CPM
  give the impressions, a delivery goal and a rate give the budget. See
  [`cost_per_unit()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md)
  and
  [`unit_type_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/unit_type_levels.md).

- name:

  Formal plan name. **Required** — every plan carries one.

- nickname:

  Optional short working handle used in preference to `name` when
  labelling scenarios.

- advertiser:

  Optional advertiser / client.

- planner:

  Optional person responsible.

- status:

  Optional workflow state; one of
  [`status_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/status_levels.md)
  (matched case-insensitively) or `""` when unset.

- objective:

  Human-facing objective / notes.

- id:

  Optional explicit id; generated when `NULL`.

- parent_id:

  Optional parent id for lineage.

## Value

A validated
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

## Details

It knows nothing about decomps: a plan is constructed from the plan
alone. To check a plan against a decomp, call
[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
— which can then be re-run whenever the decomp refreshes, without
rebuilding the plan.

## Examples

``` r
df <- data.frame(
  channel = c("TV", "Search", "Social"),
  planned_spend = c(100, 80, 60)
)
media_plan_from_df(df, grain = "channel", name = "Q3 plan",
                   advertiser = "Acme", status = "in development")
#> <MediaPlan> Q3 plan  [in development]
#>   advertiser  Acme
#>   grain       channel
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       240
#>   id          plan_1f7fb5
#> 
#>    channel planned_spend
#>         TV           100
#>     Search            80
#>     Social            60
```
