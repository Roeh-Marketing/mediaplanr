# Abbreviate a synthetic id for printing

Keeps the human-readable prefix and the trailing random segment,
collapsing the timestamp in the middle to an ellipsis.

## Usage

``` r
short_id(id)
```

## Arguments

- id:

  A character id produced by `new_id()`.

## Value

A short character string suitable for console output.
