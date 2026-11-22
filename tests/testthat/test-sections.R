# Sections and scopes. The contract: every verb here resolves rows through the
# matcher the edit path uses, so a scope check never disagrees with what an
# edit would touch.

q1 <- function() list(from = "2027-01-01", to = "2027-03-31")

# ---- match_rows ------------------------------------------------------------------

test_that("match_rows takes a partial key", {
  p <- fix_agency_plan()
  m <- match_rows(p, list(partner = "DSP A"))
  expect_type(m, "logical")
  expect_length(m, nrow(p@data))
  expect_equal(m, p@data$partner == "DSP A")

  both <- match_rows(p, list(channel = "Streaming", campaign = "Promo"))
  expect_equal(both, p@data$channel == "Streaming" & p@data$campaign == "Promo")
})

test_that("an empty target is the whole plan, as for an op", {
  p <- fix_agency_plan()
  expect_true(all(match_rows(p, list())))
  expect_true(all(match_rows(p, NULL)))
})

test_that("a list of targets matches any of them", {
  p <- fix_agency_plan()
  m <- match_rows(p, list(list(channel = "Streaming"),
                          list(partner = "DSP A", tactic = "Prospecting")))
  want <- p@data$channel == "Streaming" |
    (p@data$partner == "DSP A" & p@data$tactic == "Prospecting")
  expect_equal(m, want)
})

test_that("a list of targets parsed from JSON reads the same", {
  p <- fix_agency_plan()
  scope <- jsonlite::fromJSON(
    '[{"channel": "Streaming"}, {"partner": ["DSP A", "DSP B"]}]',
    simplifyVector = FALSE)
  expect_equal(match_rows(p, scope),
               p@data$channel == "Streaming" | p@data$channel == "Programmatic")
})

test_that("during narrows to rows overlapping the window", {
  p <- fix_agency_plan()
  m <- match_rows(p, list(channel = "Streaming"), during = q1())
  expect_equal(m, p@data$channel == "Streaming" &
                 p@data$month >= as.Date("2027-01-01"))
  # a window cutting into a month takes that month whole
  mid <- match_rows(p, list(channel = "Streaming"),
                    during = list(from = "2026-12-15", to = "2026-12-20"))
  expect_true(all(p@data$month[mid] == as.Date("2026-12-01")))
})

test_that("strict = TRUE errors as an op's target does", {
  p <- fix_agency_plan()
  expect_error(match_rows(p, list(channel = "Radio")),
               "no such value\\(s\\) in 'channel': Radio")
  expect_error(match_rows(p, list(chanel = "Streaming")),
               "may only name grain columns")
  expect_error(match_rows(p, list(channel = "Streaming", partner = "DSP A")),
               "do not co-occur")
  expect_error(match_rows(p, list(channel = "Streaming"),
                          during = list(from = "2028-01-01", to = "2028-01-31")),
               "no rows are in market")
  # the same message build_scenario() gives, word for word
  op_msg <- tryCatch(build_scenario(p, op_scale(2, list(channel = "Radio")),
                                    name = "x"),
                     error = conditionMessage)
  rows_msg <- tryCatch(match_rows(p, list(channel = "Radio")),
                       error = conditionMessage)
  expect_equal(sub("^edit op 1: ", "", op_msg), rows_msg)
})

test_that("a failing target in a list is named by its position", {
  p <- fix_agency_plan()
  expect_error(match_rows(p, list(list(channel = "Streaming"),
                                  list(channel = "Radio"))),
               "target 2: no such value")
})

test_that("strict = FALSE lets an absent value match nothing", {
  p <- fix_agency_plan()
  expect_equal(match_rows(p, list(channel = c("Streaming", "Radio")),
                          strict = FALSE),
               p@data$channel == "Streaming")
  expect_false(any(match_rows(p, list(channel = "Radio"), strict = FALSE)))
  expect_false(any(match_rows(p, list(channel = "Streaming"), strict = FALSE,
                              during = list(from = "2028-01-01",
                                            to = "2028-01-31"))))
  # a typo in a column is still a typo
  expect_error(match_rows(p, list(chanel = "Streaming"), strict = FALSE),
               "may only name grain columns")
})

