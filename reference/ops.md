# Build an edit op

Constructors for the operations
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
applies. Each returns the **plain list** you would otherwise write by
hand, so a constructor-built op, a hand-written one and one parsed from
an agent's JSON are interchangeable:

## Usage

``` r
op_set(value, target = NULL, during = NULL)

op_scale(by, target = NULL, during = NULL)

op_delta(by, target = NULL, during = NULL)

op_delta_each(by, target = NULL, during = NULL)

op_total(value, target = NULL, during = NULL)

op_add(...)

op_drop(target = NULL, during = NULL)

op_shift(days, target = NULL, during = NULL)

op_restage(from, to, target = NULL, during = NULL)
```

## Arguments

- value:

  A single number: planned spend per row (`op_set()`) or for the matched
  rows in total (`op_total()`). Not negative.

- target:

  Optional named list of grain column = value(s) selecting the rows to
  act on, e.g. `list(channel = c("TV", "Radio"))`. Omit to match every
  row.

- during:

  Optional `list(from =, to =)` narrowing to rows in market at any point
  in that window.

- by:

  A single number: the multiplier (`op_scale()`, not negative) or the
  amount to add (`op_delta()`, `op_delta_each()`; negative to cut).

- ...:

  For `op_add()`: the new line item's columns, named.

- days:

  A whole number of days; negative moves earlier.

- from, to:

  The new in-market dates: `Date`, `POSIXct`, or ISO-8601 strings.

## Value

A plain list: one edit op, ready for the `edits` argument of
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
on its own or in a list of ops.

## Details

    op_scale(1.2, target = list(channel = "TV"))
    # is exactly
    list(scale = 1.2, target = list(channel = "TV"))

What a constructor adds is **checking where the op is written**: a wrong
type, a backwards window or an unparseable date errors here, before any
plan is involved. Whether the target exists in a particular plan can
only be known when the op is applied, so
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
checks that.

Fields come out in a fixed order – the operation, then `target`, then
`during` – and fields not given are left out, so
[`identical()`](https://rdrr.io/r/base/identical.html) holds against a
hand-written op in that order.
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
does not care about order.

## Operations

See *Edit forms* in
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
for the full rules.

- `op_set()`:

  Put `value` on **each** matched row.

- `op_total()`:

  Make the matched rows **sum** to `value`, holding their mix.

- `op_scale()`:

  Multiply each matched row by `by`.

- `op_delta()`:

  Move the matched rows' **sum** by `by`, holding their mix. The usual
  way to say "take 50k out of TV".

- `op_delta_each()`:

  Add `by` to **each** matched row.

- [`op_transfer()`](https://roeh-marketing.github.io/mediaplanr/reference/op_transfer.md):

  Move an amount from one set of rows to another, leaving the plan's
  total unchanged. Documented on its own page.

- `op_add()`:

  Introduce a line item, named by its columns in `...`: every line item
  column, `planned_spend`, and either the plan's time column or
  `flight_start` and `flight_end`.

- `op_drop()`:

  Remove the matched rows entirely.

- `op_shift()`:

  Move the matched flights by `days`.

- `op_restage()`:

  Move the matched flights to run `from`–`to`.

- [`op_rebound()`](https://roeh-marketing.github.io/mediaplanr/reference/op_rebound.md):

  Change the spend bounds on the matched rows, and no spend. Documented
  on its own page.

## See also

[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
to apply ops;
[`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
for the JSON Schema an agent's ops are checked against.

## Examples

``` r
op_scale(1.2, target = list(channel = "Search"))
#> $scale
#> [1] 1.2
#> 
#> $target
#> $target$channel
#> [1] "Search"
#> 
#> 

identical(op_scale(1.2, target = list(channel = "Search")),
          list(scale = 1.2, target = list(channel = "Search")))
#> [1] TRUE

op_add(channel = "Audio", week = "2026-07-06", planned_spend = 25)
#> $add
#> $add$channel
#> [1] "Audio"
#> 
#> $add$week
#> [1] "2026-07-06"
#> 
#> $add$planned_spend
#> [1] 25
#> 
#> 
op_restage("2026-08-03", "2026-08-30", target = list(channel = "TV"))
#> $restage
#> $restage$from
#> [1] "2026-08-03"
#> 
#> $restage$to
#> [1] "2026-08-30"
#> 
#> 
#> $target
#> $target$channel
#> [1] "TV"
#> 
#> 

# A malformed op errors where it is written.
try(op_shift(2.5))
#> Error : op_shift(): `shift` must be a single whole number of days (negative to move earlier).

base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search", "Social"),
             planned_spend = c(80, 40, 40)),
  grain = "channel", time = "week", name = "base"
)
build_scenario(base, name = "trim TV, drop Social", edits = list(
  op_delta(-10, target = list(channel = "TV")),
  op_drop(target = list(channel = "Social"))
))
#> <MediaPlan> trim TV, drop Social  [in development]
#>   grain       channel + week
#>   flight      2026-07-06 to 2026-07-12  (1 week)
#>   line items  2
#>     channel   Search, TV
#>   rows        2
#>   spend       110
#>   id          plan_f0e365   derived from plan_72dfcc
#> 
#>          week channel planned_spend
#>    2026-07-06      TV            70
#>    2026-07-06  Search            40
```
