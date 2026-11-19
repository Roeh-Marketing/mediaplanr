# Build a transfer op: move money between line items

The most common real edit to a plan: *"move 37,419 from DSP A in October
to the regional tactic in October."* A transfer takes `amount` out of
the `from` rows and puts it into the `to` rows, so the plan's total does
not change. Written as two `delta` ops, the same edit loses the fact
that its halves belong together; as one op it is one intent, and one
scenario.

## Usage

``` r
op_transfer(
  amount,
  from,
  to,
  during = NULL,
  from_during = NULL,
  to_during = NULL
)
```

## Arguments

- amount:

  A single number, more than 0: how much to move.

- from, to:

  Named lists of grain column = value(s): the rows the money comes from
  and goes to.

- during:

  Optional `list(from =, to =)` narrowing both sides.

- from_during, to_during:

  Optional `list(from =, to =)` narrowing one side each, instead of
  `during`.

## Value

A plain list: one edit op, for the `edits` argument of
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md).

## Details

Like every [op
constructor](https://roeh-marketing.github.io/mediaplanr/reference/ops.md),
this returns a plain list –
`list(transfer = amount, from = from, to = to, ...)` – and checks it
where it is written.

## How the money is spread

**The source gives in proportion** to what each of its rows plans,
exactly like `delta = -amount`. Its mix holds, so an evenly paced flight
stays even. It cannot give more than it holds.

**The destination receives in proportion** to what its rows plan,
exactly like `delta = +amount` – unless it plans **nothing**, when there
is no mix to follow. Then the amount is spread **evenly by in-market
days** across the matched rows: the rule an evenly paced flight follows,
so money moved into an empty flight lands as if the flight had been
bought that way. A flight that starts on a Wednesday gets five days'
worth in its first week and seven in each full week.

## Choosing the two sides

`from` and `to` are targets, with the same rules as `target` in any op:
a named list of grain column = value(s), naming any subset of the grain.
A value that is not in the plan is an error, never a silent no-op.

- `during` narrows **both** sides to the rows in market in that window.

- `from_during` and `to_during` narrow **one** side each, so the same
  line item can move money between months. Give these or `during`, not
  both.

The two sides must not share a row: money cannot move from a row to
itself. The destination must already be in the plan; to move money into
a new line item, `add` it first, earlier in the same edits list. Rows a
subplan owns are read-only on either side.

## See also

[ops](https://roeh-marketing.github.io/mediaplanr/reference/ops.md) for
the other operations;
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
to apply them.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(month = as.Date(c("2026-10-01", "2026-11-01")),
             channel = rep(c("Streaming", "Online Video"), each = 2),
             planned_spend = c(60000, 40000, 20000, 0)),
  grain = "channel", time = "month", name = "Q4"
)

# Move 10,000 from Streaming to Online Video across the quarter
op_transfer(10000, from = list(channel = "Streaming"),
            to = list(channel = "Online Video"))
#> $transfer
#> [1] 10000
#> 
#> $from
#> $from$channel
#> [1] "Streaming"
#> 
#> 
#> $to
#> $to$channel
#> [1] "Online Video"
#> 
#> 

# Move it within one line item, from October into November. November's
# Online Video plans nothing, so it takes the whole amount.
s <- build_scenario(plan, name = "pull into November", edits = op_transfer(
  5000, from = list(channel = "Online Video"),
  to = list(channel = "Online Video"),
  from_during = list(from = "2026-10-01", to = "2026-10-31"),
  to_during   = list(from = "2026-11-01", to = "2026-11-30")))
s@data
#>        month      channel planned_spend
#> 1 2026-10-01    Streaming         60000
#> 2 2026-11-01    Streaming         40000
#> 3 2026-10-01 Online Video         15000
#> 4 2026-11-01 Online Video          5000
```
