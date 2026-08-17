# Check a plan against a decomp (the one pairing operation)

A plan on its own holds intent and is blind to what has already
happened. Pair it with a decomp — which reports actualised spend and
attributed KPI through a date — and questions about history become
answerable. This is the first of those: **does the plan account for
everything the model measured?**

## Usage

``` r
check_coverage(plan, decomp, through = NULL)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- decomp:

  A data frame of the decomp's line items. May name any subset of
  [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
  — a channel-only decomp checks channels and ignores partners.

- through:

  Optional `Date`. Restricts the check to plan rows in market before
  that date; see *What `through` compares against*. Without it, or on a
  plan with no time dimension, the whole plan is considered.

## Value

Invisibly, a character vector of the decomp line items missing from the
plan — empty when coverage is complete. Returned so a UI can render
them; the warning is for interactive use.

## Details

Every line item in `decomp` should appear in the plan rows dated before
`through`. Missing ones are reported. Line items the plan has and the
decomp does not are *never* flagged: the future portion is expected to
introduce new partners and tactics, and the historical portion may carry
line items the decomp never modelled.

This **warns rather than errors**. Both artifacts are individually
valid; it is their pairing that disagrees, so an app should surface the
mismatch and let the user resolve it, not refuse to load the plan.

## What `through` compares against

A row is in scope when **any part of its in-market period falls before**
`through` — overlap, not containment. A decomp reporting through a
Wednesday has measured part of the week that began on the Monday, so
that line item should be expected in the plan.

The comparison is against the row's period from
[`flight_window()`](https://roeh-marketing.github.io/mediaplanr/reference/flight_window.md)'s
machinery, not the bare week value, so it is right for a flight that
starts or ends mid-week: a buy whose flight begins on the Wednesday is
*not* in scope for a decomp reporting through the Tuesday, even though
its week started on the Monday.

One consequence is worth stating rather than discovering. A long flight
that began the day before `through` is in scope on the strength of a
single measured day. That is deliberate — the decomp saw part of it, so
the line item should appear in the plan — but it means being in scope
says nothing about *how much* of a buy the decomp measured.

## Examples

``` r
p <- media_plan_from_df(
  data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
  grain = "channel", name = "Q3 plan"
)
check_coverage(p, data.frame(channel = c("TV", "Search")))
```
