# The columns that record flighting

Reserved column names carried on `@data` when a plan was authored as
flights. They ride along: the validator type-checks them, but they never
form part of `@grain` and never key a row.

## Usage

``` r
flight_cols()
```

## Value

A character vector of the reserved column names.

## Examples

``` r
flight_cols()
#> [1] "flight_id"    "flight_start" "flight_end"   "period_basis" "pacing"      
```
