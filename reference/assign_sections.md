# Which section each line item belongs to

Places every line item of a plan in the sections of an organization
tree: brand and performance, lines of business, channels. `sections`
holds the tree's **leaves**, each a target – the same named list of
grain column = value(s) an op uses – or a list of targets. A line item
is in a section when the section matches any of its rows.

## Usage

``` r
assign_sections(plan, sections)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- sections:

  A named list, one entry per leaf section: its target, or a list of
  targets. Names must be distinct.

## Value

A data frame with one row per line item
([`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)):

- `line_item`:

  Its key, as
  [`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
  writes it.

- `section`:

  The one section it is in; `NA` when it is in none, or in more than
  one.

- `n_matches`:

  How many sections it is in.

Attributes `overlaps` (a data frame of `line_item` and `sections`, the
sections' names joined with `", "`) and `unmatched` (the line items in
no section) list the disagreements, which also print beneath the table.

## Details

A clean tree puts every line item in exactly one leaf. This reports
where the plan and the tree disagree – line items in two leaves, line
items in none – and **never errors** on either: whether an overlap is a
mistake in the tree or a shared line, and whether an unplaced line item
belongs to nobody or to a leaf not yet drawn, is the caller's decision.

A section may name a value the plan does not have (an organization names
channels a plan has stopped buying), so values are matched leniently, as
[`match_rows()`](https://roeh-marketing.github.io/mediaplanr/reference/match_rows.md)
with `strict = FALSE`. A column that is not in the grain is still an
error: the organization's levels must be grain columns – add a missing
level with
[`regrain()`](https://roeh-marketing.github.io/mediaplanr/reference/regrain.md).

## See also

[`match_rows()`](https://roeh-marketing.github.io/mediaplanr/reference/match_rows.md);
[`check_budget()`](https://roeh-marketing.github.io/mediaplanr/reference/check_budget.md)
for a section's envelope.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "TV", "Search", "Social"),
             partner = c("NBC", "ESPN", "Google", "Meta"),
             planned_spend = c(50, 30, 40, 40)),
  grain = c("channel", "partner"), time = "week", name = "Q3"
)
assign_sections(plan, list(
  Video  = list(channel = "TV"),
  Search = list(channel = "Search"),
  Google = list(partner = "Google")   # overlaps Search
))
#>         line_item section n_matches
#> 1        TV | NBC   Video         1
#> 2       TV | ESPN   Video         1
#> 3 Search | Google    <NA>         2
#> 4   Social | Meta    <NA>         0
#> 1 in more than one section (Search | Google); 1 in none (Social | Meta).
```
