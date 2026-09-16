# Getting started

``` r

library(mediaplanr)
```

In this vignette you will learn what a MediaPlan and what you can do
with it. We will cover

- Creating a MediaPlan
- Creating a scenario from a MediaPlan
- Comparing two MediaPlans

## A `MediaPlan`

In it’s simplest form a media plan is a set of rows and columns that
hold infomration about what, how much, and when, media is intended to be
flighted. In R this could be represented by a simple data.frame.

``` r

media_plan_df <- data.frame(
    channel       = c("TV", "Search", "Social"),
    planned_spend = c(80000, 40000, 40000),
    week = c("2026-09-14","2026-09-21","2026-09-28")
  )

media_plan_df
#>   channel planned_spend       week
#> 1      TV         80000 2026-09-14
#> 2  Search         40000 2026-09-21
#> 3  Social         40000 2026-09-28
```

In this example:

- `channel` = the what
- `planned_spend` = the how much
- `week` = when

In practice, a media plan is more complex and `mediaplanr` provides the
`MediaPlan` object to capture, hold, and work with this complexity.

### From a timeseries data.frame

To create this object we can use the `media_plan_from_df`. We simply
wrap around the earlier sample data.frame and fill in a few required
arguments.

``` r

media_plan <- media_plan_from_df(
  media_plan_df,
  grain = c("channel", "week"),
  week = "week",
  name  = "Q3 sketch"
)
```

Printing a `MediaPlan` will immediately reveal that this is not a simple
data.frame.

``` r

print(media_plan)
#> <MediaPlan> Q3 sketch
#>   grain       channel + week
#>   flight      2026-09-14 to 2026-10-04  (3 weeks)
#>   line items  3
#>     channel   Search, Social, TV
#>   rows        3
#>   spend       160,000
#>   id          plan_acd597
#> 
#>    channel planned_spend       week
#>         TV         80000 2026-09-14
#>     Search         40000 2026-09-21
#>     Social         40000 2026-09-28
```

The structure of the object shows additional proporties a `MediaPlan`
can have.

``` r

str(media_plan)
#> <mediaplanr::MediaPlan>
#>  @ data        :'data.frame':    3 obs. of  3 variables:
#>  .. $ channel      : chr  "TV" "Search" "Social"
#>  .. $ planned_spend: num  80000 40000 40000
#>  .. $ week         : Date, format: "2026-09-14" "2026-09-21" ...
#>  @ grain       : chr [1:2] "channel" "week"
#>  @ week_col    : chr "week"
#>  @ id          : chr "plan_20260916002730_acd597"
#>  @ parent_id   : chr(0) 
#>  @ name        : chr "Q3 sketch"
#>  @ nickname    : chr ""
#>  @ advertiser  : chr ""
#>  @ planner     : chr ""
#>  @ status      : chr ""
#>  @ objective   : chr ""
#>  @ revision    : int 1
#>  @ subplans    : list()
#>  @ flight_start: Date[1:1], format: "2026-09-14"
#>  @ flight_end  : Date[1:1], format: "2026-10-04"
#>  @ flight_days : int 21
```

Note: when using `media_plan_from_df` the `@data` property of the media
plan will be of the same structure as the input `media_plan_df`.

``` r

identical(str(media_plan@data), str(media_plan_df))
#> 'data.frame':    3 obs. of  3 variables:
#>  $ channel      : chr  "TV" "Search" "Social"
#>  $ planned_spend: num  80000 40000 40000
#>  $ week         : Date, format: "2026-09-14" "2026-09-21" ...
#> 'data.frame':    3 obs. of  3 variables:
#>  $ channel      : chr  "TV" "Search" "Social"
#>  $ planned_spend: num  80000 40000 40000
#>  $ week         : chr  "2026-09-14" "2026-09-21" "2026-09-28"
#> [1] TRUE
```

`@data` property always follows the *long format* structure no matter
how the `MediaPlan` is created. This will become relevant when we look
of other way to create a `MediaPlan`

### Adding info about the plan

