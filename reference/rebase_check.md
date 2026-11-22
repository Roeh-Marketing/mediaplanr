# Would these ops do the same on the current revision?

A draft is a scenario under a base revision, and its ops are approved by
replaying them on the **current** revision, so approved revisions stay
one chain. That is safe when the rows the ops touch are the same on both
plans. This finds the rows where they are not.

## Usage

``` r
rebase_check(base, current, ops)
```

## Arguments

- base:

  The plan the ops were written against: the draft's parent.

- current:

  The plan they would be replayed on: normally the current approved
  revision. Must share `base`'s grain.

- ops:

  The ops, in any form
  [`ops_within()`](https://roeh-marketing.github.io/mediaplanr/reference/ops_within.md)
  takes – including the draft's own `@edits` record.

## Value

A data frame with one row per op side and row that differs:

- `op`, `side`:

  As in
  [`ops_within()`](https://roeh-marketing.github.io/mediaplanr/reference/ops_within.md).

- `row`:

  The row's key:
  [`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
  at the full grain.

- `issue`:

  `"changed"`, `"base only"` or `"current only"`.

- `columns`:

  For `"changed"`, the columns that differ, joined with `", "`; `NA`
  otherwise.

- `base_spend`, `current_spend`:

  The row's planned spend on each plan as the op finds it; `NA` where
  the op does not select it.

## Details

The ops are resolved on both plans, in order, as
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
would apply them. For each op side, the rows it selects on `base` are
compared with the rows it selects on `current`: a row selected on one
and not the other is reported, and so is a row selected on both whose
`planned_spend`, spend bounds
([`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md))
or flight columns
([`flight_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_cols.md))
differ. Those are the facts an op's arithmetic reads – a `delta` spreads
by the group's spend, a transfer routes around its bounds, money moved
into an empty line spreads by its flight days – so **zero rows means
replaying the ops on `current` does to those rows what it did on
`base`**.

Rows the ops do not touch may differ freely: a sibling section approved
in between is not a conflict. An `add` selects nothing, so it is
compared only through the ops after it. An op that cannot be applied to
one of the plans at all – its target is gone – is an error naming the
plan, since replaying it there would fail the same way.

## See also

[`ops_within()`](https://roeh-marketing.github.io/mediaplanr/reference/ops_within.md),
[`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md)

## Examples

``` r
base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "TV", "Search", "Social"),
             partner = c("NBC", "ESPN", "Google", "Meta"),
             planned_spend = c(50, 30, 40, 40)),
  grain = c("channel", "partner"), time = "week", name = "Rev 1"
)
draft <- op_transfer(10, from = list(partner = "NBC"),
                     to = list(partner = "ESPN"))

# Search was cut in the meantime: no conflict with a TV draft
current <- build_scenario(base, op_scale(0.5, list(channel = "Search")),
                          name = "Rev 2")
rebase_check(base, current, draft)
#> [1] op            side          row           issue         columns      
#> [6] base_spend    current_spend
#> <0 rows> (or 0-length row.names)

# NBC was cut: the draft's source is not what it was
current <- build_scenario(base, op_scale(0.5, list(partner = "NBC")),
                          name = "Rev 2")
rebase_check(base, current, draft)
#>   op side                   row   issue       columns base_spend current_spend
#> 1  1 from TV | NBC | 2026-07-06 changed planned_spend         50            25
```
