# The allowed plan workflow states

`@status` tracks where a plan sits in the review workflow. The set is
fixed so that typos error rather than creating a silent fourth state,
and so a UI can build its dropdown from one source of truth. `""` means
unset.

## Usage

``` r
status_levels()
```

## Value

A character vector of the valid, canonical status values.

## Examples

``` r
status_levels()
#> [1] "in development" "to review"      "approved"      
```