test_that("match_rows names the rows build_scenario() edits", {
  p <- fix_agency_plan()
  target <- list(partner = "DSP A")
  s <- build_scenario(p, op_set(12345, target = target, during = q1()),
                      name = "probe")
  edited <- s@data$planned_spend != p@data$planned_spend
  expect_equal(match_rows(p, target, during = q1()), edited)

  # and the rows a transfer's sides take, each through its own window
  op <- op_transfer(1000, from = list(channel = "Streaming"),
                    to = list(partner = "Video A", tactic = "Prospecting"),
                    from_during = q1(),
                    to_during = list(from = "2026-10-01", to = "2026-12-31"))
  s <- build_scenario(p, op, name = "probe")
  moved <- s@data$planned_spend != p@data$planned_spend
  expect_equal(moved,
               (match_rows(p, op$from, op$from_during) |
                  match_rows(p, op$to, op$to_during)) &
                 # the committed upfront cannot give, so it does not move
                 p@data$tactic != "Upfront")
})

test_that("match_rows reads rows a subplan owns; an edit refuses them", {
  topline <- std_plan("Q3 topline")
  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50)),
    grain = c("channel", "partner"), time = "week", name = "TV detail")
  p <- attach_subplan(topline, tv)
  expect_equal(match_rows(p, list(channel = "TV")), p@data$channel == "TV")
  expect_error(build_scenario(p, op_scale(2, list(channel = "TV")), name = "x"),
               "planned in a subplan")
})

test_that("match_rows refuses what is not a target", {
  p <- fix_agency_plan()
  expect_error(match_rows(p, "Streaming"), "must be a target")
  expect_error(match_rows(p, data.frame(channel = "Streaming")),
               "must be a target")
  expect_error(match_rows(p, list(channel = "Streaming", list(partner = "x"))),
               "must be a target")
  expect_error(match_rows(p, list(), strict = NA), "TRUE or FALSE")
  expect_error(match_rows(list(), list()), "must be a MediaPlan")
})

# ---- assign_sections -------------------------------------------------------------

agency_leaves <- function() {
  list(Streaming    = list(channel = "Streaming"),
       Programmatic = list(channel = "Programmatic"),
       Video        = list(channel = "Online Video"))
}

test_that("a clean partition puts every line item in one section", {
  p <- fix_agency_plan()
  a <- assign_sections(p, agency_leaves())
  expect_s3_class(a, "data.frame")
  expect_named(a, c("line_item", "section", "n_matches"))
  expect_equal(nrow(a), 9)
  expect_true(all(a$n_matches == 1L))
  expect_equal(a$section[a$line_item == "Programmatic | DSP B | Promo | Prospecting"],
               "Programmatic")
  expect_equal(nrow(attr(a, "overlaps")), 0)
  expect_length(attr(a, "unmatched"), 0)
  expect_output(print(a), "Every line item is in exactly one section")
})

test_that("an overlap is reported, not refused", {
  p <- fix_agency_plan()
  leaves <- c(agency_leaves(),
              list(Retargeting = list(partner = "DSP A", tactic = "Retargeting")))
  a <- assign_sections(p, leaves)
  li <- "Programmatic | DSP A | Promo | Retargeting"
  expect_equal(a$n_matches[a$line_item == li], 2L)
  expect_true(is.na(a$section[a$line_item == li]))
  expect_equal(attr(a, "overlaps"),
               data.frame(line_item = li, sections = "Programmatic, Retargeting"))
  expect_output(print(a), "1 in more than one section \\(Programmatic \\| DSP A")
})

test_that("an unmatched line item is reported, not refused", {
  p <- fix_agency_plan()
  leaves <- agency_leaves()
  leaves$Video <- list(partner = "Video A")
  a <- assign_sections(p, leaves)
  li <- "Online Video | Video B | Promo | Regional"
  expect_equal(attr(a, "unmatched"), li)
  expect_equal(a$n_matches[a$line_item == li], 0L)
  expect_true(is.na(a$section[a$line_item == li]))
  expect_output(print(a), "1 in none \\(Online Video \\| Video B")
})

test_that("a section may be a list of targets, and name values the plan lacks", {
  p <- fix_agency_plan()
  a <- assign_sections(p, list(
    Brand       = list(list(channel = "Streaming"), list(channel = "Online Video"),
                       list(channel = "Linear TV")),
    Performance = list(channel = c("Programmatic", "Search"))
  ))
  expect_true(all(a$n_matches == 1L))
  expect_equal(sum(a$section == "Brand"), 6)
})

