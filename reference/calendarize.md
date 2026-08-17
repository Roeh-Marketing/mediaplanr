# Re-cut a plan onto a different calendar

The temporal counterpart to
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md).
Where
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
aggregates over *dimensions* — channel, partner, tactic — this
aggregates over *time*: it spreads each row's spend across the days it
is actually in market, then gathers those days into days, weeks or
months.

## Usage

``` r
calendarize(plan, basis = c("week", "day", "month"), week_start = NULL)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  with a time dimension.

- basis:

  `"week"` (default), `"day"` or `"month"`.

- week_start:

  Weekday weeks begin on, when `basis = "week"`. Defaults to the plan's
  own, read off its data by
  [`week_start()`](https://roeh-marketing.github.io/mediaplanr/reference/week_start.md).

## Value

A data frame: the line item columns, a date column named after `basis`
holding each period's start, and `planned_spend`. One row per line item
per period, ordered by period.

## Details

The two are deliberately separate verbs rather than one with a mode
flag, so they compose: roll a plan up to channel, then cut it to months,
in whichever order suits.

Because each row's period is its week **clipped to its flight**, a
flight that starts mid-week contributes only its real days. Re-cutting
to months therefore splits a week that straddles a month boundary, which
is exactly the thing that is tedious and error-prone to do by hand.
Spend is split in whole cents that re-sum to the row's original total.

## Why a data frame, not a plan

This returns a **projection**, like
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
— something to chart, export, or hand to a reconciliation. It is not a
[MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md),
because aggregating over time can merge two of a line item's rows into
one period, and a flight that spanned them is no longer one row's worth
of anything: the flighting columns cannot survive the operation
honestly, so they are dropped rather than guessed at. Editing belongs on
the plan, where the flights still are. If you do want a plan at the new
grain, pass the result to
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md).

## Examples

``` r
p <- media_plan_from_flights(
  data.frame(channel = "OOH",
             flight_start = as.Date("2026-04-20"),
             flight_end   = as.Date("2026-05-10"),
             planned_spend = 210000),
  grain = "channel", name = "Straddles a month end"
)

calendarize(p, "week")
#>   channel       week planned_spend
#> 1     OOH 2026-04-20         70000
#> 2     OOH 2026-04-27         70000
#> 3     OOH 2026-05-04         70000
calendarize(p, "month")   # the week of Apr 27 is split across April and May
#>   channel      month planned_spend
#> 1     OOH 2026-04-01        110000
#> 2     OOH 2026-05-01        100000
```
