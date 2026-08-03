# Line item identifier for each row

Collapses the given columns into a single character vector of line item
identifiers, one per row. A **line item** is a specific combination of
the plan's descriptive dimensions — channel, partner, tactic — and is
how the package identifies what a row is buying. This is what the decomp
constrains and what response models attach to.

## Usage

``` r
line_item(df, cols, sep = " | ")
```

## Arguments

- df:

  A data frame containing the columns.

- cols:

  Character vector of column names to combine.

- sep:

  Separator between parts. Default `" | "`.

## Value

A character vector of identifiers, length `nrow(df)`.

## Details

At a weekly grain a row is a line item *for a given week*, so pass
[`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
to identify the line item independent of time, or the full `@grain` to
identify the row.

## Examples

``` r
d <- data.frame(channel = c("TV", "TV"), partner = c("NBC", "ESPN"))
line_item(d, c("channel", "partner"))
#> [1] "TV | NBC"  "TV | ESPN"
```
