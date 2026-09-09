# Structure views: what hangs beneath a plan, and where a plan came from.
#
# Two different questions on two different objects. Subplan STRUCTURE lives
# inside one plan -- a tree hanging off @subplans. LINEAGE lives across plans --
# @parent_id edges -- and only becomes a drawable graph inside a registry, which
# is what a ScenarioSet is.
#
# Everything here is a PROJECTION, in the same sense as compare_scenarios() and
# calendarize(): data shaped for someone else to render, plus a console tree
# because print's job is to be read. No graphics dependency; a companion
# package or an app draws from subplan_map() and lineage() rather than
# rebuilding them by hand and drifting.

# Box-drawing glyphs for the console tree, as escapes so the source stays ASCII.
.box <- list(tee = "\u251c\u2500 ", end = "\u2514\u2500 ", bar = "\u2502  ",
             dot = " \u00b7 ")

# A plan's cadence in one word, for structure views. Flights report their
# basis; weekly rows with no flight identity are simply weekly.
.cadence <- function(plan) {
  if (!length(plan@week_col)) return("timeless")
  fl <- flights(plan)
  if (nrow(fl)) {
    b <- unique(fl[["period_basis"]])
    if (length(b) == 1L) {
      return(switch(b, day = "daily", week = "weekly", month = "monthly",
                    "flighted"))
    }
    return("flighted")
  }
  "weekly"
}

# Distinct line items, ignoring time and flight bookkeeping.
.n_line_items <- function(plan) {
  d  <- plan@data
  li <- setdiff(line_item_grain(plan), flight_cols())
  if (!nrow(d)) return(0L)
  if (!length(li)) return(nrow(d))
  length(unique(line_item(d, li)))
}

# ---- subplan_map ---------------------------------------------------------------

#' The subplan tree as a table
#'
#' One row per plan in the tree — the plan itself at depth 0, then every
#' subplan in pre-order, each with the cell it backs, its depth, and the facts
#' a viewer needs to draw or list it. This is the projection a UI builds a tree
#' from; [plan_tree()] and [plan_mermaid()] are two renderings of it.
#'
#' @param plan A [MediaPlan].
#' @return A data frame with one row per plan in the tree:
#'   \describe{
#'     \item{`depth`}{0 for `plan`, 1 for its subplans, and so on.}
#'     \item{`key`}{The parent cell this plan backs (`"TV"`, `"TV | NBC"`);
#'       `NA` for the root.}
#'     \item{`path`}{Keys from the root joined with `" > "`; `""` for the root.}
#'     \item{`name`, `nickname`, `status`, `revision`, `id`}{The plan's own.}
#'     \item{`grain`}{Its grain columns joined with `" + "`.}
#'     \item{`cadence`}{`"timeless"`, `"weekly"`, `"daily"`, `"monthly"` or
#'       `"flighted"`, read off the data.}
#'     \item{`line_items`, `rows`, `spend`}{Its size.}
#'     \item{`subplans`}{How many it holds directly.}
#'   }
#' @examples
#' topline <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(100, 40)),
#'   grain = "channel", name = "Q3 topline"
#' )
#' tv <- media_plan_from_df(
#'   data.frame(channel = "TV", partner = c("NBC", "ESPN"),
#'              planned_spend = c(70, 50)),
#'   grain = c("channel", "partner"), name = "TV detail"
#' )
#' subplan_map(attach_subplan(topline, tv))
#' @seealso [plan_tree()], [plan_mermaid()], [attach_subplan()]
#' @export
subplan_map <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  out <- do.call(rbind, .map_rows(plan, NA_character_, "", 0L))
  rownames(out) <- NULL
  out
}

.map_rows <- function(plan, key, path, depth) {
  own <- data.frame(
    depth      = depth,
    key        = key,
    path       = path,
    name       = plan@name,
    nickname   = plan@nickname,
    grain      = paste(plan@grain, collapse = " + "),
    cadence    = .cadence(plan),
    line_items = .n_line_items(plan),
    rows       = nrow(plan@data),
    spend      = sum(plan@data[["planned_spend"]]),
    subplans   = length(plan@subplans),
    revision   = plan@revision,
    status     = plan@status,
    id         = plan@id,
    stringsAsFactors = FALSE
  )
  kids <- lapply(names(plan@subplans), function(k) {
    .map_rows(plan@subplans[[k]], k,
              if (nzchar(path)) paste(path, k, sep = " > ") else k,
              depth + 1L)
  })
  c(list(own), unlist(kids, recursive = FALSE))
}

# ---- plan_tree -----------------------------------------------------------------

