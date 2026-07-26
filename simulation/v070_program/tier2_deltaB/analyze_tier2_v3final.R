#!/usr/bin/env Rscript
# Tier 2 delta-B re-score under the v0.8.0 FINAL resolved lattice, for
# App D.6. NO re-simulation: reads the banked per-rep draws (delta +
# implied q_hats, run_tier2_deltaB.R, seeds 20260708+) and re-positions
# every rep on the SHIPPED v0.8.0 null via the production functions
# grassr:::lookup_delta_null / grassr:::delta_null_percentile (trilinear
# q/log10N/prev interpolation, k snap, mid-p ties) from the INSTALLED
# grassr 0.8.0 (sysdata v3-resolved-lattice-intdelta; version asserted).
#
# HEADLINE (production semantics): per rep q_hat_panel = median of the
# finite implied q_hats (same statistic as the original analyzer);
# prevalence = the cell's true generating prev (per-rep pi_hat was not
# banked; true prev is the oracle version of production's bridged
# estimate, and tier2 prevs 0.10/0.30 interpolate inside the lattice).
# COMPARISON (*_design): oracle true-q matching, same prev.
# Outputs: results/tier2_deltaB_results_v3final.rds + summary txt.
suppressMessages({library(grassr); library(parallel)})
stopifnot(packageVersion("grassr") == "0.8.0")
nullobj <- get("delta_null_ecdf", asNamespace("grassr"))
stopifnot(identical(nullobj$version, "v3-resolved-lattice-intdelta"))

T2 <- "/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/tier2_deltaB"
PER_CELL <- file.path(T2, "per_cell")
RESULTS  <- file.path(T2, "results")

score_cell <- function(f) {
  x <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(x) || is.null(x$draws)) return(NULL)
  cell <- x$cell; d <- x$draws
  qmat <- cbind(d$q_pabak, d$q_fleiss_kappa, d$q_mean_ac1)
  q_hat <- apply(qmat, 1L, function(z) {
    z <- z[is.finite(z)]; if (length(z)) median(z) else NA_real_ })
  pct <- pct_des <- rep(NA_real_, nrow(d))
  # oracle true-q cell: one lookup for the whole cell
  nc_des <- grassr:::lookup_delta_null(cell$k, cell$N, cell$q, cell$prev)
  if (!is.null(nc_des))
    pct_des <- vapply(d$delta, function(z)
      if (is.finite(z)) grassr:::delta_null_percentile(z, nc_des) else NA_real_,
      numeric(1L))
  # headline: per-rep q_hat lookup (round q_hat to 4dp to pool identical lookups)
  qr <- round(q_hat, 4L)
  for (qv in unique(qr[is.finite(qr)])) {
    nc <- grassr:::lookup_delta_null(cell$k, cell$N, qv, cell$prev)
    if (is.null(nc)) next
    ii <- which(qr == qv & is.finite(d$delta))
    pct[ii] <- vapply(d$delta[ii], grassr:::delta_null_percentile,
                      numeric(1L), cell = nc)
  }
  meta <- cell[rep(1L, nrow(d)), , drop = FALSE]
  out <- cbind(meta, d[c("rep", "delta")], row.names = NULL)
  out$arm <- x$arm
  out$flag95 <- as.numeric(pct >= 95);  out$flag99 <- as.numeric(pct >= 99)
  out$flag95_design <- as.numeric(pct_des >= 95)
  out$flag99_design <- as.numeric(pct_des >= 99)
  out
}

files <- list.files(PER_CELL, pattern = "^arm[ABC]_cell_[0-9]+\\.rds$",
                    full.names = TRUE)
cat("cells:", length(files), "\n")
big <- mclapply(files, score_cell, mc.cores = 8)
bad <- !vapply(big, is.data.frame, logical(1L))
if (any(bad)) {
  cat("FAILED cells:", sum(bad), "\n")
  print(unique(vapply(big[bad], function(z) paste(class(z), collapse="/"), character(1L))))
  stopifnot(!any(bad))
}

rate_tab <- function(df, byvar) {
  lv <- sort(unique(df[[byvar]]))
  res <- do.call(rbind, lapply(lv, function(L) {
    s <- df[df[[byvar]] == L, ]
    data.frame(level = L, n = sum(is.finite(s$flag95)),
               rate_caution = mean(s$flag95, na.rm = TRUE),
               rate_divergent = mean(s$flag99, na.rm = TRUE),
               rate_caution_design = mean(s$flag95_design, na.rm = TRUE),
               rate_divergent_design = mean(s$flag99_design, na.rm = TRUE))
  }))
  names(res)[1] <- byvar
  res
}

lines <- c("== Tier 2 delta-B re-score, v0.8.0 FINAL null (production lookup, mid-p) ==", "")
results <- list()
allA <- do.call(rbind, big[vapply(big, function(z) z$arm[1] == "A", logical(1))])
allB <- do.call(rbind, big[vapply(big, function(z) z$arm[1] == "B", logical(1))])
allC <- do.call(rbind, big[vapply(big, function(z) z$arm[1] == "C", logical(1))])
if (!is.null(allA)) {
  results$armA <- rate_tab(allA, "sd_d")
  lines <- c(lines, "-- Arm A (item difficulty): flag rate by sd_d --",
             capture.output(print(results$armA, row.names = FALSE, digits = 3)), "")
}
if (!is.null(allB)) {
  results$armB <- rate_tab(allB, "rho")
  lines <- c(lines, "-- Arm B (correlated errors): flag rate by rho --",
             capture.output(print(results$armB, row.names = FALSE, digits = 3)), "")
}
if (!is.null(allC)) {
  results$armC <- rate_tab(allC, "pattern")
  lines <- c(lines, "-- Arm C (asymmetry patterns, A=0.20): TPR by pattern --",
             capture.output(print(results$armC, row.names = FALSE, digits = 3)), "")
}
saveRDS(results, file.path(RESULTS, "tier2_deltaB_results_v3final.rds"))
writeLines(lines, file.path(RESULTS, "tier2_deltaB_summary_v3final.txt"))
cat(paste(lines, collapse = "\n"), "\n")
cat("\nTIER2 RESCORE V3 COMPLETE\n")
