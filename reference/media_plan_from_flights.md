# Build a plan from flights rather than weeks

The other door into a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).
Where
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
takes the plan already laid out by week, this takes it as a planner
states it — one row per **flight**, with in-market dates and a total —
and expands it onto the weekly rows `@data` holds. Everything downstream
(the grid,
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md),
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md),
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md))
sees the ordinary weekly shape.

## Usage

``` r
media_plan_from_flights(
  df,
  grain,
  start = "flight_start",
  end = "flight_end",
  planned_spend = "planned_spend",
  week = "week",
  week_start = "Monday",
  period_basis = NULL,
  name,
  ...
)
```

## Arguments

- df:

  A data frame with one row per flight: the line item columns, a start
  date, an end date, and a spend.

- grain:

  Character vector naming the **line item** columns (channel, partner,
  tactic). The week column is created and appended, so do not include
  it.

- start, end:

  Names of the flight start and end date columns. `end` is inclusive.
  Coerced to `Date`.

- planned_spend:

  Name of the flight's total spend column.

- week:

  Name for the week column to create. Default `"week"`.

- week_start:

  Weekday the plan's weeks begin on — a name or 1-7 with Monday as 1.
  Default `"Monday"`, the US broadcast convention.

- period_basis:

  Optional column naming each flight's cadence, validated against
  [`period_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/period_basis_levels.md).
  Inferred per flight when absent.

- name:

  Formal plan name. **Required**.

- ...:

  Further arguments passed to
  [`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
  — `nickname`, `advertiser`, `planner`, `status`, `objective`, `id`,
  `parent_id`.

## Value

A validated
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
at grain `c(grain, week)`, carrying the
[`flight_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_cols.md).

## Details

Spend is spread evenly across the flight's days and then gathered into
the weeks those days fall in, so a flight that starts mid-week
contributes a part week at each ragged end. The split is exact to the
cent: the weekly figures always re-sum to the flight total.

Each input row is given a `flight_id`, which is what makes
[`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
an exact inverse. Without it the expansion could not be undone — four
equal weeks are indistinguishable from four weekly buys.

## Examples

``` r
buys <- data.frame(
  channel      = c("OOH", "Search"),
  partner      = c("JCDecaux", "Google"),
  flight_start = as.Date(c("2026-04-06", "2026-04-08")),
  flight_end   = as.Date(c("2026-05-03", "2026-04-08")),
  planned_spend = c(120000, 3100)
)

p <- media_plan_from_flights(buys, grain = c("channel", "partner"),
                             name = "Q2 flights")
p@data
#>   channel  partner       week planned_spend              flight_id flight_start
#> 1     OOH JCDecaux 2026-04-06         30000 fl_20260817005512_a909   2026-04-06
#> 2     OOH JCDecaux 2026-04-13         30000 fl_20260817005512_a909   2026-04-06
#> 3     OOH JCDecaux 2026-04-20         30000 fl_20260817005512_a909   2026-04-06
#> 4     OOH JCDecaux 2026-04-27         30000 fl_20260817005512_a909   2026-04-06
#> 5  Search   Google 2026-04-06          3100 fl_20260817005512_c3ff   2026-04-08
#>   flight_end period_basis pacing
#> 1 2026-05-03       flight   even
#> 2 2026-05-03       flight   even
#> 3 2026-05-03       flight   even
#> 4 2026-05-03       flight   even
#> 5 2026-04-08          day   even
flights(p)
#>   channel  partner              flight_id flight_start flight_end period_basis
#> 1     OOH JCDecaux fl_20260817005512_a909   2026-04-06 2026-05-03       flight
#> 2  Search   Google fl_20260817005512_c3ff   2026-04-08 2026-04-08          day
#>   pacing planned_spend n_weeks
#> 1   even        120000       4
#> 2   even          3100       1
```
