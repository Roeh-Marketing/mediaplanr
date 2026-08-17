# The allowed buying cadences

What kind of period a flight represents. `"day"` is a single dated
insertion, `"week"` a standard weekly buy, `"flight"` any other
continuous in-market period.

## Usage

``` r
period_basis_levels()
```

## Value

A character vector of the valid, canonical values.

## Examples

``` r
period_basis_levels()
#> [1] "day"    "week"   "month"  "flight"
```
