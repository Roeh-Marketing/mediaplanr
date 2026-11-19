# Build a plan rule

Constructors for the rules a
[PlanConstraints](https://roeh-marketing.github.io/mediaplanr/reference/PlanConstraints.md)
holds, in the pattern of the [op
constructors](https://roeh-marketing.github.io/mediaplanr/reference/ops.md):
each returns the plain list you could write by hand –
`rule_min_share(0.4, target = list(channel = "Streaming"))` is
`list(type = "min_share", value = 0.4, target = list(channel = "Streaming"))`
– and checks it where it is written.

## Usage

``` r
rule_min_spend(value, target = NULL, during = NULL, note = NULL)

rule_max_spend(value, target = NULL, during = NULL, note = NULL)

rule_fixed_total(value, target = NULL, during = NULL, note = NULL)

rule_min_share(value, target = NULL, during = NULL, note = NULL)

rule_max_share(value, target = NULL, during = NULL, note = NULL)

rule_max_change_abs(value, target = NULL, during = NULL, note = NULL)

rule_max_change_pct(value, target = NULL, during = NULL, note = NULL)
```

## Arguments

- value:

  The rule's limit: an amount of money, or a share or fraction from 0 to
  1 for the share rules (`max_change_pct` may exceed 1).

- target:

  Optional named list of line item column = value(s), as in an op; omit
  for the whole plan. Rules measure whole days, so time is given by
  `during`, not by naming the time column.

- during:

  Optional `list(from =, to =)` of dates.

- note:

  Optional text saying why the rule exists.

## Value

A plain list: one rule, for
[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md).

## Details

Every rule measures the spend on its `target` rows inside its `during`
window, day by day (as
[`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md)
does), and compares it with `value`:

- `rule_min_spend()`, `rule_max_spend()`:

  That spend is at least, or at most, `value`.

- `rule_fixed_total()`:

  That spend is exactly `value` – a commitment on a line's or a flight's
  total that leaves its phasing free. (A commitment month by month is a
  spend bound on the plan instead; see
  [`bound_cols()`](https://roeh-marketing.github.io/mediaplanr/reference/bound_cols.md).)

- `rule_min_share()`, `rule_max_share()`:

  That spend, as a share of the whole plan's spend in the same window,
  is at least or at most `value`, from 0 to 1.

- `rule_max_change_abs()`, `rule_max_change_pct()`:

  That spend moves by at most `value` – an amount, or a fraction of the
  reference's – from a reference plan, normally the parent or the
  current approved plan.
  [`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md)
  needs the reference for these.

## See also

[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md),
[`check_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/check_constraints.md).

## Examples

``` r
rule_min_share(0.4, target = list(channel = "Streaming"))
#> $type
#> [1] "min_share"
#> 
#> $value
#> [1] 0.4
#> 
#> $target
#> $target$channel
#> [1] "Streaming"
#> 
#> 
rule_max_change_pct(0.25, target = list(channel = "Online Video"),
                    note = "no channel swings more than 25%")
#> $type
#> [1] "max_change_pct"
#> 
#> $value
#> [1] 0.25
#> 
#> $target
#> $target$channel
#> [1] "Online Video"
#> 
#> 
#> $note
#> [1] "no channel swings more than 25%"
#> 
```
