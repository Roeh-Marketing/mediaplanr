# @spend_basis declares what planned_spend measures -- media net, client net,
# gross. The contract worth pinning: it is a declaration that travels with the
# plan and converts nothing, and plans combine only when theirs match.

net <- function(plan, basis = "media_net") revise(plan, spend_basis = basis)

# ---- declaring it ------------------------------------------------------------

test_that("a plan's basis is undeclared until someone declares it", {
  expect_identical(std_plan()@spend_basis, "")
  p <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", planned_spend = 80),
    grain = "channel", time = "week", name = "p", spend_basis = " client_net ")
  expect_identical(p@spend_basis, "client_net")      # trimmed
})

test_that("media_plan_from_flights() forwards it", {
  p <- media_plan_from_flights(
    data.frame(channel = "TV", flight_start = as.Date("2026-04-06"),
               flight_end = as.Date("2026-04-19"), planned_spend = 1000),
    grain = "channel", name = "p", spend_basis = "gross")
  expect_identical(p@spend_basis, "gross")
})

test_that("revise() corrects the declaration and changes no figure", {
  p <- net(std_plan())
  q <- revise(p, spend_basis = "client_net")
  expect_identical(q@spend_basis, "client_net")
  expect_identical(q@data, p@data)
  expect_identical(q@id, p@id)
  expect_error(revise(p, spend_basis = c("a", "b")), "single string")
})

test_that("scenarios and rollups carry the basis", {
  p <- net(fine_plan())
  expect_identical(build_scenario(p, op_scale(2), name = "s")@spend_basis,
                   "media_net")
  expect_identical(roll_up(p, "channel")@spend_basis, "media_net")
})

# ---- combining plans ---------------------------------------------------------

test_that("a scenario set holds one basis", {
  base <- net(std_plan())
  other <- net(build_scenario(base, op_scale(2), name = "s"), "client_net")
  expect_error(add_scenario(scenario_set(base), other),
               "share one spend basis; got base = \"media_net\", s = \"client_net\".*revise\\(spend_basis = \\)")
  # undeclared is not a wildcard: it does not match a declared basis
  undeclared <- build_scenario(std_plan(), op_scale(2), name = "u")
  expect_error(add_scenario(scenario_set(base), undeclared), "one spend basis")
})

test_that("a subplan must share its parent's basis", {
  tv <- media_plan_from_df(
    data.frame(week = fix_week(), channel = "TV", partner = c("NBC", "ESPN"),
               planned_spend = c(70, 50)),
    grain = c("channel", "partner"), time = "week", name = "TV detail",
    spend_basis = "client_net")
  expect_error(attach_subplan(net(std_plan()), tv),
               "parent's spend basis is \"media_net\" and the subplan's is \"client_net\"")
  expect_no_error(attach_subplan(net(std_plan(), "client_net"), tv))
})

# ---- where it shows ----------------------------------------------------------

test_that("print, describe_plan() and JSON all carry it", {
  p <- net(std_plan())
  expect_match(paste(utils::capture.output(print(p)), collapse = "\n"),
               "spend basis +media_net")
  expect_identical(describe_plan(p)$money$spend_basis, "media_net")
  expect_identical(plan_from_json(plan_to_json(p))@spend_basis, "media_net")
  expect_identical(plan_from_json(plan_to_json(std_plan()))@spend_basis, "")
})
