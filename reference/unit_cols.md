# The columns that record what a line item buys

Reserved column names carried on `@data` when a plan records more than
money. Like the flighting columns they ride along: the validator checks
them, but they never form part of `@grain`.

## Usage

``` r
unit_cols()
```

## Value

A character vector of the reserved column names.

## Examples

``` r
unit_cols()
#> [1] "unit_type"     "planned_units" "planned_rate" 
```
