# A media plan at a configurable grain

`MediaPlan` is a typed wrapper around a flat plan table. `@data` is a
plain, directly accessible data frame of the grain columns plus a
`planned_spend` column; the class adds a validator, a synthetic identity
(`@id`), and lineage (`@parent_id`).

## Usage

``` r
MediaPlan(
  data = data.frame(),
  grain = character(0),
  time_col = character(0),
  time_basis = "week",
  tz = "",
  id = new_id("plan"),
  parent_id = character(0),
  name = "",
  nickname = "",
  advertiser = "",
  planner = "",
  status = "",
  objective = "",
  spend_basis = "",
  approved_on = as.Date(character(0)),
  subplans = list(),
  edits = list(),
  rationale = list()
)
```

## Arguments

- data:

  A data frame with the grain columns + `planned_spend`. One row per
  grain cell.

- grain:

  Character vector naming the columns that identify a row. It always
  ends with `@time_col`, which the constructors append for you — a
  caller names the line item columns and the time column separately.

- time_col:

  Name of the plan's time column, part of `@grain`. **Required**: every
  plan is planned against a calendar. Holds `Date` values (the first day
  of the period) or `POSIXct` moments.

- time_basis:

  What one value of `@time_col` stands for; one of
  [`time_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/time_basis_levels.md).
  `"day"`, `"week"` and `"month"` go with a `Date` column, `"instant"`
  with a `POSIXct` one.

- tz:

  The plan's timezone: the clock its times are stated on, as an Olson
  name (`"America/New_York"`, `"UTC"`). It is the plan's own property
  rather than a detail of whichever column happens to hold a moment, so
  a time given to an edit is read on the plan's clock wherever the code
  runs. `""` means unstated, and then the session's zone decides — which
  is the ambiguity worth removing. Only moments have a clock, so this
  has no effect on a plan keyed by day, week or month.

- id:

  Opaque synthetic id (identity/lineage only).

- parent_id:

  Id of the plan this one was derived from; empty for a root plan.

- name:

  Formal plan name. **Required** — every plan is named.

- nickname:

  Optional short working handle, e.g. `"aggressive TV"`. Used in
  preference to `@name` when labelling scenarios, so a set of
  in-progress scenarios reads well without renaming the formal plan.

- advertiser:

  Optional advertiser / client this plan belongs to.

- planner:

  Optional person responsible for the plan.

- status:

  Optional workflow state; one of
  [`status_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/status_levels.md),
  or `""` when unset.

- objective:

  Human-facing objective / notes.

- spend_basis:

  What `planned_spend` measures, as free text: commonly `"media_net"`
  (media cost to the agency), `"client_net"` (what the client pays, fees
  included) or `"gross"`. `""` when undeclared. It declares the basis
  and converts nothing. Plans combine – in a
  [ScenarioSet](https://roeh-marketing.github.io/mediaplanr/reference/ScenarioSet.md),
  or as a subplan – only when their bases match exactly.

- approved_on:

  The date the plan was approved: a single `Date`, or empty when unset.
  Only an approved plan may carry one, and even then it is optional – it
  is never defaulted to today. A plan's *revision* is not stored: it is
  its place among the approved plans in its lineage; see
  [`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md).

- subplans:

  Named list of `MediaPlan`s, one per parent line item they back.
  Populate through
  [`attach_subplan()`](https://roeh-marketing.github.io/mediaplanr/reference/attach_subplan.md),
  not by hand: attaching recomputes the parent's rows for that cell and
  the validator refuses a subplan whose rollup the parent's rows do not
  match.

- edits:

  The edits that derived this plan from `parent_id`, as
  [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
  recorded them; empty for a root. Replaying them on the parent
  reproduces `data` exactly. See
  [`edit_log()`](https://roeh-marketing.github.io/mediaplanr/reference/edit_log.md).

- rationale:

  Why this plan was derived: a named list with any of `author`
  (`"human"`, `"agent"` or `"optimizer"`), `goal`, `constraints_id`,
  `forecast` (a named list of numbers the caller supplies) and `notes`.
  Empty when unstated. Set through
  [`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
  or
  [`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md).

## Value

A `MediaPlan` S7 object.

## Details

A plan holds **planned values only** — `planned_spend` is what was
intended for a row, including for weeks that have already passed. It is
never what actually happened; actualised spend and attributed KPI live
in the decomp.

Every plan is keyed by time. `@time_col` is required and `@time_basis`
says what one of its values covers — a day, a week, a month, or a moment
for a buy placed at a specific time. Those two are what a row's
in-market period is derived from, so nothing in the package has to
assume a week. See
[`time_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/time_basis_levels.md).

A plan on its own is therefore **blind to past and future**.
"Historical", "future", under-delivery and over-delivery are not
properties of a plan: they only exist for a *pairing* of a plan with a
decomp that reports actuals through a given date. That is why no
through-date is stored here, and why editing a row for a past week is a
perfectly ordinary thing to do — you are revising what was planned, and
the plan cannot know that week has passed. See
[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
for the one pairing operation the package provides.

Any other columns on the supplied data frame are carried through
untouched.

Construct one with
[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md)
rather than calling the constructor directly.

## Derived properties

`@flight_start`, `@flight_end` and `@flight_days` are computed from
`@data` on every read and cannot be assigned. They describe the plan's
own extent — the dates it has line items for — and so are true of the
plan alone. See
[`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md)
for why that is a different thing from the decomp through-date
[`check_coverage()`](https://roeh-marketing.github.io/mediaplanr/reference/check_coverage.md)
takes, and why only one of the two can live on a plan.
