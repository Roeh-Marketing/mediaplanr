# Build a validated media plan from a data frame

The primary entry point for turning an uploaded plan into a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).
Normalises the spend column name to `planned_spend`, reads the time
column and appends it to the grain, and runs the full validator on
construction.

## Usage

``` r
media_plan_from_df(
  df,
  grain,
  time = NULL,
  time_basis = NULL,
  tz = NULL,
  planned_spend = "planned_spend",
  planned_units = NULL,
  planned_rate = NULL,
  unit_type = NULL,
  name,
  nickname = "",
  advertiser = "",
  planner = "",
  status = "",
  approved_on = NULL,
  objective = "",
  spend_basis = "",
  id = NULL,
  parent_id = character(0)
)
```

## Arguments

- df:

  A data frame holding the plan: grain columns plus a spend column. All
  other columns are preserved on `@data` untouched. Optional
  [`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)
  `min_spend` and `max_spend` record spend that cannot move – a
  commitment, a floor, a cap – and every edit then respects them.

- grain:

  Character vector naming the **line item** columns — channel, partner,
  tactic. The time column is appended to them automatically, so there is
  no need to name it here; naming it anyway is harmless, and it is moved
  to the end either way.

- time:

  Name of the plan's time column. A time column is **required**: every
  plan says when it runs. Left `NULL`, it is taken from `df` when
  exactly one Date or POSIXct column is available to be it. Values may
  be `Date` (the first day of the period), `POSIXct` moments, or
  ISO-8601 strings of either.

- time_basis:

  What one value of the time column covers; one of
  [`time_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/time_basis_levels.md).
  Inferred from the column when `NULL`: month starts read as `"month"`,
  dates that all fall on one weekday as `"week"`, anything else as
  `"day"`, and a `POSIXct` column always as `"instant"`. Declare it when
  the guess would be wrong — a single month of a monthly plan cannot be
  told from a single week.

- tz:

  The plan's timezone, as an Olson name (`"America/New_York"`). Times
  given as strings are read on it, and the time column is put on it, so
  the plan reads the same wherever the code runs. Taken from the column
  when `NULL` and it already carries one; `""` otherwise, which leaves
  the session's zone to decide.

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

- approved_on:

  Optional date the plan was approved, as a `Date` or an ISO string;
  only with `status = "approved"`. Never defaulted to today.

- objective:

  Human-facing objective / notes.

- spend_basis:

  What `planned_spend` measures: free text such as `"media_net"`,
  `"client_net"` or `"gross"`; `""` (default) when undeclared. See
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

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
  week    = as.Date(c("2026-07-06", "2026-07-06", "2026-07-06")),
  channel = c("TV", "Search", "Social"),
  planned_spend = c(100, 80, 60)
)
media_plan_from_df(df, grain = "channel", time = "week", name = "Q3 plan",
                   advertiser = "Acme", status = "in development")
#> <MediaPlan> Q3 plan  [in development]
#>   advertiser  Acme
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       240
#>   id          plan_3f2628
#> 
#>          week channel planned_spend
#>    2026-07-06      TV           100
#>    2026-07-06  Search            80
#>    2026-07-06  Social            60

# A buy placed at a specific moment: a POSIXct column, basis "instant".
spots <- data.frame(
  airs   = as.POSIXct(c("2026-07-06 20:30:00", "2026-07-06 21:00:00"),
                      tz = "UTC"),
  daypart = c("primetime", "primetime"),
  planned_spend = c(45000, 52000)
)
media_plan_from_df(spots, grain = "daypart", time = "airs",
                   name = "Launch spots")
#> <MediaPlan> Launch spots
#>   grain       daypart + airs
#>   flight      2026-07-06 20:30:00 to 2026-07-06 21:00:00 UTC  (2 moments)
#>   line items  1
#>     daypart   primetime
#>   rows        2
#>   spend       97,000
#>   id          plan_c0d89c
#> 
#>                   airs   daypart planned_spend
#>    2026-07-06 20:30:00 primetime         45000
#>    2026-07-06 21:00:00 primetime         52000
```
