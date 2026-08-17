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
  week_col = character(0),
  id = new_id("plan"),
  parent_id = character(0),
  name = "",
  nickname = "",
  advertiser = "",
  planner = "",
  status = "",
  objective = ""
)
```

## Arguments

- data:

  A data frame with the grain columns + `planned_spend`. One row per
  grain cell.

- grain:

  Character vector naming the columns that identify a row. When the plan
  is weekly this includes the week column.

- week_col:

  Optional name of the week column within `@grain`. Must hold `Date`
  values (the week start). Empty means the plan has no time dimension.

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

## Value

A `MediaPlan` S7 object.

## Details

A plan holds **planned values only** — `planned_spend` is what was
intended for a row, including for weeks that have already passed. It is
never what actually happened; actualised spend and attributed KPI live
in the decomp.

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
