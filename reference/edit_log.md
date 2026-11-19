# The edits behind every scenario in a set, one row per op

Reads each scenario's `@edits` – the record
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
keeps of exactly what it applied – and lays them out as a change log:
one row per op, scenarios in lineage order (roots first, then each
generation), ops in the order they were applied. Alongside each op it
carries who proposed the scenario (`@rationale$author`) and why
(`@objective`).

## Usage

``` r
edit_log(set)
```

## Arguments

- set:

  A
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md).

## Value

A data frame with one row per op:

- `scenario`, `parent`:

  The scenario's label, and its parent's (its short id when the parent
  is not in the set).

- `author`:

  `@rationale$author`: `"human"`, `"agent"`, `"optimizer"`, or `NA` when
  unstated.

- `op`:

  The operation, e.g. `"transfer"`, or `"allocation"`.

- `target`:

  The rows the op acts on, as `column value` – `"partner DSP A"`. For a
  transfer, its source; for `add`, the line item it creates;
  `"(whole plan)"` when the op names no target.

- `to`:

  A transfer's destination; `NA` for every other op.

- `amount`:

  The money the op states: the amount a transfer moves, a `delta`, an
  added line's spend, an allocation's net change. `NA` for ops that
  state no amount (`scale`, `set`, `shift`, ...).

- `detail`:

  The op's own value, in words: `"x1.2"`, `"+7 days"`, `"min 30,000"`.

- `window`:

  The op's `during` window, or a transfer's per-side windows; `NA` when
  it has none.

- `objective`:

  The scenario's `@objective`.

## Details

An allocation edit (a data frame or named vector of absolute spend,
typically an optimizer's output) is one row, `op = "allocation"`, whose
`amount` is the net change in the plan's total. A scenario with no
recorded edits – a root, or a plan imported from a file – contributes no
rows.

## See also

[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
for how edits and rationale are recorded;
[`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
for the derivation tree itself.

## Examples

``` r
base <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search", "Social"),
             planned_spend = c(80, 40, 40)),
  grain = "channel", time = "week", name = "base"
)
s1 <- build_scenario(
  base, name = "Search push", objective = "Lift search share",
  edits = op_transfer(20, from = list(channel = "TV"),
                      to = list(channel = "Search")),
  rationale = list(author = "agent", goal = "maximise conversions")
)
s2 <- build_scenario(
  s1, name = "Trim social", objective = "Budget cut",
  edits = list(op_scale(0.5, target = list(channel = "Social")),
               op_delta(-5, target = list(channel = "TV"))),
  rationale = list(author = "human")
)
edit_log(add_scenario(add_scenario(scenario_set(base), s1), s2))
#>      scenario      parent author       op         target             to amount
#> 1 Search push        base  agent transfer     channel TV channel Search     20
#> 2 Trim social Search push  human    scale channel Social           <NA>     NA
#> 3 Trim social Search push  human    delta     channel TV           <NA>     -5
#>   detail window         objective
#> 1   <NA>   <NA> Lift search share
#> 2   x0.5   <NA>        Budget cut
#> 3   <NA>   <NA>        Budget cut
```
