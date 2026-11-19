# Check a plan against a budget envelope

Compares a plan with the budget it was authorised under: rows such as
"Streaming, October to December, 1.2m". For each budget row, the plan's
spend on the matching line items inside that window is summed, and the
variance reported. Rows whose variance is more than `tolerance` either
way are listed in a warning.

## Usage

``` r
check_budget(plan, budget, tolerance = 0.5)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- budget:

  A data frame, one row per envelope: `from` and `to` (the window,
  inclusive; `Date` or ISO strings), `amount`, and any of the plan's
  [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
  columns naming which line items it covers. A column left out, or `NA`
  in a row, means every value – a row with no line item columns is a
  whole-plan envelope.

- tolerance:

  How far planned spend may sit from a budget row's `amount`, either
  way, before the row is reported. In the plan's money; default half a
  unit, i.e. a rounding difference.

## Value

The budget rows, with `from` and `to` as dates, plus:

- `planned`:

  The plan's spend on those line items in that window.

- `variance`:

  `planned - amount`: positive is over budget.

- `variance_pct`:

  `variance / amount`; `NA` for a zero budget.

- `in_plan`:

  `FALSE` when the row names a value the plan does not have at all – a
  channel with no line items – so its `planned` of 0 is an absence
  rather than an underspend.

- `within`:

  Whether the variance is within `tolerance`.

## Details

Budget rows may name any subset of the plan's line item columns, at any
window, and may overlap – a quarterly channel envelope and a whole-year
total can sit in one table. Spend is measured day by day (through
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)),
so a window that ends mid-week takes only the days of that week inside
it, whatever the plan is keyed by.

Like
[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md),
this **warns rather than errors**: the plan and the budget are each
valid, and it is their pairing that disagrees.

## An envelope is not a subplan

Both put a number on part of a plan, and they are easy to confuse. A
budget envelope is a **target**: the plan is checked against it, with a
tolerance, and nothing stops the plan from missing it. A subplan
([`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md))
is **ownership**: a team plans that cell's detail, and the plan's rows
there *are* the subplan's rollup, exactly, and cannot be edited around
it. Signed channel-by-quarter authorisations are an envelope.

## See also

[`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md)
for a cell a team owns outright;
[`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md),
which summarises the variances when given a budget.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(month = rep(as.Date(c("2026-10-01", "2026-11-01",
                                   "2026-12-01")), each = 2),
             channel = c("Streaming", "Search"),
             planned_spend = c(400, 100, 400, 100, 420, 100)),
  grain = "channel", time = "month", name = "Q4"
)
budget <- data.frame(
  channel = c("Streaming", "Search", NA),
  from = "2026-10-01", to = "2026-12-31",
  amount = c(1200, 300, 1500)
)
check_budget(plan, budget)
#> Warning: 2 budget row(s) off by more than 0.5: channel Streaming, 2026-10-01..2026-12-31: planned 1,220 against 1,200 (+20); (whole plan), 2026-10-01..2026-12-31: planned 1,520 against 1,500 (+20).
#>     channel       from         to amount planned variance variance_pct in_plan
#> 1 Streaming 2026-10-01 2026-12-31   1200    1220       20   0.01666667    TRUE
#> 2    Search 2026-10-01 2026-12-31    300     300        0   0.00000000    TRUE
#> 3      <NA> 2026-10-01 2026-12-31   1500    1520       20   0.01333333    TRUE
#>   within
#> 1  FALSE
#> 2   TRUE
#> 3  FALSE
```
