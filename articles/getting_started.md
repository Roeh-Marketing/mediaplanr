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
#>     channel   Search, Social, TV
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
#>   flight      2026-04-06 to 2026-05-17  (6 weeks)
#>   line items  4
#>     channel   Search, Social, TV
#>     partner   ESPN, Google, Meta, NBC
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

## The other door in: flights

Planners do not always write a plan by week. Often a buy is stated as
**in-market dates and a total** — “OOH, 6 April to 3 May, 120k”. That is
a **flight**, and
[`media_plan_from_flights()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md)
takes it directly:

``` r

buys <- data.frame(
  channel       = c("OOH", "Search", "TV"),
  partner       = c("JCDecaux", "Google", "NBC"),
  flight_start  = as.Date(c("2026-04-06", "2026-04-08", "2026-04-06")),
  flight_end    = as.Date(c("2026-05-03", "2026-04-08", "2026-04-12")),
  planned_spend = c(120000, 3100, 33333)
)

flighted <- media_plan_from_flights(
  buys, grain = c("channel", "partner"), name = "Q2 flighting"
)

flighted@data[, c("channel", "week", "planned_spend", "period_basis")]
#>   channel       week planned_spend period_basis
#> 1     OOH 2026-04-06         30000       flight
#> 2     OOH 2026-04-13         30000       flight
#> 3     OOH 2026-04-20         30000       flight
#> 4     OOH 2026-04-27         30000       flight
#> 5  Search 2026-04-06          3100          day
#> 6      TV 2026-04-06         33333         week
```

The flight is **expanded onto the weekly rows `@data` already holds**,
so the grid,
[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md),
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
and
[`compare_scenarios()`](https://roeh-marketing.github.io/mediaplanr/reference/compare_scenarios.md)
all see the ordinary shape. Spend is spread across the buy’s days and
gathered into those weeks, exactly to the cent — note the 33,333
dividing cleanly, and the single-day Search buy sitting inside its week.

Going back the other way is exact:

``` r

flights(flighted)
#>   channel  partner              flight_id flight_start flight_end period_basis
#> 1     OOH JCDecaux fl_20260817005515_7766   2026-04-06 2026-05-03       flight
#> 2      TV      NBC fl_20260817005515_c5c4   2026-04-06 2026-04-12         week
#> 3  Search   Google fl_20260817005515_4a2f   2026-04-08 2026-04-08          day
#>   pacing planned_spend n_weeks
#> 1   even        120000       4
#> 2   even         33333       1
#> 3   even          3100       1
```

That works because each buy’s identity is stored. It is **not**
inferred: a plan built by
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
records no flights and says so, rather than guessing that four equal
weeks were one buy.

``` r

nrow(flights(base))
#> [1] 0
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

The five spend operations, and the distinction that catches people out:

| Operation    | Effect on matched rows                          |
|--------------|-------------------------------------------------|
| `total`      | rows **sum** to this, holding their current mix |
| `delta`      | rows’ **sum** moves by this, holding their mix  |
| `scale`      | multiply each row (`1.2` = +20%)                |
| `set`        | each row becomes exactly this                   |
| `delta_each` | add to each row (may be negative)               |

The split that catches people out runs both ways:

|          | across the matched rows | to each matched row |
|----------|-------------------------|---------------------|
| absolute | `total`                 | `set`               |
| relative | `delta`                 | `delta_each`        |

“Set the TV budget to 350k” is `total`, not `set`. “Take 50k out of TV”
is `delta`, not `delta_each` — on a 26-week plan `delta_each = -50000`
would take out 1.3 million, and because the two sides of a transfer
often cancel, the plan total still reconciles while every channel is
wrong. Reach for the left-hand column unless you specifically mean
“every week”.

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

#### Changing which rows there are

The operations above change spend on rows that already exist. Four more
change the row set itself, so a plan can gain and lose line items:

| Operation | Effect                                             |
|-----------|----------------------------------------------------|
| `add`     | introduce a line item, for one week or as a flight |
| `drop`    | remove the matched rows entirely                   |
| `shift`   | move the matched buys by ±N days                   |
| `restage` | move the matched buys to explicit dates            |

``` r

reshaped <- build_scenario(base, edits = list(
  list(add = list(channel = "Audio", partner = "Spotify",
                  week = weeks[1], planned_spend = 25000)),
  list(target = list(partner = "ESPN"), drop = TRUE)
), name = "Q2 2026 Brand Plan — Audio in, ESPN out", nickname = "reshaped")

grain_values(reshaped, "partner")
#> [1] "Google"  "Meta"    "NBC"     "Spotify"
```

`drop` is not the same as setting a row to zero: a dropped line item is
not bought at all, where a zeroed one is still in the plan at nothing.

Selection grows an axis too. `during` narrows any operation to rows
whose in-market period **overlaps** a window, so “cut back the back half
of April” reaches a buy that started in March and is still running:

``` r

build_scenario(base, edits = list(
  during = list(from = "2026-04-20", to = "2026-04-30"), scale = 0.5
), name = "Q2 2026 Brand Plan — late April trim", nickname = "late Apr -50%")@data |>
  head(3)
#>         week partner channel planned_spend
#> 1 2026-04-06     NBC      TV         42000
#> 2 2026-04-13     NBC      TV         42000
#> 3 2026-04-20     NBC      TV         21000
```

`during` *selects* rows; it never slices them, so a buy half inside the
window is matched whole.

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
#> 1  baseline plan_20260817005515_cb283f                       <NA>
#> 2   TV -20% plan_20260817005516_c45205 plan_20260817005515_cb283f
#> 3 TV→Social plan_20260817005516_fe3218 plan_20260817005515_cb283f
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

There is a third level, for plans that record flights. It compares the
**buys** rather than the cells, and names what happened to each:

``` r

moved <- build_scenario(flighted,
                        edits = list(target = list(channel = "OOH"), shift = 7),
                        name = "OOH pushed a week", nickname = "pushed")

fl_set <- add_scenario(scenario_set(flighted, name = "base"), moved)
compare_scenarios(fl_set, "flight")[, c("scenario", "channel", "flight_start",
                                        "spend_vs_base", "start_shift_days",
                                        "change")]
#>   scenario channel flight_start spend_vs_base start_shift_days    change
#> 1     base     OOH   2026-04-06             0                0      base
#> 2     base      TV   2026-04-06             0                0      base
#> 3     base  Search   2026-04-08             0                0      base
#> 4   pushed     OOH   2026-04-13             0                7     moved
#> 5   pushed      TV   2026-04-06             0                0 unchanged
#> 6   pushed  Search   2026-04-08             0                0 unchanged
```

At cell level that same change reads as money leaving one week and
arriving in another — true, but it leaves you to infer that a single buy
moved. Here it says so. This works within a **derivation**: buy
identities are minted per import, so they trace a plan and the scenarios
forked from it, and comparing two independently authored plans this way
warns rather than reporting every buy as added and dropped.

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

## What a line item buys

Spend is the common currency — the one quantity every channel shares —
so it stays mandatory. Alongside it a line item can record **what** it
buys, **how much**, and **at what price**. The three are bound by one
identity:

    planned_spend = planned_units * planned_rate / rate_per(unit_type)

`rate_per` is 1000 for impressions, because the trade quotes a CPM
rather than a price per impression, and 1 for everything else — a CPC
per click, a CPP per GRP.

So **supply any two and the third is computed**, whichever way you
actually have it. A budget and a negotiated rate:

``` r

social <- media_plan_from_df(
  data.frame(
    channel       = "Social",
    unit_type     = "impression",
    planned_spend = 140000,
    planned_rate  = 5          # a $5 CPM
  ),
  grain = "channel", name = "Social plan"
)

social@data$planned_units
#> [1] 2.8e+07
```

Or a delivery goal and a rate, which gives the budget instead:

``` r

media_plan_from_df(
  data.frame(channel = "Social", unit_type = "impression",
             planned_units = 28000000, planned_rate = 5),
  grain = "channel", name = "Goal-led"
)@data$planned_spend
#> [1] 140000
```

All three are stored, and the validator enforces the identity, so they
cannot drift apart.

### The rate is what survives an edit

This is the part worth knowing. When you cut a budget, the negotiated
rate does not improve — you buy fewer impressions:

``` r

cut <- build_scenario(social, edits = list(delta = -40000), name = "trimmed")

c(spend = cut@data$planned_spend,
  units = cut@data$planned_units,
  rate  = cut@data$planned_rate)
#> spend units  rate 
#> 1e+05 2e+07 5e+00
```

Units follow the money at the held rate, everywhere money moves: through
scaling and re-totalling, through a flight spreading across its weeks,
through
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md).
[`cost_per_unit()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md)
and
[`cpm()`](https://roeh-marketing.github.io/mediaplanr/reference/cost_per_unit.md)
derive from spend and units, so no third number can disagree with them.

[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
sums units only **within** one unit type, and reports none across a mix
— summing GRPs and clicks would produce a figure nobody should act on.
The spend always survives, because that is the point of a common
currency:

``` r

mixed <- media_plan_from_df(
  data.frame(bucket = "all", channel = c("Social", "Search"),
             unit_type = c("impression", "click"),
             planned_spend = c(140000, 95000), planned_rate = c(5, 0.80)),
  grain = c("bucket", "channel"), name = "Mixed"
)

roll_up(mixed, "bucket")@data
#>   bucket planned_spend unit_type planned_units planned_rate
#> 1    all        235000      <NA>            NA           NA
```

## Re-cutting the calendar

[`roll_up()`](https://roeh-marketing.github.io/mediaplanr/reference/roll_up.md)
aggregates over *dimensions*.
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
is its counterpart over *time*: it spreads each row’s spend across the
days it is actually in market, then gathers those days into days, weeks
or months.

``` r

ooh <- media_plan_from_flights(
  data.frame(
    channel       = "OOH",
    flight_start  = as.Date("2026-04-20"),
    flight_end    = as.Date("2026-05-10"),
    planned_spend = 210000
  ),
  grain = "channel", name = "A buy that crosses a month end"
)

calendarize(ooh, "week")
#>   channel       week planned_spend
#> 1     OOH 2026-04-20         70000
#> 2     OOH 2026-04-27         70000
#> 3     OOH 2026-05-04         70000
calendarize(ooh, "month")
#>   channel      month planned_spend
#> 1     OOH 2026-04-01        110000
#> 2     OOH 2026-05-01        100000
```

The month cut splits the week of 27 April, which straddles the boundary:
eleven days fall in April and ten in May. Doing that by hand is exactly
the tedious, error-prone part of finance-facing reporting.

The two verbs compose, in either order, because neither knows about the
other’s axis:

``` r

calendarize(roll_up(base, c("channel", "week")), "month")
#>   channel      month planned_spend
#> 1  Search 2026-04-01      67857.14
#> 2  Social 2026-04-01      82142.86
#> 3      TV 2026-04-01     250000.00
#> 4  Search 2026-05-01      46142.86
#> 5  Social 2026-05-01      55857.14
#> 6      TV 2026-05-01     170000.00
```

[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
returns a plain data frame rather than a plan. Aggregating over time can
merge two of a line item’s rows into one period, at which point the
flight that spanned them is no longer one row’s worth of anything — so
rather than guess, the flighting columns are dropped and the result is a
projection to chart or export. Pass it to
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
if you do want a plan at the new grain.

## Where to next

- [`vignette("plan_concepts")`](https://roeh-marketing.github.io/mediaplanr/articles/plan_concepts.md)
  — what a plan *is*, why flights are authored but weeks are held, why
  the rate survives an edit, and the boundaries that keep the package
  small.
- [`?build_scenario`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
  — the full edit-form and operation reference.
- [`?media_plan_from_flights`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_flights.md),
  [`?flights`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
  — authoring by buy rather than by week.
- [`?check_coverage`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  — pairing a plan with a decomp, and what `through` compares against.
- `Roadmap.md` — what is deliberately not built yet, and what is staying
  out.
