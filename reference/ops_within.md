# Do these ops stay inside a scope?

Checks that every row a list of ops would touch lies inside a planner's
scope – a list of targets, such as the sections they own. The answer is
one row per op side that reaches outside it, so zero rows means every op
stays inside.

## Usage

``` r
ops_within(plan, ops, scope)
```

## Arguments

- plan:

  The
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  the ops would be applied to.

- ops:

  The ops, in any form
  [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
  takes them: a list of ops or a single op – plain lists, [op
  constructors](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
  or parsed from JSON – or a scenario's `@edits` record.

- scope:

  The scope: a target, or a list of targets. Empty is the whole plan.

## Value

A data frame with one row per op side that selects rows outside `scope`:

- `op`:

  The op's position in `ops`.

- `side`:

  `"target"`, `"from"`, `"to"` or `"add"`.

- `line_items`:

  A list column: the line items
  ([`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
  at
  [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md))
  that side reaches outside the scope.

## Details

Rows are resolved exactly as
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
resolves them, **in order**: an `add` earlier in the list creates rows a
later op may target, and a `drop` removes rows a later op can no longer
reach. `during`, and a transfer's `from_during` / `to_during`, narrow
each side as they do when the op is applied. An `add` is outside when
the line item it creates does not match the scope.

A target that does not exist is refused here with the error
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
gives. Ops that change which rows exist, when they run, or how they are
bound (`add`, `drop`, `shift`, `restage`, `rebound`) are applied as they
go, and refused as they would be there. Ops that only move money are not
applied: they cannot change what a later op selects, and whether the
money can move – past a floor, say – is
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)'s
question, whose answer must not hide this one. The scope is read
leniently
([`match_rows()`](https://roeh-marketing.github.io/mediaplanr/reference/match_rows.md)
with `strict = FALSE`): it may name values the plan no longer has.

## See also

[`match_rows()`](https://roeh-marketing.github.io/mediaplanr/reference/match_rows.md),
[`rebase_check()`](https://roeh-marketing.github.io/mediaplanr/reference/rebase_check.md)

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "TV", "Search", "Social"),
             partner = c("NBC", "ESPN", "Google", "Meta"),
             planned_spend = c(50, 30, 40, 40)),
  grain = c("channel", "partner"), time = "week", name = "Q3"
)
video <- list(channel = "TV")

# inside: money moves between two TV partners
ops_within(plan, op_transfer(10, from = list(partner = "NBC"),
                             to = list(partner = "ESPN")), video)
#> [1] op         side       line_items
#> <0 rows> (or 0-length row.names)

# outside: the money comes from Search
ops_within(plan, op_transfer(10, from = list(channel = "Search"),
                             to = list(partner = "ESPN")), video)
#>   op side      line_items
#> 1  1 from Search | Google
```
