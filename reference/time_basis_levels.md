# What one value of a plan's time column stands for

A plan's `@time_basis`. `"day"`, `"week"` and `"month"` are `Date`
columns holding the first day of the period, so a row covers that day,
that week, or that calendar month. `"instant"` is a `POSIXct` column
holding the exact moment a buy runs — a dated spot, an 8pm takeover, a
half-hour sponsorship.

## Usage

``` r
time_basis_levels()
```

## Value

A character vector of the valid, canonical values.

## Details

A timed row is keyed by the moment it starts, and its **length is its
flight's**: a 30-second spot flighted `20:00:00` to `20:00:30` covers
half a minute, a sponsorship flighted `20:00` to `20:30` covers half an
hour, and a moment with no flight is a point in time. That is the same
rule as every other basis — the row's period, resolved against the buy
it belongs to — with the difference that a timed buy occupies exactly
one row, so there is nothing to spread across.

The basis is tied to the column's type: a `Date` column is `"day"`,
`"week"` or `"month"`, and a `POSIXct` column is always `"instant"`.

## See also

[`media_plan_from_df()`](https://roeh-marketing.github.io/mediaplanr/reference/media_plan_from_df.md),
[`period_basis_levels()`](https://roeh-marketing.github.io/mediaplanr/reference/period_basis_levels.md)
for the *flight* cadence, which is a different thing: what kind of buy a
flight is, rather than what one plan row covers.

## Examples

``` r
time_basis_levels()
#> [1] "day"     "week"    "month"   "instant"
```