#' Print a plan's subplan tree
#'
#' The console view of [subplan_map()]: the plan on the first line, each
#' subplan beneath the cell it backs, and — under any plan that holds subplans
#' — an `(editable)` line for the cells no subplan owns. It answers the
#' planner's question, *what is locked, and who owns it?*, without leaving R.
#'
#' @param plan A [MediaPlan].
#' @return The printed lines, invisibly, as a character vector.
#' @examples
#' topline <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(100, 40)),
#'   grain = "channel", name = "Q3 topline"
#' )
#' tv <- media_plan_from_df(
#'   data.frame(channel = "TV", partner = c("NBC", "ESPN"),
#'              planned_spend = c(70, 50)),
#'   grain = c("channel", "partner"), name = "TV detail"
#' )
#' plan_tree(attach_subplan(topline, tv))
#' @seealso [subplan_map()], [plan_mermaid()]
#' @export
plan_tree <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  rows <- do.call(rbind, .tree_rows(plan, prefix = "", root = TRUE))

  # Uniform columns: label, name, cadence, size, spend. Empty cells collapse
  # so a flat plan prints as one clean line.
  w <- vapply(rows[c("label", "name", "cadence", "size")], function(col) {
    max(nchar(col))
  }, numeric(1))
  lines <- vapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i, ]
    mid <- paste(c(formatC(r$name,    width = -w[["name"]]),
                   formatC(r$cadence, width = -w[["cadence"]]),
                   formatC(r$size,    width = -w[["size"]])), collapse = "  ")
    sub("\\s+$", "", paste0(formatC(r$label, width = -w[["label"]]), "  ",
                            mid, "  ",
                            formatC(r$spend, width = max(nchar(rows$spend)))))
  }, character(1))
  cat(lines, sep = "\n")
  invisible(lines)
}

# One row per printed line, recursing with the box-drawing prefix.
.tree_rows <- function(plan, prefix, root = FALSE, key = NULL, last = TRUE) {
  hdr <- if (root) {
    h <- plan@name
    if (nzchar(plan@nickname)) h <- paste0(h, ' ("', plan@nickname, '")')
    if (plan@revision > 1L) h <- paste0(h, "  Rev ", plan@revision)
    if (nzchar(plan@status)) h <- paste0(h, "  [", plan@status, "]")
    h
  } else {
    paste0(prefix, if (last) .box$end else .box$tee, key)
  }
  n_li <- .n_line_items(plan)
  own <- data.frame(
    label   = hdr,
    name    = if (root) "" else plan@name,
    cadence = if (root) "" else .cadence(plan),
    size    = if (root) "" else paste(n_li, if (n_li == 1L) "line item" else "line items"),
    spend   = .fmt_num(sum(plan@data[["planned_spend"]])),
    stringsAsFactors = FALSE
  )
  if (!length(plan@subplans)) return(list(own))

  child_prefix <- if (root) "" else paste0(prefix, if (last) "   " else .box$bar)
  keys <- names(plan@subplans)
  kids <- lapply(seq_along(keys), function(i) {
    .tree_rows(plan@subplans[[i]], child_prefix, key = keys[i], last = FALSE)
  })

  # The cells nobody owns: what a planner can still edit at this level.
  d    <- plan@data
  free <- !.backed_rows(plan)
  li   <- setdiff(line_item_grain(plan), flight_cols())
  n_free <- if (!any(free)) 0L else if (length(li)) {
    length(unique(line_item(d[free, , drop = FALSE], li)))
  } else sum(free)
  editable <- data.frame(
    label   = paste0(child_prefix, .box$end, "(editable)"),
    name    = "",
    cadence = "",
    size    = paste(n_free, if (n_free == 1L) "line item" else "line items"),
    spend   = .fmt_num(sum(d[["planned_spend"]][free])),
    stringsAsFactors = FALSE
  )
  c(list(own), unlist(kids, recursive = FALSE), list(editable))
}

# ---- ownership_map -------------------------------------------------------------

