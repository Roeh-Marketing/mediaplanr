# Build a rebound op: change what spend rows may hold

Sets the spend bounds – `min_spend` and `max_spend`, see
[`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)
– on each matched row. It changes **no spend**. Bounds record money that
cannot move, so changing one is a deliberate act of its own, never a
side effect of moving money: lowering a floor so a line can be cut takes
a `rebound` and then the cut, in that order, in one edits list.

## Usage

``` r
op_rebound(min = NULL, max = NULL, target = NULL, during = NULL)
```

## Arguments

- min, max:

  The new floor and cap for each matched row: a number of 0 or more,
  `NA` to remove that bound, or `NULL` (the default) to leave it as it
  is. Give at least one.

- target, during:

  Select the rows, as in every op; see
  [ops](https://roeh-marketing.github.io/mediaplanr/reference/ops.md).

## Value

A plain list: one edit op, for the `edits` argument of
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md).

## Details

Like every [op
constructor](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
this returns a plain list –
`list(rebound = list(min = , max = ), target = , during = )` – and
checks it where it is written.

Each bound is set per row, so `min = 5000` on a monthly line item puts a
floor of 5,000 under every month it matches. A bound left out (`NULL`)
is unchanged; `NA` removes it. The new bounds must still contain the
spend each row already plans, or the op is refused naming the rows;
change the spend first, earlier in the same edits, if it needs to move.

## See also

[`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)
for what the bounds mean;
[ops](https://roeh-marketing.github.io/mediaplanr/reference/ops.md) for
the other operations.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(month = as.Date(c("2026-10-01", "2026-11-01")),
             channel = "Streaming", planned_spend = c(60000, 40000),
             min_spend = c(60000, 40000), max_spend = c(60000, 40000)),
  grain = "channel", time = "month", name = "Q4"
)

# Committed spend cannot be cut ...
try(build_scenario(plan, edits = op_delta(-10000), name = "cut"))
#> Error : edit op 1: `delta` of -10,000 cannot take 10,000 out of these rows: their floors leave 0 to give. Floors: Streaming | 2026-10-01 (committed); Streaming | 2026-11-01 (committed). Ask for less, or lower the floors first with `rebound`.

# ... until the commitment is lowered, first, in the same edits
s <- build_scenario(plan, name = "renegotiated", edits = list(
  op_rebound(min = 30000, target = list(month = "2026-11-01")),
  op_delta(-10000, target = list(month = "2026-11-01"))
))
s@data
#>        month   channel planned_spend min_spend max_spend
#> 1 2026-10-01 Streaming         60000     60000     60000
#> 2 2026-11-01 Streaming         30000     30000     40000
```