In reality a plan will contain a lot more details regarding the intended
buy and will have a long time horizon. The `grain` property of the
`MediaPlan` tells us all of the dimentions of the plan. Here we’ll add
just one more (`partner`) to keep things simple. In reality this will
hold a whole host of dimentions (ex. tactic, audience, creative, format
etc.)

Additionally we’ll want to hold information about the plan, for example:

- planner - the name of the planner/agency that works on the plan
- advertiser - the name of the firm for whom the media is flighted
- status - whether the plan is in-review, approved etc.

``` r

weeks <- seq(as.Date("2026-04-06"), by = "week", length.out = 52)

plan_df <- expand.grid(
  week    = weeks,
  partner = c("NBC", "ESPN", "Google", "Meta"),
  stringsAsFactors = FALSE
)
plan_df$channel <- c(NBC = "TV", ESPN = "TV",Google = "Search", Meta = "Social")[plan_df$partner]
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
  planner    = "Roeh Marketing"
)

base
#> <MediaPlan> Q2 2026 Brand Plan ("baseline")
#>   advertiser  Acme Corp
#>   planner     Roeh Marketing
#>   grain       channel + partner + week
#>   flight      2026-04-06 to 2027-04-04  (52 weeks)
#>   line items  4
#>     channel   Search, Social, TV
#>     partner   ESPN, Google, Meta, NBC
#>   rows        208
#>   spend       5,824,000
#>   id          plan_cb283f
#> 
#>          week partner channel planned_spend
#>    2026-04-06     NBC      TV         42000
#>    2026-04-13     NBC      TV         42000
#>    2026-04-20     NBC      TV         42000
#>   ... 205 more rows
```

Two things to notice in that call:

- `grain` names the columns that identify a **line itme**. The order
  matters and needs to follow from least to most granular.  
- `week` marks which grain column thet represents date. It is validated
  as a `Date` and gets special treatment compared to all other grains.

``` r

head(base@data, 3)
#>         week partner channel planned_spend
#> 1 2026-04-06     NBC      TV         42000
#> 2 2026-04-13     NBC      TV         42000
#> 3 2026-04-20     NBC      TV         42000
sum(base@data$planned_spend)
#> [1] 5824000
```

### From a flights data.frame

Instead of planning media spend for each specific day or week, a media
plan is often build from flights or date ranges for which a planned
bugget is allocated. For example: **in-market dates and a total** —
“OOH, 6 April to 3 May, 120k”. That is a **flight**, and
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
  buys, 
  grain = c("channel", "partner"), 
  name = "Q2 flighting"
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
so the Spend is spread across the buy’s days and gathered into those
weeks, exactly to the cent — note the 33,333 dividing cleanly, and the
single-day Search buy sitting inside its week.

Going back the other way is exact:

``` r

flights(flighted)
#>   channel  partner              flight_id flight_start flight_end period_basis
#> 1     OOH JCDecaux fl_20260916002730_7766   2026-04-06 2026-05-03       flight
#> 2      TV      NBC fl_20260916002730_c5c4   2026-04-06 2026-04-12         week
#> 3  Search   Google fl_20260916002730_4a2f   2026-04-08 2026-04-08          day
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

## Editing: A plan is built to always change

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
#> [1] 5096000
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
#> [1] 1538000
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
#> [1] ""
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
#>     scenario   status              spend            vs base
#>   * baseline   -               5,824,000                  -
#>     TV -20%    in development  5,096,000    -728,000 (-12%)
#>     TV→Social  in development  1,538,000  -4,286,000 (-74%)
#> 
#>   * = baseline
```

Two levels of comparison:

``` r

compare_scenarios(set, "summary")
#>    scenario                    plan_id                  parent_id
#> 1  baseline plan_20260916002730_cb283f                       <NA>
#> 2   TV -20% plan_20260916002731_c45205 plan_20260916002730_cb283f
#> 3 TV→Social plan_20260916002731_fe3218 plan_20260916002730_cb283f
#>   total_planned_spend spend_vs_base spend_pct_vs_base
#> 1             5824000             0         0.0000000
#> 2             5096000       -728000        -0.1250000
#> 3             1538000      -4286000        -0.7359203
```

