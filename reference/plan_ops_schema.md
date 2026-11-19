# JSON Schema for the edits an agent may send

Describes the operations form of `edits` (see
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md))
as a JSON Schema, draft 2020-12: an array of ops, each exactly one of
the shapes the [op
constructors](https://roeh-marketing.github.io/mediaplanr/reference/ops.md)
build. Hand it to a tool-calling model as the type of its `edits`
argument, and a malformed op is refused before R sees it.

## Usage

``` r
plan_ops_schema(plan = NULL, as_json = FALSE)
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

## Details

Without a plan, the schema says what any op may look like. With one, it
narrows to what is legal on **that** plan, which is the contract to give
an agent working on it:

- `target` may name only the plan's grain columns, each limited to the
  values present.

- Dates take the shape the plan's time basis uses: `YYYY-MM-DD` for a
  plan keyed by day, week or month; a date or a date-time for a plan of
  moments.

- `add` must name every line item column, and may set only columns the
  plan has.

The schema is the first check, not the only one. Some rules depend on
the plan's rows in ways a schema cannot state – values that each exist
but never occur together, a shift that would collide with a row already
planned – and
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
still enforces them.

To read an agent's ops in R, parse with
`jsonlite::fromJSON(x, simplifyVector = FALSE)`. Simplifying turns an
array of ops into a data frame, which
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
would read as an allocation rather than a list of operations.

## See also

[ops](https://roeh-marketing.github.io/mediaplanr/reference/ops.md) for
the constructors that build each shape.

## Examples

``` r
schema <- plan_ops_schema()
vapply(schema$items$oneOf, function(op) op$title, character(1))
#>  [1] "set"        "scale"      "delta"      "delta_each" "total"     
#>  [6] "transfer"   "add"        "drop"       "shift"      "restage"   
#> [11] "rebound"   

plan <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", time = "week", name = "base"
)
# On a plan, `target` lists the values an op may name.
scale <- plan_ops_schema(plan)$items$oneOf[[2]]
scale$properties$target$properties$channel
#> $anyOf
#> $anyOf[[1]]
#> $anyOf[[1]]$enum
#> [1] "Search" "TV"    
#> 
#> 
#> $anyOf[[2]]
#> $anyOf[[2]]$type
#> [1] "array"
#> 
#> $anyOf[[2]]$items
#> $anyOf[[2]]$items$enum
#> [1] "Search" "TV"    
#> 
#> 
#> $anyOf[[2]]$minItems
#> [1] 1
#> 
#> 
#> 

cat(substr(plan_ops_schema(plan, as_json = TRUE), 1, 200))
#> {
#>   "$schema": "https://json-schema.org/draft/2020-12/schema",
#>   "title": "mediaplanr edits",
#>   "description": "Edit operations applied in order to derive a scenario. Each op carries exactly one opera
```
