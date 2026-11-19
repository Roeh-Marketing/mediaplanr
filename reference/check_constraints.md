# Check a plan against its rules

Measures each rule of a
[PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md)
on a plan and reports how it stands: the `actual` measure, the rule's
`limit`, the `slack` between them, and whether the rule is `ok`. Rules
are measured day by day, through
[`calendarize()`](https://roeh-marketing.github.io/mediaplanr/reference/calendarize.md),
so a rule's window may cut a week or a month anywhere.

## Usage

``` r
check_constraints(plan, constraints, reference = NULL)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- constraints:

  A
  [PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md).

- reference:

  The plan change rules are measured against – normally the plan's
  parent, or the current approved plan
  ([`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md)).
  Required when `constraints` has a `max_change_*` rule.

## Value

A data frame, one row per rule:

- `rule`:

  Its position in `constraints`; `NA` for `row_bounds`.

- `type`, `target`, `window`, `note`:

  The rule, in words.

- `limit`:

  The rule's value.

- `actual`:

  What the plan measures: the target's spend, its share of the plan, or
  how far it moved from the reference.

- `slack`:

  How far inside its limit the rule is; negative is how far outside.
  Always 0 or less for `fixed_total`.

- `ok`:

  Whether the rule holds.

## Details

Like
[`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md),
this **warns rather than errors** on a violation: the plan and its rules
are each valid, and an agent or a planner checking a proposal needs to
see what it breaks, not be refused. It does error on a rule it cannot
measure – a target naming a value the plan does not have, or a change
rule with no `reference` to change from.

Rules about groups of rows live here; rules about single rows are the
plan's own spend bounds, which the plan's validator already guarantees.
They are reported anyway, as one `row_bounds` row, so the report is
complete.

## See also

[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md);
[`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md),
which summarises the check when given `constraints`.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(month = as.Date("2026-10-01"),
             channel = c("Streaming", "Programmatic", "Online Video"),
             planned_spend = c(500, 300, 200)),
  grain = "channel", time = "month", name = "Q4"
)
rules <- plan_constraints(list(
  rule_min_share(0.4, target = list(channel = "Streaming")),
  rule_max_change_pct(0.25, target = list(channel = "Online Video"))
), name = "guardrails")

check_constraints(plan, rules, reference = plan)
#>   rule           type               target window limit actual slack   ok note
#> 1    1      min_share    channel Streaming   <NA>  0.40    0.5  0.10 TRUE     
#> 2    2 max_change_pct channel Online Video   <NA>  0.25    0.0  0.25 TRUE     

moved <- build_scenario(plan, name = "more video", edits = op_transfer(
  150, from = list(channel = "Streaming"), to = list(channel = "Online Video")))
check_constraints(moved, rules, reference = plan)
#> Warning: 2 of 2 rule(s) violated: min_share 0.4 on channel Streaming: actual 0.35 (slack -0.05); max_change_pct 0.25 on channel Online Video: actual 0.75 (slack -0.5).
#>   rule           type               target window limit actual slack    ok note
#> 1    1      min_share    channel Streaming   <NA>  0.40   0.35 -0.05 FALSE     
#> 2    2 max_change_pct channel Online Video   <NA>  0.25   0.75 -0.50 FALSE     
```