#' Who owns each cell of a plan
#'
#' One row per line item per period — the plan's own rows, labelled with the
#' subplan that owns each one. A cell backed by a subplan is **locked** on this
#' plan: its number is the subplan's rollup and every edit door refuses it. The
#' rest are the plan's own, editable here. This is the projection behind an
#' ownership grid — line items across, weeks down, coloured by owner — and the
#' planner's answer to *where can I still change things?*
#'
#' Ownership is one level deep by construction: a cell belongs to the subplan
#' attached *here*, whatever that subplan holds beneath it. Ask the subplan for
#' its own map.
#'
#' @param plan A [MediaPlan].
#' @return A data frame with the plan's line item columns, its week column
#'   when it has one, and:
#'   \describe{
#'     \item{`key`}{The line item, as [line_item()] names it.}
#'     \item{`owner`}{The subplan key that owns the cell; `NA` when the plan
#'       does.}
#'     \item{`owner_name`}{That subplan's `@name`; `NA` when the plan owns it.}
#'     \item{`locked`}{`TRUE` when a subplan owns the cell.}
#'     \item{`planned_spend`}{The cell's spend.}
#'   }
#'   Ordered by period, then line item.
#' @examples
#' topline <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(100, 40)),
#'   grain = "channel", name = "Q3 topline"
#' )
#' tv <- media_plan_from_df(
#'   data.frame(channel = "TV", partner = c("NBC", "ESPN"),
#'              planned_spend = c(70, 50)),
#'   grain = c("channel", "partner"), name = "TV detail"
#' )
#' ownership_map(attach_subplan(topline, tv))
#' @seealso [subplan_map()], [attach_subplan()]
#' @export
ownership_map <- function(plan) {
  if (!S7::S7_inherits(plan, MediaPlan)) {
    stop("`plan` must be a MediaPlan.", call. = FALSE)
  }
  d  <- plan@data
  li <- setdiff(line_item_grain(plan), flight_cols())
  wk <- plan@week_col
  if (!length(li)) {
    stop("the plan's grain is only its time column, so there are no line ",
         "items to own.", call. = FALSE)
  }
  key   <- line_item(d, li)
  subs  <- plan@subplans
  owner <- ifelse(key %in% names(subs), key, NA_character_)

  out <- d[, c(li, wk), drop = FALSE]
  out[["key"]]        <- key
  out[["owner"]]      <- owner
  out[["owner_name"]] <- vapply(owner, function(k) {
    if (is.na(k)) NA_character_ else subs[[k]]@name
  }, character(1), USE.NAMES = FALSE)
  out[["locked"]]        <- !is.na(owner)
  out[["planned_spend"]] <- d[["planned_spend"]]

  ord <- if (length(wk)) order(out[[wk]], key) else order(key)
  out <- out[ord, , drop = FALSE]
  rownames(out) <- NULL
  out
}

# ---- lineage -------------------------------------------------------------------

#' The derivation tree of a scenario set
#'
#' Each scenario records the plan it was derived from in `@parent_id`; a
#' [ScenarioSet] is where enough of those plans sit together for the edges to
#' be drawn. One row per scenario, pointing at its parent **within the set**
#' and carrying what changed against it. A scenario whose parent is not in the
#' set is a root here — lineage as far as the set records it.
#'
#' The baseline is not privileged: [compare_scenarios()] measures every
#' scenario against the baseline, this measures each against the plan it
#' actually came from. On a set built by deriving from the base they agree; on
#' a chain — base, a scenario from it, a scenario from *that* — they do not,
#' and this is the one that reads as a tree.
#'
#' @param set A [ScenarioSet].
#' @return A data frame with one row per scenario:
#'   \describe{
#'     \item{`scenario`, `id`, `parent_id`}{Its label and identity.}
#'     \item{`parent`}{The label of its parent in the set; `NA` for a root.}
#'     \item{`depth`}{0 for a root, parent's depth + 1 otherwise.}
#'     \item{`status`, `revision`, `spend`}{The scenario's own.}
#'     \item{`spend_vs_parent`, `spend_pct_vs_parent`}{Against its parent;
#'       `NA` for a root.}
#'   }
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "base"
#' )
#' s1  <- build_scenario(base, c(Search = 60), name = "Search up")
#' s2  <- build_scenario(s1, c(TV = 70), name = "and TV down")
#' set <- add_scenario(add_scenario(scenario_set(base), s1), s2)
#' lineage(set)
#' @seealso [plan_mermaid()], [compare_scenarios()]
#' @export
lineage <- function(set) {
  if (!S7::S7_inherits(set, ScenarioSet)) {
    stop("`set` must be a ScenarioSet.", call. = FALSE)
  }
  scen <- set@scenarios
  nms  <- names(scen)
  ids  <- vapply(scen, function(p) p@id, character(1))
  pids <- vapply(scen, function(p) {
    if (length(p@parent_id) && nzchar(p@parent_id[1])) p@parent_id[1] else NA_character_
  }, character(1))
  parent <- nms[match(pids, ids)]
  spend  <- vapply(scen, function(p) sum(p@data[["planned_spend"]]), numeric(1))
  pspend <- spend[match(parent, nms)]

  # Depth by walking up: roots first, then whoever's parent is placed. Ids are
  # unique and a parent is minted before its child, so this terminates.
  depth <- rep(NA_integer_, length(nms))
  depth[is.na(parent)] <- 0L
  repeat {
    pd <- depth[match(parent, nms)]
    i  <- which(is.na(depth) & !is.na(pd))
    if (!length(i)) break
    depth[i] <- pd[i] + 1L
  }

  out <- data.frame(
    scenario  = nms,
    id        = unname(ids),
    parent_id = unname(pids),
    parent    = parent,
    depth     = depth,
    status    = vapply(scen, function(p) p@status, character(1)),
    revision  = vapply(scen, function(p) p@revision, integer(1)),
    spend     = unname(spend),
    spend_vs_parent = unname(spend - pspend),
    stringsAsFactors = FALSE
  )
  out$spend_pct_vs_parent <- ifelse(!is.na(pspend) & pspend != 0,
                                    out$spend_vs_parent / pspend, NA_real_)
  rownames(out) <- NULL
  out
}

