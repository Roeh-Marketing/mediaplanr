# The allowed pacing patterns

How a flight's spend is shaped across its weeks. `"even"` means the
weekly figures are exactly what spreading the flight's total across its
days gives. `"custom"` means a planner has shaped it by hand and it no
longer follows that rule.

## Usage

``` r
pacing_levels()
```

## Value

A character vector of the valid, canonical values.

## Details

Pacing is **re-derived after every edit**, so it describes the shape the
rows actually have rather than remembering whether anyone touched them.
Two consequences worth knowing:

- Scaling a whole flight, or setting its total, leaves it `"even"` —
  every week moves in proportion, so only the amount changed, not the
  shape.

- Editing one week, or adding a flat amount to weeks of unequal length,
  makes it `"custom"`.

Either way the flight survives: its `flight_id` is never dropped, so a
hand-shaped buy is still one buy and
[`flights()`](https://roeh-marketing.github.io/mediaplanr/reference/flights.md)
still reports it whole.

## Examples

``` r
pacing_levels()
#> [1] "even"   "custom"
```
