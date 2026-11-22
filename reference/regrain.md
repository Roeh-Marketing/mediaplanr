# Add an organization level to a plan's grain

Inserts a new grain column `name`, before the column `before`, whose
value on each row is read from another grain column through `groups`:
for instance a `funnel` column grouping `channel` into Brand and
Performance. Every value of `from` in the plan must sit in exactly one
group; anything else is refused, naming the values.

## Usage

``` r
regrain(plan, name, from, groups, before = from)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md),
  without subplans.

- name:

  The new column's name, such as `"funnel"`. Not a column the plan
  already has, nor one the package reserves.

- from:

  The line item column the new one is read from, such as `"channel"`.

- groups:

  A named list: each group's name, and the values of `from` in it –
  `list(Brand = c("TV", "Streaming"), Performance = "Search")`. A group
  may name values the plan does not have.

- before:

  The line item column the new one goes in front of; by default `from`,
  since a grouping is coarser than what it groups and the grain is
  ordered coarsest-first.

## Value

The same plan (same `@id`) with `name` in its grain and data.

## Details

Line item keys change –
[`line_item()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item.md)
gains the new column – and nothing else does: the rows, their spend, and
the plan's `@id`, `@parent_id`, `@status`, `@approved_on`, `@rationale`
and every other slot are carried as
[`revise()`](https://roeh-marketing.github.io/mediaplanr/reference/revise.md)
carries them. A target that names the old columns selects the same rows
after, so a stored op still replays. A stored `add` or allocation names
every grain column, so it gains the new one too, and the plan's `@edits`
replay on a parent regrained with the same `groups`.

To regrain a set of revisions and drafts, regrain each plan with the
same arguments: the ids, and so
[`lineage()`](https://roeh-marketing.github.io/mediaplanr/reference/lineage.md)
and
[`current_approved()`](https://roeh-marketing.github.io/mediaplanr/reference/current_approved.md),
are unchanged.

A plan holding subplans is refused: a subplan's grain must contain its
parent's, so the column would have to be added beneath it too.

## See also

[`assign_sections()`](https://roeh-marketing.github.io/mediaplanr/reference/assign_sections.md),
which needs every organization level to be a grain column.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "Streaming", "Search"),
             planned_spend = c(50, 30, 40)),
  grain = "channel", time = "week", name = "Q3"
)
by_funnel <- regrain(plan, "funnel", from = "channel",
                     groups = list(Brand = c("TV", "Streaming"),
                                   Performance = "Search"))
by_funnel@grain
#> [1] "funnel"  "channel" "week"   
line_item(by_funnel@data, line_item_grain(by_funnel))
#> [1] "Brand | TV"           "Brand | Streaming"    "Performance | Search"
```
