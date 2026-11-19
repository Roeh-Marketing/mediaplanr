# Which response model scores each line item

Maps every line item of a plan to the response model that should score
it, when models are fitted at a different grain from the plan – or at
several. `models` lists the fitted models, one row each, by the line
item values they cover: a channel-level model names a channel and leaves
the finer columns empty; a partner-level model names the partner too.

## Usage

``` r
model_map(plan, models)
```

## Arguments

- plan:

  A
  [MediaPlan](https://roeh-marketing.github.io/mediaplanr/reference/MediaPlan.md).

- models:

  A data frame of fitted models: a `model_id` column (unique) and any of
  the plan's
  [`line_item_grain()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_grain.md)
  columns. `NA` or a blank cell means the model covers any value of that
  column; a row with no line item columns set covers the whole plan.

## Value

One row per line item, in
[`line_item_summary()`](https://roeh-marketing.github.io/mediaplanr/reference/line_item_summary.md)'s
order: the line item columns, `line_item` (its key), `model_id`,
`match_level` (the columns the model matched on, joined with `" + "`;
`""` for a whole-plan model, `NA` when unmodeled) and `planned_spend`.

## Details

**The most specific model wins.** Of the models whose named values all
match a line item, the one naming the most columns is chosen, so a
partner-level model takes precedence over its channel's model, which is
the fallback for the channel's other partners. Two matching models
naming the same number of columns – a channel model and a campaign
model, both covering one line – is an error naming both: which one
scores it is a decision for whoever fitted them, not a guess for this
function.

A line item no model covers gets `model_id = NA`, and a warning gives
the spend left unmodeled and its share of the plan. Both the plan and
the models are valid on their own; it is their pairing that leaves a
gap.

## See also

[`spend_by_model()`](https://roeh-marketing.github.io/mediaplanr/reference/spend_by_model.md)
for the spend each model scores, period by period;
[`describe_plan()`](https://roeh-marketing.github.io/mediaplanr/reference/describe_plan.md),
which reports model coverage when given `models`.

## Examples

``` r
plan <- media_plan_from_df(
  data.frame(week = as.Date("2026-07-06"),
             channel = c("TV", "TV", "Search", "Audio"),
             partner = c("NBC", "ESPN", "Google", "Spotify"),
             planned_spend = c(50, 30, 40, 10)),
  grain = c("channel", "partner"), time = "week", name = "Q3"
)
models <- data.frame(
  model_id = c("tv", "tv_nbc", "search"),
  channel  = c("TV", "TV", "Search"),
  partner  = c(NA, "NBC", NA)
)
# NBC has its own model; ESPN falls back to TV's; Audio has none.
model_map(plan, models)
#> Warning: 1 line item(s) have no model: Audio | Spotify (10). 10 of 130 planned spend (7.7%) is unmodeled.
#>   channel partner       line_item model_id       match_level planned_spend
#> 1      TV     NBC        TV | NBC   tv_nbc channel + partner            50
#> 2  Search  Google Search | Google   search           channel            40
#> 3      TV    ESPN       TV | ESPN       tv           channel            30
#> 4   Audio Spotify Audio | Spotify     <NA>              <NA>            10
```
