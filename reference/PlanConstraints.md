# A set of rules a plan must keep

The group rules a plan lives under – Streaming holds at least 40% of the
plan, the upfront totals exactly 360,000 however it is phased, Online
Video moves no more than 25% from the approved plan – written down once,
so the agent checking its own proposal and the optimizer read the same
definition of "allowed". Build one with
[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md);
check a plan against it with
[`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md).

## Usage

``` r
PlanConstraints(
  id = new_id("constraints"),
  name = "",
  rules = .rules_frame(list())
)
```

## Arguments

- id:

  Opaque id; a scenario's `rationale$constraints_id` refers to it.

- name:

  A name for the rule set.

- rules:

  A data frame, one row per rule: `type`, `value`, `target` (a list
  column of named lists), `during` (a list column; `NULL` for no window)
  and `note`. Build it with
  [`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md)
  rather than by hand.

## Value

A `PlanConstraints` S7 object.

## Details

Rules about **one row** – a commitment, a floor, a cap on a line item in
a month – are not here: they are spend bounds on the plan itself
([`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md)),
which every edit respects. A `PlanConstraints` holds the rules about
**groups** of rows, which a single edit cannot enforce row by row but a
plan can be checked against.

## See also

[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md),
[rules](https://roeh-marketing.github.io/mediaplanr/reference/rules.md),
[`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md).
