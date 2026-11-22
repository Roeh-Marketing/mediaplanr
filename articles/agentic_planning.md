# Agentic planning

``` r

library(mediaplanr)
```

An agentic media planner is a language model that edits a media plan: it
reads the plan, proposes changes, has them scored, checks them, and
hands them to a person to approve. `mediaplanr` is the part of that
system that holds the plan and decides what is allowed. This vignette
runs the loop once, on the agency plan from
[`vignette("getting_started")`](https://roeh-marketing.github.io/mediaplanr/articles/getting_started.md),
with real calls.

Three owners, one job each:

|  | Owns | In this loop |
|----|----|----|
| `mediaplanr` | plan state, legal actions, constraints, checks, history | describe, validate, derive, check, record |
| `mrmopt` | scoring and optimization | score |
| the app | the agent loop and the human approval gate | propose, approve |

The loop:

    describe  ->  propose ops  ->  validate & derive  ->  score  ->  check
              ->  record why   ->  a person approves

## The plan, and what the agent is told

The approved plan, the response models fitted to it, and the rules it
lives under:

``` r

ext <- function(file) system.file("extdata", file, package = "mediaplanr")

plan <- media_plan_from_df(
  read.csv(ext("agency_plan.csv")),
  grain       = c("channel", "partner", "campaign", "tactic"),
  time        = "month",
  name        = "National digital, Q4 2026 - Q1 2027",
  nickname    = "Rev 1",
  spend_basis = "media_net",
  status      = "approved",
  approved_on = "2026-09-15"
)
models <- read.csv(ext("agency_models.csv"))
rules  <- plan_constraints(read.csv(ext("agency_constraints.csv")),
                           name = "Agency guardrails")
```

### What the plan looks like

The agent does not read 54 rows – or 50,000. It reads
[`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md):
a summary capped at `top_n` values per list, so it is the same size
however big the plan is, and every number in it reconciles to the plan’s
rows.

``` r

description <- describe_plan(plan, top_n = 3, models = models,
                             constraints = rules, reference = plan)
nchar(jsonlite::toJSON(description, auto_unbox = TRUE))
#> [1] 2474
```

The sections that matter most before an edit: what cannot move, which
rules are tight, and what the models cannot score.

``` r

jsonlite::toJSON(description[c("commitments", "constraints", "models")],
                 auto_unbox = TRUE, pretty = TRUE)
#> {
#>   "commitments": {
#>     "committed": 360000,
#>     "floor_locked": 90000,
#>     "flexible": 810600,
#>     "headroom": 870600,
#>     "n_bounded_line_items": 3
#>   },
#>   "constraints": {
#>     "id": "constraints_20261122212521_cb283f",
#>     "n_rules": 5,
#>     "n_ok": 5,
#>     "violated": [],
#>     "binding": [
#>       {
#>         "rule": "fixed_total 360000 on partner Stream A",
#>         "actual": 360000,
#>         "limit": 360000,
#>         "slack": 0
#>       }
#>     ]
#>   },
#>   "models": {
#>     "modeled_share": 0.9546,
#>     "unmodeled_spend": 60000,
#>     "n_models_used": 6,
#>     "unmodeled": [
#>       {
#>         "line_item": "Streaming | Stream B | Promo | Regional",
#>         "planned_spend": 60000
#>       }
#>     ],
#>     "n_more_unmodeled": 0
#>   }
#> }
```

`headroom` is the spend an edit could take out at all. The upfront’s
`fixed_total` is `binding`: it holds with no slack, so nothing may move
it.

### What the agent may send

The agent edits only through operations, and
[`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
is the contract: a JSON Schema for the list of ops, narrowed to this
plan. Given as the type of a tool’s argument, it stops a malformed op
before it reaches R. A `target` may name only the plan’s columns and
values:

``` r

schema <- plan_ops_schema(plan)
transfer <- Filter(function(op) op$title == "transfer", schema$items$oneOf)[[1]]
unlist(transfer$properties$to$properties$partner$anyOf[[1]]$enum)
#> [1] "DSP A"    "DSP B"    "Stream A" "Stream B" "Video A"  "Video B"
```

## The agent proposes

Asked to lift prospecting reach in Q1 without touching commitments, the
agent replies with two transfers, as JSON:

``` r

reply <- r"([
  {"transfer": 30000,
   "from": {"channel": "Streaming"},
   "to":   {"partner": "DSP A", "tactic": "Prospecting"},
   "during": {"from": "2027-01-01", "to": "2027-03-31"}},
  {"transfer": 20000,
   "from": {"partner": "DSP B"},
   "to":   {"partner": "Video A", "tactic": "Prospecting"},
   "during": {"from": "2027-01-01", "to": "2027-03-31"}}
])"
ops <- jsonlite::fromJSON(reply, simplifyVector = FALSE)
```

(`simplifyVector = FALSE` matters: simplifying would turn the list of
ops into a data frame, which
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
reads as an allocation.)

### Validate and derive

[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
checks every op and derives a new scenario. The approved plan is never
touched. This proposal is refused:

``` r

build_scenario(plan, edits = ops, name = "Q1 prospecting push")
#> Error:
#> ! edit op 2: `from`: `transfer` of 20,000 cannot take 20,000 out of these rows: their floors leave 17,500 to give. Floors: Programmatic | DSP B | Promo | Prospecting | 2027-01-01 (floor); Programmatic | DSP B | Promo | Prospecting | 2027-02-01 (floor); Programmatic | DSP B | Promo | Prospecting | 2027-03-01 (floor). Ask for less, or lower the floors first with `rebound`.
```

DSP B has a floor of 15,000 a month; in Q1 it can give 17,500, not
20,000. The refusal is specific enough to act on, and that is the point:
the agent did not have to be told about the floor. It is a fact in the
plan, and every edit respects it. The agent asks for what can be given,
and records why:

``` r

ops[[2]]$transfer <- 15000

proposal <- build_scenario(
  plan,
  edits     = ops,
  name      = "National digital, Q4 2026 - Q1 2027",
  nickname  = "Q1 prospecting push",
  objective = "More prospecting reach in Q1",
  rationale = list(author = "agent",
                   goal = "lift Q1 prospecting reach without touching commitments",
                   constraints_id = rules@id)
)
```

The 30,000 out of Streaming came from Stream B alone: Stream A’s upfront
is committed, so the transfer routed around it.

## Score

Scoring is `mrmopt`’s job. `mediaplanr` hands it the spend each response
model scores, period by period – with unmodeled spend kept, so nothing
is silently left out of the total:

``` r

weekly <- spend_by_model(proposal, models, basis = "week")
head(weekly, 3)
#>   model_id       week planned_spend  unit_type planned_units planned_rate
#> 1    dsp_a 2026-09-28       9290.32 impression       1290322     7.200001
#> 2    dsp_a 2026-10-05      16258.07 impression       2258065     7.200000
#> 3    dsp_a 2026-10-12      16258.07 impression       2258065     7.200000
```

``` r

# `fits`: models from mrmopt::fit_response(), named by model_id
scored <- split(weekly, weekly$model_id)
kpi <- vapply(names(scored), function(id) {
  f <- mrmopt::mrm_response_function(fits[[id]])
  sum(f(scored[[id]]$planned_spend))
}, numeric(1))
```

## Check

The proposal respected every row’s bounds – it could not have been built
otherwise. The group rules are checked against the approved plan:

``` r

check_constraints(proposal, rules, reference = plan)[
  , c("type", "target", "actual", "slack", "ok")]
#>             type               target    actual     slack   ok
#> 1      min_share    channel Streaming 4.316e-01 3.160e-02 TRUE
#> 2    fixed_total     partner Stream A 3.600e+05 0.000e+00 TRUE
#> 3      max_spend channel Programmatic 2.975e+05 2.250e+04 TRUE
#> 4      max_share channel Online Video 1.708e-01 7.920e-02 TRUE
#> 5 max_change_pct channel Online Video 7.120e-02 1.788e-01 TRUE
#> 6     row_bounds          (every row) 0.000e+00 0.000e+00 TRUE
```

Every rule holds. The signed budget is another matter: moving money
between channels moves it between their Q1 envelopes too.

``` r

q1_budget <- data.frame(
  channel = c("Streaming", "Programmatic", "Online Video"),
  from = "2027-01-01", to = "2027-03-31",
  amount = c(250000, 212500, 87750)
)
check_budget(proposal, q1_budget)
#> Warning: 3 budget row(s) off by more than 0.5: channel Streaming,
#> 2027-01-01..2027-03-31: planned 220,000 against 250,000 (-30,000); channel
#> Programmatic, 2027-01-01..2027-03-31: planned 227,500 against 212,500
#> (+15,000); channel Online Video, 2027-01-01..2027-03-31: planned 102,750
#> against 87,750 (+15,000).
#>        channel       from         to amount planned variance variance_pct
#> 1    Streaming 2027-01-01 2027-03-31 250000  220000   -30000  -0.12000000
#> 2 Programmatic 2027-01-01 2027-03-31 212500  227500    15000   0.07058824
#> 3 Online Video 2027-01-01 2027-03-31  87750  102750    15000   0.17094017
#>   in_plan within
#> 1    TRUE  FALSE
#> 2    TRUE  FALSE
#> 3    TRUE  FALSE
```

Both checks warn rather than refuse. They are for the person who
approves the plan: the agent’s proposal is legal, and these say what
signing it would mean.

## Record and hand over

The proposal goes to review with what scoring returned (illustrative
figures here) added to its rationale. The package never computes a
forecast; it keeps the one it was given.

``` r

proposal <- revise(
  proposal,
  status    = "to review",
  rationale = c(proposal@rationale,
                list(forecast = list(conversions = 18450, roas = 2.4)))
)

set <- add_scenario(scenario_set(plan), proposal)
edit_log(set)[, c("scenario", "author", "op", "target", "to", "amount", "window")]
#>              scenario author       op            target
#> 1 Q1 prospecting push  agent transfer channel Streaming
#> 2 Q1 prospecting push  agent transfer     partner DSP B
#>                                       to amount                 window
#> 1   partner | tactic DSP A | Prospecting  30000 2027-01-01..2027-03-31
#> 2 partner | tactic Video A | Prospecting  15000 2027-01-01..2027-03-31
compare_scenarios(set, against = "current_approved")[
  , c("scenario", "total_planned_spend", "spend_vs_current_approved")]
#>              scenario total_planned_spend spend_vs_current_approved
#> 1               Rev 1             1320600                         0
#> 2 Q1 prospecting push             1320600                         0
```

[`edit_log()`](https://roeh-marketing.github.io/mediaplanr/reference/edit_log.md)
is exactly what was applied: the scenario was derived by replaying that
record, so it cannot have drifted from it. Approval is the person’s:
`revise(status = "approved", approved_on = )`, after which
[`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md)
names the new plan and the next loop starts from it.

## One master plan, several planners

So far one agent edited one plan. In practice a client keeps **one
master plan per fiscal year**, and several planners – people or agents –
work on it at once, each over their own part of the organization. That
needs no new object, only four ideas the package already has:

- A **section** of the organization is a target: the named list of grain
  columns and values an op already uses.
- A planner’s **scope** is a list of targets: the sections they own.
- A **draft** is a scenario under the revision it was written against.
  It is approved by replaying its ops on the *current* revision, so the
  approved revisions stay one chain.
- Every level of the organization is a grain column, because a target
  may only name grain columns.

### Every level is a column

The organization here splits Brand from Performance above the channels.
The plan has no such column, so it gets one, read off `channel`:

``` r

master <- regrain(plan, "funnel", from = "channel",
                  groups = list(Brand = c("Streaming", "Online Video"),
                                Performance = "Programmatic"))
master <- revise(master, nickname = "Rev 1")
master@grain
#> [1] "funnel"   "channel"  "partner"  "campaign" "tactic"   "month"
```

It is the same plan – same id, same approval – keyed one level deeper.
The sections are the leaves of the organization tree, and
[`assign_sections()`](https://roeh-marketing.github.io/mediaplanr/reference/assign_sections.md)
says where each line item falls; a line item in two leaves, or in none,
would be listed under the table, not refused:

``` r

sections <- list(
  Streaming    = list(funnel = "Brand", channel = "Streaming"),
  Video        = list(funnel = "Brand", channel = "Online Video"),
  Programmatic = list(funnel = "Performance", channel = "Programmatic")
)
assign_sections(master, sections)
#>                                                  line_item      section
#> 1     Brand | Online Video | Video A | Brand | Added Value        Video
#> 2     Brand | Online Video | Video A | Brand | Prospecting        Video
#> 3        Brand | Online Video | Video B | Promo | Regional        Video
#> 4 Performance | Programmatic | DSP A | Brand | Prospecting Programmatic
#> 5 Performance | Programmatic | DSP A | Promo | Retargeting Programmatic
#> 6 Performance | Programmatic | DSP B | Promo | Prospecting Programmatic
#> 7           Brand | Streaming | Stream A | Brand | Upfront    Streaming
#> 8       Brand | Streaming | Stream B | Brand | Prospecting    Streaming
#> 9          Brand | Streaming | Stream B | Promo | Regional    Streaming
#>   n_matches
#> 1         1
#> 2         1
#> 3         1
#> 4         1
#> 5         1
#> 6         1
#> 7         1
#> 8         1
#> 9         1
#> Every line item is in exactly one section.
```

### A draft in each scope

The Brand planner owns two sections, and the Performance planner owns
one:

``` r

brand_scope <- sections[c("Streaming", "Video")]
perf_scope  <- sections["Programmatic"]
```

The app asks
[`ops_within()`](https://roeh-marketing.github.io/mediaplanr/reference/ops_within.md)
before it builds anything. It resolves each op’s rows exactly as
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
would, so the answer cannot disagree with the edit. The Brand planner’s
move stays inside their scope:

``` r

q1 <- list(from = "2027-01-01", to = "2027-03-31")
brand_ops <- list(op_transfer(10000, from = list(partner = "Stream B"),
                              to = list(partner = "Video A",
                                        tactic = "Prospecting"),
                              during = q1))
ops_within(master, brand_ops, brand_scope)
#> [1] op         side       line_items
#> <0 rows> (or 0-length row.names)
brand_draft <- build_scenario(master, brand_ops, name = "Brand draft")
```

The Performance planner’s second op takes money out of Streaming, which
they do not own:

``` r

perf_ops <- list(
  op_transfer(5000, from = list(partner = "DSP B"),
              to = list(partner = "DSP A", tactic = "Prospecting"), during = q1),
  op_transfer(5000, from = list(partner = "Stream B"),
              to = list(partner = "DSP A", tactic = "Prospecting"), during = q1)
)
outside <- ops_within(master, perf_ops, perf_scope)
outside
#>   op side
#> 1  2 from
#>                                                                                            line_items
#> 1 Brand | Streaming | Stream B | Brand | Prospecting, Brand | Streaming | Stream B | Promo | Regional
```

The app refuses that op, and the draft is built from the rest:

``` r

perf_draft <- build_scenario(master, perf_ops[-outside$op],
                             name = "Performance draft")
set <- add_scenario(add_scenario(scenario_set(master), brand_draft),
                    perf_draft)
current_approved(set)
#> [1] "Rev 1"
```

### Approving a draft is replaying it

Both drafts were written under Rev 1. Approving one means replaying its
ops on whatever revision is current, which is Rev 1 for the first
approval:

``` r

approve <- function(set, draft, nickname, on) {
  current <- set@scenarios[[current_approved(set)]]
  rev <- build_scenario(current, draft@edits$ops, name = master@name,
                        nickname = nickname)
  add_scenario(set, revise(rev, status = "approved", approved_on = on))
}
set <- approve(set, brand_draft, "Rev 2", "2026-10-01")
current_approved(set)
#> [1] "Rev 2"
```

The Performance draft was written under Rev 1 too, but Rev 2 is current
now.
[`rebase_check()`](https://roeh-marketing.github.io/mediaplanr/reference/rebase_check.md)
says whether replaying it on Rev 2 does to its rows what it did on
Rev 1. Rev 2 changed only Brand’s rows, so it does:

``` r

rebase_check(master, set@scenarios[["Rev 2"]], perf_draft@edits)
#> [1] op            side          row           issue         columns      
#> [6] base_spend    current_spend
#> <0 rows> (or 0-length row.names)
set <- approve(set, perf_draft, "Rev 3", "2026-10-02")
current_approved(set)
#> [1] "Rev 3"
```

Rev 3 holds both planners’ changes, and neither had to wait for the
other.

### When a draft goes stale

A third draft is written under Rev 3. Before it is approved, a
reallocation from the top moves Q1 money from Brand to Performance and
is approved as Rev 4:

``` r

rev3 <- set@scenarios[["Rev 3"]]
brand_draft_2 <- build_scenario(rev3, op_transfer(
  4000, from = list(partner = "Stream B", campaign = "Promo"),
  to = list(partner = "Stream B", campaign = "Brand"), during = q1),
  name = "Brand draft 2")
top_down <- build_scenario(rev3, op_transfer(
  20000, from = list(funnel = "Brand"), to = list(funnel = "Performance"),
  during = q1), name = "Top-down reallocation")
set <- approve(add_scenario(set, brand_draft_2), top_down, "Rev 4",
               "2026-10-15")

rebase_check(rev3, set@scenarios[["Rev 4"]], brand_draft_2@edits)[
  , c("op", "side", "row", "issue", "base_spend", "current_spend")]
#>   op side                                                             row
#> 1  1 from    Brand | Streaming | Stream B | Promo | Regional | 2027-01-01
#> 2  1 from    Brand | Streaming | Stream B | Promo | Regional | 2027-02-01
#> 3  1 from    Brand | Streaming | Stream B | Promo | Regional | 2027-03-01
#> 4  1   to Brand | Streaming | Stream B | Brand | Prospecting | 2027-01-01
#> 5  1   to Brand | Streaming | Stream B | Brand | Prospecting | 2027-02-01
#> 6  1   to Brand | Streaming | Stream B | Brand | Prospecting | 2027-03-01
#>     issue base_spend current_spend
#> 1 changed       6300      5628.895
#> 2 changed       7200      6433.023
#> 3 changed       9000      8041.278
#> 4 changed      18900     16886.684
#> 5 changed      21600     19299.068
#> 6 changed      27000     24123.835
```

The rows the draft moves money between are not what they were when it
was written, so replaying it would not do what its planner saw. The app
sends the draft back to be rebuilt on Rev 4. It does not replay it
anyway.

Through all of this the approvals form one chain, and there is one
current plan:

``` r

lineage(set)[, c("scenario", "parent", "status", "revision", "current")]
#>            scenario parent         status revision current
#> 1             Rev 1   <NA>       approved        1   FALSE
#> 2       Brand draft  Rev 1 in development       NA   FALSE
#> 3 Performance draft  Rev 1 in development       NA   FALSE
#> 4             Rev 2  Rev 1       approved        2   FALSE
#> 5             Rev 3  Rev 2       approved        3   FALSE
#> 6     Brand draft 2  Rev 3 in development       NA   FALSE
#> 7             Rev 4  Rev 3       approved        4    TRUE
```

## What the agent may and may not do

**May:** read the plan through
[`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md);
propose any operation in
[`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md);
derive as many scenarios as it likes – each is a new object, and the
plan it came from is never changed; check its own proposals with
[`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md)
and
[`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md).

**May not:**

- **Move money that cannot move.** Spend bounds are in the plan, and
  every edit respects them: an edit across a group routes around a
  bound, and one that names a row’s value outright is refused at it.
- **Change a commitment quietly.** Bounds change only through the
  `rebound` op, which shows in
  [`edit_log()`](https://roeh-marketing.github.io/mediaplanr/reference/edit_log.md)
  like any other edit.
- **Send something malformed or vague.** A typo in a target is an error
  naming the alternatives, never a silent no-op; ops are checked whether
  they came from JSON, a constructor or by hand.
- **Reach outside its scope.** Which rows an op touches is decided by
  the package’s matcher, so
  [`ops_within()`](https://roeh-marketing.github.io/mediaplanr/reference/ops_within.md)
  gives the app the same answer the edit would. The app enforces the
  scope.
- **Approve its own work.** The package records approval; the app
  decides who may give it.

## Why commitments live in the plan

An agent could be told about the upfront commitment in its prompt.
Prompts are read, mostly, and followed, usually. A commitment stored as
`min_spend` and `max_spend` on the plan’s rows is not read by anyone:
every edit path – an agent’s op, a planner’s allocation, an optimizer’s
output – passes through the same check, so the commitment holds whoever
is editing and however carefully they were told. The rules about groups
of rows are the same idea one level up: written once in a
`PlanConstraints`, checked the same way by the agent and, next, by the
optimizer.
