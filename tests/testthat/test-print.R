# Print methods are the main way a user inspects these objects in a console, so
# the contract worth pinning is: required info always present, optional info
# shown only when set, and nothing leaked that would confuse (e.g. an empty
# advertiser line, or a set-level advertiser the scenarios disagree on).

grab <- function(x) paste(utils::capture.output(print(x)), collapse = "\n")

test_that("a minimal plan prints the essentials and nothing optional", {
  out <- grab(std_plan(name = "Simple Plan"))
  expect_match(out, "<MediaPlan> Simple Plan")
  expect_match(out, "grain")
  expect_match(out, "spend")
  # optional slots are omitted entirely rather than shown blank
  expect_false(grepl("advertiser", out))
  expect_false(grepl("planner", out))
  expect_false(grepl("\\[", out))          # no status badge
  expect_false(grepl("derived from", out)) # no parent
})

test_that("metadata appears when set, including the status badge", {
  p <- media_plan_from_df(
    data.frame(channel = "TV", planned_spend = 10), grain = "channel",
    name = "Q2 Plan", nickname = "baseline", advertiser = "Acme",
    planner = "R. Roe", status = "approved", objective = "hold the mix")
  out <- grab(p)
  expect_match(out, 'Q2 Plan \\("baseline"\\)')
  expect_match(out, "\\[approved\\]")
  expect_match(out, "advertiser  Acme")
  expect_match(out, "planner     R\\. Roe")
  expect_match(out, "objective   hold the mix")
})

test_that("a weekly plan reports its flight window and line item count", {
  out <- grab(weekly_plan())
  # the window ends on the last day of the last week, not on its start
  expect_match(out, "flight      2026-03-02 to 2026-04-12")
  expect_match(out, "\\(2 weeks\\)")
  expect_match(out, "line items  3")
})

test_that("the inventory lists each dimension under the user's own column name", {
  out <- grab(weekly_plan())
  expect_match(out, "    channel   Search, TV")
  expect_match(out, "    partner   Google, Hulu, NBC")
})

test_that("a timeless plan shows its inventory but no flight or line item count", {
  out <- grab(std_plan())
  expect_match(out, "    channel   Search, Social, TV")
  expect_false(grepl("flight", out))
  # rows and line items are the same number without a time dimension
  expect_false(grepl("line items", out))
})

test_that("a flighted plan reports its flights by cadence", {
  p <- media_plan_from_flights(
    data.frame(channel = c("OOH", "Search"),
               flight_start = as.Date(c("2026-04-06", "2026-04-08")),
               flight_end   = as.Date(c("2026-05-03", "2026-04-08")),
               planned_spend = c(120000, 3100)),
    grain = "channel", name = "Flighted")
  out <- grab(p)
  expect_match(out, "flights     2  \\(1 day, 1 flight\\)")
  # the flighting columns are summarised, not repeated down the preview
  expect_false(grepl("flight_id", out))
  expect_false(grepl("period_basis", out))
})

test_that("a plan without flights shows no flights line", {
  expect_false(grepl("flights", grab(weekly_plan())))
})

test_that("a long dimension is truncated with a count of the remainder", {
  p <- media_plan_from_df(
    data.frame(partner = paste0("P", sprintf("%02d", 1:9)),
               planned_spend = rep(10, 9)),
    grain = "partner", name = "Many partners")
  expect_match(grab(p), "\\(\\+3 more\\)")
})

test_that("a derived plan shows its lineage", {
  p <- std_plan(name = "Base")
  s <- build_scenario(p, edits = c("TV" = 90), name = "Variant")
  out <- grab(s)
  expect_match(out, "derived from")
  expect_match(out, short_id(p@id))
})

test_that("the data preview is truncated with a count of the remainder", {
  out <- grab(weekly_plan())          # 5 rows, 3 shown
  expect_match(out, "\\.\\.\\. 2 more rows")
})

test_that("a one-row remainder is not pluralised", {
  p <- media_plan_from_df(
    data.frame(channel = c("a", "b", "c", "d"), planned_spend = c(1, 2, 3, 4)),
    grain = "channel", name = "Four")
  expect_match(grab(p), "\\.\\.\\. 1 more row\\b")
})

test_that("a scenario set prints one row per scenario with status and delta", {
  base <- media_plan_from_df(
    data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
    grain = "channel", name = "Base", nickname = "baseline",
    advertiser = "Acme", status = "approved")
  set <- add_scenario(scenario_set(base),
                      build_scenario(base, edits = list(total = 240),
                                     name = "Bigger", nickname = "double"))
  out <- grab(set)
  expect_match(out, "2 scenarios at channel")
  expect_match(out, "advertiser  Acme")
  expect_match(out, "scenario")
  expect_match(out, "\\* baseline")          # baseline marked
  expect_match(out, "approved")
  expect_match(out, "in development")        # derived scenario's reset status
  expect_match(out, "\\+120 \\(\\+100%\\)")  # delta and percentage
  expect_match(out, "\\* = baseline")
})

test_that("the set-level advertiser is hidden when scenarios disagree", {
  a <- media_plan_from_df(data.frame(channel = "TV", planned_spend = 10),
                          grain = "channel", name = "A", advertiser = "Acme")
  b <- media_plan_from_df(data.frame(channel = "TV", planned_spend = 20),
                          grain = "channel", name = "B", advertiser = "Other Co")
  out <- grab(add_scenario(scenario_set(a), b))
  expect_false(grepl("advertiser", out))
})

test_that("an unset status shows as a placeholder, not blank or NA", {
  out <- grab(scenario_set(std_plan(name = "No Status")))
  expect_false(grepl("NA", out))
})

test_that("print returns its argument invisibly", {
  p <- std_plan()
  invisible(utils::capture.output(res <- withVisible(print(p))))
  expect_false(res$visible)
  expect_identical(res$value, p)
})