test_that("assign_sections refuses a malformed tree, and a column not in the grain", {
  p <- fix_agency_plan()
  expect_error(assign_sections(p, list(list(channel = "Streaming"))),
               "named list")
  expect_error(assign_sections(p, list(A = list(channel = "Streaming"),
                                       A = list(channel = "Programmatic"))),
               "distinct names")
  expect_error(assign_sections(p, list(Brand = list(funnel = "Brand"))),
               "section 'Brand': `target` may only name grain columns")
})

# ---- ops_within ------------------------------------------------------------------

brand <- function() list(channel = c("Streaming", "Online Video"))
dsp_a_items <- function() c("Programmatic | DSP A | Brand | Prospecting",
                            "Programmatic | DSP A | Promo | Retargeting")

test_that("each one-target op is inside or outside its scope", {
  p <- fix_agency_plan()
  makers <- list(
    set        = function(t) op_set(1000, target = t),
    scale      = function(t) op_scale(1.1, target = t),
    delta      = function(t) op_delta(-1000, target = t),
    delta_each = function(t) op_delta_each(-10, target = t),
    total      = function(t) op_total(50000, target = t),
    rebound    = function(t) op_rebound(max = 1e6, target = t),
    drop       = function(t) op_drop(target = t)
  )
  for (key in names(makers)) {
    inside <- ops_within(p, makers[[key]](list(partner = "Stream B")), brand())
    expect_equal(nrow(inside), 0, info = key)
    expect_named(inside, c("op", "side", "line_items"))

    out <- ops_within(p, makers[[key]](list(partner = "DSP A")), brand())
    expect_equal(nrow(out), 1, info = key)
    expect_equal(out$op, 1L, info = key)
    expect_equal(out$side, "target", info = key)
    expect_equal(out$line_items[[1]], dsp_a_items(), info = key)
  }
})

test_that("an op with no target reaches the whole plan", {
  p <- fix_agency_plan()
  # build_scenario() would refuse this at the committed upfront; the scope
  # answer is given regardless
  out <- ops_within(p, op_scale(1.05), brand())
  expect_equal(out$side, "target")
  expect_length(out$line_items[[1]], 3)   # the three Programmatic line items
})

test_that("shift and restage are inside or outside their scope", {
  buys <- data.frame(
    channel = c("TV", "Search"), partner = c("NBC", "Google"),
    flight_start = as.Date(c("2026-07-06", "2026-07-06")),
    flight_end   = as.Date(c("2026-07-26", "2026-07-26")),
    planned_spend = c(300, 90))
  p <- media_plan_from_flights(buys, grain = c("channel", "partner"),
                               name = "flights")
  tv <- list(channel = "TV")
  expect_equal(nrow(ops_within(p, op_shift(7, list(channel = "TV")), tv)), 0)
  expect_equal(ops_within(p, op_shift(7, list(channel = "Search")), tv)$side,
               "target")
  expect_equal(nrow(ops_within(p, op_restage("2026-08-03", "2026-08-23",
                                             list(partner = "NBC")), tv)), 0)
  out <- ops_within(p, op_restage("2026-08-03", "2026-08-23",
                                  list(partner = "Google")), tv)
  expect_equal(out$line_items[[1]], "Search | Google")
})

test_that("a transfer with one side outside reports that side only", {
  p <- fix_agency_plan()
  inside <- op_transfer(5000, from = list(partner = "Stream B"),
                        to = list(partner = "Video A", tactic = "Prospecting"))
  expect_equal(nrow(ops_within(p, inside, brand())), 0)

  raid <- op_transfer(5000, from = list(partner = "DSP A"),
                      to = list(partner = "Stream B"))
  out <- ops_within(p, raid, brand())
  expect_equal(out$side, "from")
  expect_equal(out$line_items[[1]], dsp_a_items())

  give <- op_transfer(5000, from = list(partner = "Stream B"),
                      to = list(channel = "Programmatic"))
  expect_equal(ops_within(p, give, brand())$side, "to")
})

