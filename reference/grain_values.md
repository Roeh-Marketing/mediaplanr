# The values present on a grain column

Answers "which channels are in this plan?" — for whatever the user
called their channel column. The package never privileges a column name:
`channel` is simply a dimension someone chose to key on, and a plan may
key on `media_type` or `vehicle` instead. So this takes the column by
name and errors, listing the alternatives, when asked for one the plan
does not have.

## Usage

``` r
grain_values(plan, col = NULL)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- col:

  Name of a single grain column. `NULL` (the default) returns a named
  list covering every grain column, including the week.

## Value

Sorted unique values for `col`, in the column's own type; or a named
list of those vectors when `col` is `NULL`.

## Details

The values are exactly what
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)'s
`target` accepts, so an answer from here can be passed straight into an
edit without translation.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("TV", "TV", "Search"),
             partner = c("NBC", "ESPN", "Google"),
             planned_spend = c(30, 20, 50)),
  grain = c("channel", "partner"), name = "Q3 plan"
)

grain_values(p, "channel")
#> [1] "Search" "TV"    
grain_values(p)
#> $channel
#> [1] "Search" "TV"    
#> 
#> $partner
#> [1] "ESPN"   "Google" "NBC"   
#> 
```
