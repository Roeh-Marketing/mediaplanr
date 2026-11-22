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
