# Getting started

``` r

library(mediaplanr)
```

This walks the whole path: get a plan in, change it, fork scenarios,
compare them. It sticks to *what to type*. For *why the package is
shaped this way* — what a line item is, why a plan cannot tell you what
is historical — read
[`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md).

## A plan in three lines

The smallest useful plan is a table with something to key on and a spend
column.

``` r

simple <- media_plan_from_df(
  data.frame(
    channel       = c("TV", "Search", "Social"),
    planned_spend = c(80000, 40000, 40000)
  ),
  grain = "channel",
  name  = "Q3 sketch"
)

simple
#> <MediaPlan> Q3 sketch
#>   grain       channel
#>   rows        3
#>   spend       160,000
#>   id          plan_acd597
#> 
#>    channel planned_spend
#>         TV         80000
#>     Search         40000
#>     Social         40000
```

`name` is required — every plan carries one. Everything else is
optional.

## A realistic plan

Real plans are weekly and keyed by more than channel. Here is a quarter
at `channel + partner + week`:

``` r

weeks <- seq(as.Date("2026-04-06"), by = "week", length.out = 6)

plan_df <- expand.grid(
  week    = weeks,
  partner = c("NBC", "ESPN", "Google", "Meta"),
  stringsAsFactors = FALSE
)
plan_df$channel <- c(NBC = "TV", ESPN = "TV",
                     Google = "Search", Meta = "Social")[plan_df$partner]
plan_df$planned_spend <- c(42000, 28000, 19000, 23000)[
  match(plan_df$partner, c("NBC", "ESPN", "Google", "Meta"))
]

base <- media_plan_from_df(
  plan_df,
  grain      = c("channel", "partner", "week"),
  week       = "week",
  name       = "Q2 2026 Brand Plan",
  nickname   = "baseline",
  advertiser = "Acme Corp",
  planner    = "R. Roe",
  status     = "approved"
)

base
#> <MediaPlan> Q2 2026 Brand Plan ("baseline")  [approved]
#>   advertiser  Acme Corp
#>   planner     R. Roe
#>   grain       channel + partner + week
#>   weeks       2026-04-06 to 2026-05-11  (6 weeks)
#>   line items  4
#>   rows        24
#>   spend       672,000
#>   id          plan_cb283f
#> 
#>          week partner channel planned_spend
#>    2026-04-06     NBC      TV         42000
#>    2026-04-13     NBC      TV         42000
#>    2026-04-20     NBC      TV         42000
#>   ... 21 more rows
```

Two things to notice in that call:

- `grain` names the columns that identify a **row**. Order it
  coarsest-first;
  [`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
  later relies on that nesting.
- `week` marks which grain column is the week. It is validated as a
  `Date`, so ordering and range checks work without re-parsing.

`@data` stays an ordinary data frame throughout. The class adds
guarantees, not a wrapper you have to fight:

``` r

head(base@data, 3)
#>         week partner channel planned_spend
#> 1 2026-04-06     NBC      TV         42000
#> 2 2026-04-13     NBC      TV         42000
#> 3 2026-04-20     NBC      TV         42000
sum(base@data$planned_spend)
#> [1] 672000
```

## Editing: three shapes, one door

[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
is the only way to change spend, and it always returns a **new** plan.
`edits` accepts three shapes; they exist because three different callers
need different things.

### 1. Operations — for a UI or an LLM

State what you want done and let R compute it. `target` may name any
**subset** of the grain, so one operation reaches many rows.

``` r

trim <- build_scenario(
  base,
  edits    = list(target = list(channel = "TV"), scale = 0.8),
  name     = "Q2 2026 Brand Plan — TV trim",
  nickname = "TV -20%"
)

sum(trim@data$planned_spend)
#> [1] 588000
```

Operations apply in order, so a budget-neutral shift is two of them:

``` r

shift <- build_scenario(
  base,
  edits = list(
    list(target = list(channel = "TV"),     total = 350000),
    list(target = list(channel = "Social"), total = 200000)
  ),
  name     = "Q2 2026 Brand Plan — reshaped",
  nickname = "TV→Social"
)

sum(shift@data$planned_spend)
#> [1] 664000
```

The four operations, and the distinction that catches people out:

| Operation | Effect on matched rows                          |
|-----------|-------------------------------------------------|
| `set`     | each row becomes exactly this                   |
| `scale`   | multiply each row (`1.2` = +20%)                |
| `delta`   | add to each row (may be negative)               |
| `total`   | rows **sum** to this, holding their current mix |

`set` is per row; `total` is across rows. “Set the TV budget to 350k” is
almost always `total`.

A target value that does not exist is an error naming the alternatives —
never a silent no-op:

``` r

build_scenario(base, edits = list(target = list(channel = "Radio"), scale = 2),
               name = "typo")
#> Error:
#> ! edit op 1: no such value(s) in 'channel': Radio. Valid: TV, Search, Social
```

That matters most when a language model is generating the calls: a quiet
no-op would look exactly like success.

### 2. A data frame — for absolute allocations

Natural for optimizer output, where you already have the numbers:

``` r

alloc <- data.frame(
  channel       = c("TV", "TV"),
  partner       = c("NBC", "ESPN"),
  week          = c(weeks[1], weeks[1]),
  planned_spend = c(50000, 20000)
)

opt <- build_scenario(base, edits = alloc,
                      name      = "Q2 2026 Brand Plan — optimized",
                      nickname  = "optimized",
                      objective = "max KPI at 70k for w/c Apr 6")
```

Note `objective`: the package never learns *how* the numbers were
chosen, so that free-text field is where you record it.

### 3. A named vector — for one or two cells

Keyed by
[`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
over the full grain. Terse, and what an editable table produces:

``` r

key <- line_item(base@data, base@grain)[1]
key
#> [1] "TV | NBC | 2026-04-06"

nudge <- build_scenario(base, edits = stats::setNames(45000, key),
                        name = "Q2 2026 Brand Plan — nudge")
```

## Scenarios and lineage

Deriving never touches the parent, and every scenario records where it
came from:

``` r

identical(sum(base@data$planned_spend), sum(plan_df$planned_spend))
#> [1] TRUE
identical(trim@parent_id, base@id)
#> [1] TRUE
```

`status` is deliberately **not** inherited — a scenario forked from an
approved plan is not itself approved:

``` r

base@status
#> [1] "approved"
trim@status
#> [1] "in development"
```

## Collecting and comparing

A `ScenarioSet` is the comparison registry. Labels prefer `@nickname`,
so a set under development reads well without renaming the formal plans:

``` r

set <- scenario_set(base)
set <- add_scenario(set, trim)
set <- add_scenario(set, shift)

set
#> <ScenarioSet>  3 scenarios at channel + partner + week
#>   advertiser  Acme Corp
#> 
#>     scenario   status            spend         vs base
#>   * baseline   approved        672,000               -
#>     TV -20%    in development  588,000  -84,000 (-12%)
#>     TV→Social  in development  664,000    -8,000 (-1%)
#> 
#>   * = baseline
```

Two levels of comparison:

``` r

compare_scenarios(set, "summary")
#>    scenario                    plan_id                  parent_id
#> 1  baseline plan_20260803222304_cb283f                       <NA>
#> 2   TV -20% plan_20260803222305_e47766 plan_20260803222304_cb283f
#> 3 TV→Social plan_20260803222305_6e4a2f plan_20260803222304_cb283f
#>   total_planned_spend spend_vs_base spend_pct_vs_base
#> 1              672000             0        0.00000000
#> 2              588000        -84000       -0.12500000
#> 3              664000         -8000       -0.01190476
```

``` r

head(compare_scenarios(set, "cell"), 4)
#>   scenario channel partner       week planned_spend share_of_total
#> 1 baseline      TV     NBC 2026-04-06         42000         0.0625
#> 2 baseline      TV     NBC 2026-04-13         42000         0.0625
#> 3 baseline      TV     NBC 2026-04-20         42000         0.0625
#> 4 baseline      TV     NBC 2026-04-27         42000         0.0625
#>   spend_vs_base
#> 1             0
#> 2             0
#> 3             0
#> 4             0
```

The `"cell"` level compares over the **union** of grain cells across the
set, so a line item one scenario adds and another lacks still gets a
real delta rather than `NA` or a missing row.

## Rolling up

[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
aggregates to a coarser grain — useful when you need channel totals, or
to find the nearest level at which a response model exists for a
brand-new partner:

``` r

roll_up(base, c("channel", "week"))@data |> head(4)
#>   channel       week planned_spend
#> 1      TV 2026-04-06         70000
#> 2      TV 2026-04-13         70000
#> 3      TV 2026-04-20         70000
#> 4      TV 2026-04-27         70000
```

## Where to next

- [`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md)
  — what a plan *is*, and the boundaries that keep it small.
- [`?build_scenario`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
  — the full edit-form reference.
- [`?check_coverage`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  — pairing a plan with a decomp.
