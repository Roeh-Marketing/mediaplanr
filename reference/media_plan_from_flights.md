# Build a plan from flights rather than periods

The other door into a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).
Where
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
takes the plan already laid out period by period, this takes it as a
planner states it — one row per **flight**, with in-market dates and a
total — and expands it onto the rows `@data` holds. Everything
downstream (the grid,
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md),
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md),
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md))
sees the ordinary shape.

## Usage

``` r
media_plan_from_flights(
  df,
  grain,
  start = "flight_start",
  end = "flight_end",
  planned_spend = "planned_spend",
  basis = c("week", "day", "month", "instant"),
  time = NULL,
  week_start = "Monday",
  tz = NULL,
  period_basis = NULL,
  name,
  ...
)
```

## Arguments

- df:

  A data frame with one row per flight: the line item columns, a start
  date, an end date, and a spend. Optional `min_spend` and `max_spend`
  ([`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md))
  bound the whole flight, and are split across its periods beside its
  spend, so every period stays within its bounds and a committed flight
  is committed in every period.

- grain:

  Character vector naming the **line item** columns (channel, partner,
  tactic). The time column is created and appended, so do not include
  it.

- start, end:

  Names of the flight start and end date columns. `end` is inclusive.
  Coerced to `Date`.

- planned_spend:

  Name of the flight's total spend column.

- basis:

  The calendar the flights are expanded onto, and the plan's
  `@time_basis`: `"week"` (default), `"day"`, `"month"` or `"instant"`.
  `"instant"` is for buys bought by the slot rather than the period — a
  30-second spot at 20:00:00, a half-hour sponsorship from 20:00 to
  20:30. Each one becomes a single row keyed at the moment it starts,
  carrying its whole total: there is nothing to spread, and the buy's
  length is read back off its flight dates.

- time:

  Name for the time column to create. Defaults to `basis`, so a weekly
  plan gets a `week` column and a monthly one a `month` column; a timed
  plan gets `time`.

- week_start:

  Weekday the plan's weeks begin on — a name or 1-7 with Monday as 1.
  Default `"Monday"`, the US broadcast convention. Used when
  `basis = "week"`.

- tz:

  The plan's timezone, as an Olson name. Timed flight dates given as
  strings are read on it. See
  [`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md).

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
at grain `c(grain, time)`, carrying the
[`flight_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_cols.md).

## Details

Spend is spread evenly across the flight's days and then gathered into
the periods those days fall in, so a flight that starts mid-week
contributes a part week at each ragged end. The split is exact to the
cent: the period figures always re-sum to the flight total.

A buy bought by the slot rather than the period — a 30-second spot, a
half-hour sponsorship — is the degenerate case: with `basis = "instant"`
each one becomes a single row at the moment it starts, carrying its
whole total. Nothing is spread, and the buy's length is read back off
its flight.

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
#> 1     OOH JCDecaux 2026-04-06         30000 fl_20261122212515_3dc7   2026-04-06
#> 2     OOH JCDecaux 2026-04-13         30000 fl_20261122212515_3dc7   2026-04-06
#> 3     OOH JCDecaux 2026-04-20         30000 fl_20261122212515_3dc7   2026-04-06
#> 4     OOH JCDecaux 2026-04-27         30000 fl_20261122212515_3dc7   2026-04-06
#> 5  Search   Google 2026-04-06          3100 fl_20261122212515_d5b6   2026-04-08
#>   flight_end period_basis pacing
#> 1 2026-05-03       flight   even
#> 2 2026-05-03       flight   even
#> 3 2026-05-03       flight   even
#> 4 2026-05-03       flight   even
#> 5 2026-04-08          day   even
flights(p)
#>   channel  partner              flight_id flight_start flight_end period_basis
#> 1     OOH JCDecaux fl_20261122212515_3dc7   2026-04-06 2026-05-03       flight
#> 2  Search   Google fl_20261122212515_d5b6   2026-04-08 2026-04-08          day
#>   pacing planned_spend n_periods
#> 1   even        120000         4
#> 2   even          3100         1
```