test_that("an add outside the scope is reported", {
  p <- fix_agency_plan()
  audio <- op_add(channel = "Audio", partner = "Pod A", campaign = "Brand",
                  tactic = "Prospecting", month = "2027-01-01",
                  planned_spend = 5000)
  out <- ops_within(p, audio, brand())
  expect_equal(out$side, "add")
  expect_equal(out$line_items[[1]], "Audio | Pod A | Brand | Prospecting")
  # the same line item, inside a scope that names a channel the plan lacks
  expect_equal(nrow(ops_within(p, audio, list(channel = c("Streaming", "Audio")))), 0)
})

test_that("an add then an op on the added row is inside", {
  p <- fix_agency_plan()
  ops <- list(
    op_add(channel = "Streaming", partner = "Stream C", campaign = "Brand",
           tactic = "Prospecting", month = "2027-01-01", planned_spend = 0),
    op_transfer(5000, from = list(partner = "Stream B"),
                to = list(partner = "Stream C"))
  )
  expect_equal(nrow(ops_within(p, ops, brand())), 0)
  # out of order, the second op names a partner that does not exist yet
  expect_error(ops_within(p, rev(ops), brand()),
               "edit op 1: `to`: no such value\\(s\\) in 'partner': Stream C")
})

test_that("a drop after the rebound that frees it is applied in order", {
  p <- fix_agency_plan()
  ops <- list(op_rebound(min = NA, target = list(partner = "DSP B")),
              op_drop(target = list(partner = "DSP B")))
  perf <- list(channel = "Programmatic")
  expect_equal(nrow(ops_within(p, ops, perf)), 0)
  expect_error(ops_within(p, ops[2], perf), "would remove row\\(s\\) with a floor")
})

test_that("from_during narrows the source side", {
  p <- fix_agency_plan()
  # Brand is scoped by channel and Q1; Q4 rows are outside it
  scope <- list(channel = c("Streaming", "Online Video"),
                month = c("2027-01-01", "2027-02-01", "2027-03-01"))
  ok <- op_transfer(5000, from = list(partner = "Stream B"),
                    to = list(partner = "Video A", tactic = "Prospecting"),
                    during = q1())
  expect_equal(nrow(ops_within(p, ok, scope)), 0)

  early <- op_transfer(5000, from = list(partner = "Stream B"),
                       to = list(partner = "Video A", tactic = "Prospecting"),
                       from_during = list(from = "2026-12-01", to = "2026-12-31"),
                       to_during = q1())
  out <- ops_within(p, early, scope)
  expect_equal(out$side, "from")
  expect_equal(out$line_items[[1]], c("Streaming | Stream B | Brand | Prospecting",
                                      "Streaming | Stream B | Promo | Regional"))
})

test_that("ops_within takes ops from JSON and from a stored record", {
  p <- fix_agency_plan()
  json <- jsonlite::fromJSON(
    '[{"transfer": 5000, "from": {"partner": "DSP A"}, "to": {"partner": "Stream B"}},
      {"scale": 1.1, "target": {"partner": ["Stream B"]}}]',
    simplifyVector = FALSE)
  out <- ops_within(p, json, brand())
  expect_equal(out$op, 1L)
  expect_equal(out$side, "from")

  s <- build_scenario(p, json, name = "draft")
  expect_equal(ops_within(p, s@edits, brand()), out)
})

test_that("ops_within refuses an allocation and a missing scope", {
  p <- fix_agency_plan()
  expect_error(ops_within(p, c("x" = 1), brand()), "checks operations")
  expect_error(ops_within(p, op_scale(2)), "`scope` is required")
  expect_error(ops_within(p, op_scale(2), list(funnel = "Brand")),
               "`scope`: `target` may only name grain columns")
})

# ---- rebase_check ----------------------------------------------------------------

# A Brand draft: money from Stream B into Video A prospecting, in Q1.
brand_draft <- function() {
  op_transfer(10000, from = list(partner = "Stream B"),
              to = list(partner = "Video A", tactic = "Prospecting"),
              during = q1())
}

