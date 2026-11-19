# Build a set of plan rules

Collects rules into a
[PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md)
object. Rules come either as a list of rules, built with the [rule
constructors](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
or written by hand as plain lists, or as a table – the shape a rules
sheet takes:

## Usage

``` r
plan_constraints(rules, name = "", id = NULL)
```

## Arguments

- rules:

  A list of rules, or a rules table as described above.

- name:

  A name for the rule set.

- id:

  Optional explicit id; generated when `NULL`. A scenario's
  `rationale$constraints_id` refers to it.

## Value

A
[PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md).

## Details

- `type` and `value`, required;

- `from` and `to`, an optional window (both or neither);

- `note`, optional;

- any of the plan's line item columns, naming the rows a rule covers. A
  blank or `NA` means any value; a row naming none covers the whole
  plan.

Either way every rule is checked where it is written, and stored in one
canonical form, so the same rules built either way are the same object.

## See also

[`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md)
to check a plan against them;
[`constraints_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/constraints_schema.md)
for the JSON Schema an agent's rules are checked against.

## Examples

``` r
rules <- plan_constraints(name = "Q4 guardrails", rules = list(
  rule_min_share(0.4, target = list(channel = "Streaming")),
  rule_max_spend(320000, target = list(channel = "Programmatic"),
                 during = list(from = "2026-10-01", to = "2026-12-31")),
  rule_fixed_total(360000, target = list(partner = "Stream A"),
                   note = "upfront: total fixed, phasing free")
))
rules
#> <PlanConstraints> Q4 guardrails  (3 rules)
#>   min_share 0.4 on channel Streaming
#>   max_spend 320,000 on channel Programmatic, 2026-10-01..2026-12-31
#>   fixed_total 360,000 on partner Stream A -- upfront: total fixed, phasing free

# The same rules as a sheet would hold them
sheet <- data.frame(
  type    = c("min_share", "max_spend", "fixed_total"),
  value   = c(0.4, 320000, 360000),
  from    = c(NA, "2026-10-01", NA),
  to      = c(NA, "2026-12-31", NA),
  note    = c("", "", "upfront: total fixed, phasing free"),
  channel = c("Streaming", "Programmatic", NA),
  partner = c(NA, NA, "Stream A")
)
identical(plan_constraints(sheet, name = "Q4 guardrails")@rules, rules@rules)
#> [1] TRUE
```