# ---- plan_mermaid ------------------------------------------------------------

#' A plan's structure, or a set's lineage, as a Mermaid diagram
#'
#' Emits a Mermaid `graph` definition as a single string. For a [MediaPlan]
#' the nodes are the plans in its subplan tree and the edges are labelled with
#' the cell each subplan backs; for a [ScenarioSet] the nodes are the
#' scenarios and each edge carries the spend change against the parent it was
#' derived from. No graphics dependency: the string renders wherever Mermaid
#' does — a GitHub README, Quarto, Shiny, a notebook.
#'
#' @param x A [MediaPlan] or a [ScenarioSet].
#' @param direction Mermaid layout direction; `"TD"` (default) or `"LR"`.
#' @return A single string. `cat()` it, or pass it to a Mermaid renderer.
#' @examples
#' base <- media_plan_from_df(
#'   data.frame(channel = c("TV", "Search"), planned_spend = c(80, 40)),
#'   grain = "channel", name = "base"
#' )
#' s1  <- build_scenario(base, c(Search = 60), name = "Search up")
#' cat(plan_mermaid(add_scenario(scenario_set(base), s1)))
#' @seealso [subplan_map()], [lineage()]
#' @export
plan_mermaid <- function(x, direction = c("TD", "LR")) {
  direction <- match.arg(direction)
  if (S7::S7_inherits(x, MediaPlan)) {
    m   <- subplan_map(x)
    ids <- paste0("n", seq_len(nrow(m)))
    lab <- paste0(.mm_esc(m$name), "<br/>", .fmt_num(m$spend), .box$dot,
                  m$cadence,
                  ifelse(nzchar(m$status), paste0(.box$dot, m$status), ""))
    nodes <- paste0("  ", ids, "[\"", lab, "\"]")
    # Pre-order: a row's parent is the nearest earlier row one level up.
    edges <- character(0)
    for (i in seq_len(nrow(m))[-1]) {
      p <- max(which(m$depth[seq_len(i - 1L)] == m$depth[i] - 1L))
      edges <- c(edges, paste0("  ", ids[p], " -->|", .mm_edge(m$key[i]), "| ",
                               ids[i]))
    }
  } else if (S7::S7_inherits(x, ScenarioSet)) {
    l   <- lineage(x)
    ids <- paste0("n", seq_len(nrow(l)))
    lab <- paste0(.mm_esc(l$scenario), "<br/>", .fmt_num(l$spend),
                  ifelse(nzchar(l$status), paste0(.box$dot, l$status), ""))
    nodes <- paste0("  ", ids, "[\"", lab, "\"]")
    is_base <- l$scenario == x@base_name
    nodes[is_base] <- paste0(nodes[is_base], ":::base")
    has_p <- !is.na(l$parent)
    edge_lab <- ifelse(is.na(l$spend_pct_vs_parent),
                       .fmt_delta_vec(l$spend_vs_parent),
                       sprintf("%s (%s%.0f%%)", .fmt_delta_vec(l$spend_vs_parent),
                               ifelse(l$spend_pct_vs_parent >= 0, "+", "-"),
                               abs(l$spend_pct_vs_parent) * 100))
    edges <- paste0("  ", ids[match(l$parent[has_p], l$scenario)],
                    " -->|", edge_lab[has_p], "| ", ids[has_p])
    nodes <- c(nodes, "  classDef base stroke-width:3px")
  } else {
    stop("`x` must be a MediaPlan or a ScenarioSet.", call. = FALSE)
  }
  paste(c(paste("graph", direction), nodes, edges), collapse = "\n")
}

# Quotes end a Mermaid node label; everything else is fine inside one. An edge
# label is delimited by pipes, so a key like "TV | NBC" needs its pipe encoded.
.mm_esc  <- function(s) gsub("\"", "#quot;", s, fixed = TRUE)
.mm_edge <- function(s) gsub("|", "#124;", .mm_esc(s), fixed = TRUE)

.fmt_delta_vec <- function(x) vapply(x, .fmt_delta, character(1))
