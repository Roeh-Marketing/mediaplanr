# The rows a target selects

Resolves a target – or a list of them – to the plan's rows, exactly as
[`build_scenario()`](https://roeh-marketing.github.io/mediaplanr/reference/build_scenario.md)
resolves an op's `target` and `during`. It is the one matcher: a caller
that needs to know which rows a section, a scope or an op names asks
here rather than matching rows itself, so the answer can never disagree
with what an edit would touch.

## Usage

``` r
match_rows(plan, target, during = NULL, strict = TRUE)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- target:

  One target (`list(channel = "TV")`), or a list of targets
  (`list(list(channel = "TV"), list(partner = "DSP A"))`), named or not
  – so a planner's sections, `sections[c("Video", "Search")]`, are a
  scope. Empty or `NULL` is the whole plan, as for an op.

- during:

  Optional `list(from =, to =)`: narrows to rows whose period
  **overlaps** the window, as an op's `during` does.

- strict:

  With `TRUE` (the default), a value the plan does not have, a target
  whose values never occur together, or a window with nothing in market
  is an error naming the alternatives – exactly what an op's target
  gives. With `FALSE`, those match nothing instead: a scope may name a
  value the plan no longer has. A column that is not in the grain is an
  error either way.

## Value

A logical vector over the rows of `plan@data`.

## Details

A target is a named list of grain column = value(s), naming any subset
of the grain: every named column must match (AND), and a column given
several values matches any of them. A **list of targets** matches the
rows any one of them matches (OR) – which is what a planner's scope is.

Unlike an edit, this does not refuse rows a subplan owns: it reads, it
does not edit.

## See also

[`assign_sections()`](https://roeh-marketing.github.io/mediaplanr/reference/assign_sections.md),
[`ops_within()`](https://roeh-marketing.github.io/mediaplanr/reference/ops_within.md),
[`rebase_check()`](https://roeh-marketing.github.io/mediaplanr/reference/rebase_check.md)

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "TV", "Search", "Social"),
             partner = c("NBC", "ESPN", "Google", "Meta"),
             planned_spend = c(50, 30, 40, 40)),
  grain = c("channel", "partner"), time = "week", name = "Q3"
)
match_rows(plan, list(channel = "TV"))
#> [1]  TRUE  TRUE FALSE FALSE

# a scope: TV, or anything on Google
match_rows(plan, list(list(channel = "TV"), list(partner = "Google")))
#> [1]  TRUE  TRUE  TRUE FALSE

# a scope may name a channel the plan no longer buys
match_rows(plan, list(channel = c("Search", "Audio")), strict = FALSE)
#> [1] FALSE FALSE  TRUE FALSE
```
