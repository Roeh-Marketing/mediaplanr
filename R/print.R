# Print methods for the S7 classes. Registered for the base `print` generic via
# S7::methods_register() in .onLoad().
#
# These are for a human scanning a console, so: one uniform label column, blocks
# ordered from "who/what" to "shape" to "identity", optional fields omitted
# rather than shown empty, and a small data preview instead of a str() dump.

.fmt_num <- function(x) {
  formatC(x, format = "f", big.mark = ",", digits = 0)
}

# Signed number for a delta, e.g. "+1,200" / "-340".
.fmt_delta <- function(x) {
  if (!is.finite(x)) return("")
  paste0(if (x > 0) "+" else if (x < 0) "-" else "", .fmt_num(abs(x)))
}

.trunc <- function(s, n) {
  s <- as.character(s)
  ifelse(nchar(s) > n, paste0(substr(s, 1, n - 3), "..."), s)
}

# A labelled line in the uniform label column.
.field <- function(label, value, width = 12) {
  cat("  ", formatC(label, width = -width), value, "\n", sep = "")
}

#' @name print
#' @title Print methods for mediaplanr objects
#' @param x The object to print.
#' @param ... Ignored.
#' @return `x`, invisibly.
NULL

S7::method(print, MediaPlan) <- function(x, ...) {
  d <- x@data

  # --- header: formal name, working handle, and the status you scan for ---
  hdr <- x@name
  if (length(x@nickname) && nzchar(x@nickname)) {
    hdr <- paste0(hdr, ' ("', x@nickname, '")')
  }
  hdr <- paste0("<MediaPlan> ", .trunc(hdr, 56))
  if (length(x@status) && nzchar(x@status)) {
    hdr <- paste0(hdr, "  [", x@status, "]")
  }
  cat(hdr, "\n", sep = "")

  # --- who / what (omitted entirely when unset) ---
  if (nzchar(x@advertiser)) .field("advertiser", x@advertiser)
  if (nzchar(x@planner))    .field("planner", x@planner)
  if (nzchar(x@objective))  .field("objective", .trunc(x@objective, 62))

  # --- shape ---
  .field("grain", paste(x@grain, collapse = " + "))
  if (length(x@week_col) && nrow(d)) {
    wk <- range(d[[x@week_col]], na.rm = TRUE)
    n_wk <- length(unique(d[[x@week_col]]))
    .field("weeks", paste0(format(wk[1]), " to ", format(wk[2]),
                           "  (", n_wk, if (n_wk == 1) " week)" else " weeks)"))
    .field("line items", length(unique(line_item(d, line_item_grain(x)))))
  }
  .field("rows", nrow(d))
  .field("spend", .fmt_num(sum(d[["planned_spend"]])))

  # --- identity / lineage ---
  ident <- short_id(x@id)
  if (length(x@parent_id) && nzchar(x@parent_id)) {
    ident <- paste0(ident, "   derived from ", short_id(x@parent_id))
  }
  .field("id", ident)

  # --- a short preview of the plan itself ---
  if (nrow(d)) {
    n_show <- min(3L, nrow(d))
    cat("\n")
    prev <- utils::capture.output(print(utils::head(d, n_show), row.names = FALSE))
    cat(paste0("  ", prev, collapse = "\n"), "\n", sep = "")
    if (nrow(d) > n_show) {
      cat("  ... ", nrow(d) - n_show, " more row",
          if (nrow(d) - n_show == 1) "" else "s", "\n", sep = "")
    }
  }
  invisible(x)
}

S7::method(print, ScenarioSet) <- function(x, ...) {
  cmp <- compare_scenarios(x, level = "summary")
  n <- nrow(cmp)

  cat("<ScenarioSet>  ", n, if (n == 1) " scenario" else " scenarios",
      " at ", paste(x@grain, collapse = " + "), "\n", sep = "")

  # The advertiser is a property of the engagement, so show it only when the
  # whole set agrees -- otherwise it would imply a consensus that is not there.
  adv <- unique(vapply(x@scenarios, function(p) p@advertiser, character(1)))
  adv <- adv[nzchar(adv)]
  if (length(adv) == 1) .field("advertiser", adv, width = 12)

  # --- scenario table ---
  lbl <- .trunc(cmp$scenario, 26)
  sts <- vapply(x@scenarios[cmp$scenario], function(p) p@status, character(1))
  sts[!nzchar(sts)] <- "-"
  spend <- .fmt_num(cmp$total_planned_spend)

  vs <- vapply(seq_len(n), function(i) {
    if (identical(cmp$scenario[i], x@base_name)) return("-")
    dv <- cmp$spend_vs_base[i]
    pc <- cmp$spend_pct_vs_base[i]
    if (dv == 0) return("same")
    if (is.na(pc)) return(.fmt_delta(dv))
    sprintf("%s (%s%.0f%%)", .fmt_delta(dv), if (pc > 0) "+" else "-",
            abs(pc) * 100)
  }, character(1))

  w_lbl <- max(nchar(c(lbl, "scenario")))
  w_sts <- max(nchar(c(sts, "status")))
  w_spd <- max(nchar(c(spend, "spend")))
  w_vs  <- max(nchar(c(vs, "vs base")))

  cat("\n  ", "  ", formatC("scenario", width = -w_lbl), "  ",
      formatC("status", width = -w_sts), "  ",
      formatC("spend", width = w_spd), "  ",
      formatC("vs base", width = w_vs), "\n", sep = "")

  for (i in seq_len(n)) {
    mark <- if (identical(cmp$scenario[i], x@base_name)) "* " else "  "
    cat("  ", mark, formatC(lbl[i], width = -w_lbl), "  ",
        formatC(sts[i], width = -w_sts), "  ",
        formatC(spend[i], width = w_spd), "  ",
        formatC(vs[i], width = w_vs), "\n", sep = "")
  }
  cat("\n  * = baseline\n")
  invisible(x)
}
