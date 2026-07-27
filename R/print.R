# Print methods for the S7 classes. Registered for the base `print` generic via
# S7::methods_register() in .onLoad().

.fmt_num <- function(x) {
  formatC(x, format = "f", big.mark = ",", digits = 0)
}

#' @name print
#' @title Print methods for mediaplanr objects
#' @param x The object to print.
#' @param ... Ignored.
#' @return `x`, invisibly.
NULL

S7::method(print, MediaPlan) <- function(x, ...) {
  cat(sprintf("<MediaPlan> %s  (%s)\n",
              if (nzchar(x@name)) x@name else "<unnamed>", short_id(x@id)))
  cat("  grain:  ", paste(x@grain, collapse = " + "), "\n", sep = "")
  cat("  cells:  ", nrow(x@data), "\n", sep = "")
  cat("  spend:  ", .fmt_num(sum(x@data[["planned_spend"]])),
      " planned\n", sep = "")
  if (length(x@parent_id) && nzchar(x@parent_id)) {
    cat("  parent: ", short_id(x@parent_id), "\n", sep = "")
  }
  if (nzchar(x@objective)) cat("  objective: ", x@objective, "\n", sep = "")
  utils::str(x@data, max.level = 1, give.attr = FALSE, no.list = TRUE,
             vec.len = 2, nchar.max = 40)
  invisible(x)
}

S7::method(print, ScenarioSet) <- function(x, ...) {
  cat(sprintf("<ScenarioSet>  (%s)\n", short_id(x@id)))
  cat("  grain:     ", paste(x@grain, collapse = " + "), "\n", sep = "")
  cat("  scenarios: ", length(x@scenarios), "\n", sep = "")
  cmp <- compare_scenarios(x, level = "summary")
  w <- max(nchar(cmp$scenario), 0L)
  for (i in seq_len(nrow(cmp))) {
    star <- if (identical(cmp$scenario[i], x@base_name)) "*" else " "
    dv <- cmp$spend_vs_base[i]
    delta <- if (dv == 0) "" else
      sprintf("  (%s%s vs base)", if (dv > 0) "+" else "-", .fmt_num(abs(dv)))
    cat(sprintf("   %s %-*s  spend %s%s\n",
                star, w, cmp$scenario[i],
                .fmt_num(cmp$total_planned_spend[i]), delta))
  }
  cat("  (* = baseline)\n")
  invisible(x)
}