test_that("a sibling section changed in between is clean", {
  base <- fix_agency_plan()
  current <- build_scenario(
    base, op_transfer(5000, from = list(partner = "DSP B"),
                      to = list(partner = "DSP A", tactic = "Prospecting"),
                      during = q1()),
    name = "Rev 2")
  out <- rebase_check(base, current, brand_draft())
  expect_equal(nrow(out), 0)
  expect_named(out, c("op", "side", "row", "issue", "columns", "base_spend",
                      "current_spend"))
  # and so the replay does to those rows what the draft did
  draft    <- build_scenario(base, brand_draft(), name = "draft")
  replayed <- build_scenario(current, draft@edits$ops, name = "Rev 3")
  touched  <- match_rows(base, list(channel = c("Streaming", "Online Video")))
  expect_equal(replayed@data$planned_spend[touched],
               draft@data$planned_spend[touched])
})

test_that("the same rows changed in between are reported", {
  base <- fix_agency_plan()
  current <- build_scenario(base, op_scale(0.9, list(partner = "Stream B"),
                                           during = q1()),
                            name = "Rev 2")
  out <- rebase_check(base, current, brand_draft())
  expect_equal(nrow(out), 6)   # Stream B's two line items, three months
  expect_true(all(out$issue == "changed"))
  expect_true(all(out$side == "from"))
  expect_true(all(out$columns == "planned_spend"))
  expect_equal(out$current_spend, round(out$base_spend * 0.9, 6))
  row <- "Streaming | Stream B | Brand | Prospecting | 2027-01-01"
  expect_true(row %in% out$row)
})

test_that("a changed bound under the target is reported", {
  base <- fix_agency_plan()
  current <- build_scenario(
    base, op_rebound(max = 50000, target = list(partner = "Video A",
                                                tactic = "Prospecting"),
                     during = q1()),
    name = "Rev 2")
  out <- rebase_check(base, current, brand_draft())
  expect_true(all(out$side == "to"))
  expect_true(all(out$columns == "max_spend"))
  expect_equal(nrow(out), 3)
})

test_that("a row added under the ops' target on current is reported", {
  base <- fix_agency_plan()
  current <- build_scenario(
    base, op_add(channel = "Streaming", partner = "Stream B", campaign = "Brand",
                 tactic = "Retargeting", month = "2027-02-01",
                 planned_spend = 8000),
    name = "Rev 2")
  out <- rebase_check(base, current, brand_draft())
  expect_equal(out$issue, "current only")
  expect_equal(out$row, "Streaming | Stream B | Brand | Retargeting | 2027-02-01")
  expect_true(is.na(out$base_spend))
  expect_equal(out$current_spend, 8000)
})

test_that("a row gone from current is reported as base only", {
  base <- fix_agency_plan()
  current <- build_scenario(
    base, op_drop(list(partner = "Stream B", campaign = "Promo")), name = "Rev 2")
  out <- rebase_check(base, current, brand_draft())
  expect_equal(unique(out$issue), "base only")
  expect_equal(nrow(out), 3)
})

test_that("ops are resolved in order on both plans", {
  base <- fix_agency_plan()
  add_c <- op_add(channel = "Streaming", partner = "Stream C",
                  campaign = "Brand", tactic = "Prospecting",
                  month = "2027-01-01", planned_spend = 0)
  ops <- list(add_c, op_transfer(5000, from = list(partner = "Stream B"),
                                 to = list(partner = "Stream C"), during = q1()))
  sibling <- build_scenario(base, op_scale(1.1, list(channel = "Programmatic")),
                            name = "Rev 2")
  expect_equal(nrow(rebase_check(base, sibling, ops)), 0)

  # current already has the row the draft adds: the replay would fail
  clash <- build_scenario(base, add_c, name = "Rev 2")
  expect_error(rebase_check(base, clash, ops),
               "cannot be replayed on `current`: edit op 1: the plan already has")
})

test_that("rebase_check takes the draft's own record", {
  base <- fix_agency_plan()
  current <- build_scenario(base, op_scale(0.9, list(partner = "Stream B")),
                            name = "Rev 2")
  draft <- build_scenario(base, brand_draft(), name = "draft")
  expect_equal(rebase_check(base, current, draft@edits),
               rebase_check(base, current, brand_draft()))
})

test_that("rebase_check refuses plans of different grains", {
  base <- fix_agency_plan()
  other <- roll_up(base, c("channel", "partner"))
  expect_error(rebase_check(base, other, brand_draft()), "must share a grain")
})