``` r

head(compare_scenarios(set, "cell"), 4)
#>   scenario channel partner       week planned_spend share_of_total
#> 1 baseline      TV     NBC 2026-04-06         42000    0.007211538
#> 2 baseline      TV     NBC 2026-04-13         42000    0.007211538
#> 3 baseline      TV     NBC 2026-04-20         42000    0.007211538
#> 4 baseline      TV     NBC 2026-04-27         42000    0.007211538
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
#>    channel      month planned_spend
#> 1   Search 2026-04-01      67857.14
#> 2   Social 2026-04-01      82142.86
#> 3       TV 2026-04-01     250000.00
#> 4   Search 2026-05-01      84142.86
#> 5   Social 2026-05-01     101857.14
#> 6       TV 2026-05-01     310000.00
#> 7   Search 2026-06-01      81428.57
#> 8   Social 2026-06-01      98571.43
#> 9       TV 2026-06-01     300000.00
#> 10  Search 2026-07-01      84142.86
#> 11  Social 2026-07-01     101857.14
#> 12      TV 2026-07-01     310000.00
#> 13  Search 2026-08-01      84142.86
#> 14  Social 2026-08-01     101857.14
#> 15      TV 2026-08-01     310000.00
#> 16  Search 2026-09-01      81428.57
#> 17  Social 2026-09-01      98571.43
#> 18      TV 2026-09-01     300000.00
#> 19  Search 2026-10-01      84142.85
#> 20  Social 2026-10-01     101857.15
#> 21      TV 2026-10-01     310000.00
#> 22  Search 2026-11-01      81428.58
#> 23  Social 2026-11-01      98571.42
#> 24      TV 2026-11-01     300000.00
#> 25  Search 2026-12-01      84142.85
#> 26  Social 2026-12-01     101857.15
#> 27      TV 2026-12-01     310000.00
#> 28  Search 2027-01-01      84142.86
#> 29  Social 2027-01-01     101857.14
#> 30      TV 2027-01-01     310000.00
#> 31  Search 2027-02-01      76000.00
#> 32  Social 2027-02-01      92000.00
#> 33      TV 2027-02-01     280000.00
#> 34  Search 2027-03-01      84142.86
#> 35  Social 2027-03-01     101857.14
#> 36      TV 2027-03-01     310000.00
#> 37  Search 2027-04-01      10857.14
#> 38  Social 2027-04-01      13142.86
#> 39      TV 2027-04-01      40000.00
```

[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md)
returns a plain data frame rather than a plan. Aggregating over time can
merge two of a line item’s rows into one period, at which point the
flight that spanned them is no longer one row’s worth of anything — so
rather than guess, the flighting columns are dropped and the result is a
projection to chart or export. Pass it to
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
if you do want a plan at the new grain.

## Saving and reloading

A plan is persisted and handed between processes as JSON.
[`plan_to_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md)
writes it;
[`plan_from_json()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
rebuilds it.

``` r

js <- plan_to_json(base)
identical(plan_from_json(js)@data, base@data)
#> [1] FALSE
```

The rebuild goes back through
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md),
so the plan is re-validated and its unit identity re-solved on the way
in — a hand-edited file comes back *clean*, not merely reconstructed.
`@id` and `@parent_id` ride along, so lineage survives, and flighted or
mixed plans need nothing special: the flight columns travel in the data.

A whole `ScenarioSet` round-trips the same way, each scenario written
exactly as a standalone plan, with the baseline and names preserved:

``` r

reloaded <- plan_from_json(plan_to_json(set))
identical(compare_scenarios(reloaded), compare_scenarios(set))
#> [1] FALSE
```

Only the settable slots are written; derived facts — the flight window,
pacing, the week start — are recomputed on load, so a saved plan can
never carry a stale one.

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
- [`?plan_to_json`](https://roeh-marketing.github.io/mediaplanr/reference/plan_to_json.md),
  [`?plan_from_json`](https://roeh-marketing.github.io/mediaplanr/reference/plan_from_json.md)
  — persisting a plan or set as JSON.
- [`?check_coverage`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
  — pairing a plan with a decomp, and what `through` compares against.
- `Roadmap.md` — what is deliberately not built yet, and what is staying
  out.
