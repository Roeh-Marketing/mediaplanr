# JSON Schema for the rules an agent may write

Describes a list of plan rules – what
[`plan_constraints()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_constraints.md)
takes – as a JSON Schema, draft 2020-12, in the way
[`plan_ops_schema()`](https://roeh-marketing.github.io/mediaplanr/reference/plan_ops_schema.md)
describes ops: an array of rules, each exactly one of the rule types,
with that type's value range (a share is 0 to 1) and fields. With a
plan, a rule's `target` may name only the plan's line item columns, each
limited to the values present.

## Usage

``` r
constraints_schema(plan = NULL, as_json = FALSE)
```

## Arguments

- plan:

  Optional
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md)
  to narrow the schema to.

- as_json:

  `FALSE` (default) returns the schema as a nested list; `TRUE` returns
  it as JSON text.

## Value

A nested list, or a `json` string when `as_json = TRUE`.

## See also

[rules](https://roeh-marketing.github.io/mediaplanr/reference/rules.md)
for the constructors that build each shape.

## Examples

``` r
schema <- constraints_schema()
vapply(schema$items$oneOf, function(rule) rule$title, character(1))
#> [1] "min_spend"      "max_spend"      "fixed_total"    "min_share"     
#> [5] "max_share"      "max_change_abs" "max_change_pct"
```
