# Unit types with a conventional rate basis

The unit types this package knows a trade convention for. `unit_type` is
**not** restricted to these — media invents units faster than any
package can track them, and an unknown type is accepted and priced per
single unit. These are the ones where that would be wrong:

## Usage

``` r
unit_type_levels()
```

## Value

A character vector of the known unit types.

## Details

- `"impression"` — quoted as a **CPM**, a cost per thousand, so
  `rate_per` is 1000.

Everything else is quoted per single unit: a CPC per click, a CPP per
GRP, a unit cost per spot.

## Examples

``` r
unit_type_levels()
#> [1] "impression"     "click"          "grp"            "trp"           
#> [5] "spot"           "view"           "install"        "engagement"    
#> [9] "completed_view"
```
