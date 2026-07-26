#!/usr/bin/env Rscript
# Stage 7B re-analysis under the v0.8.0 FINAL resolved lattice (v3,
# 11,616 cells). Same banked 22M draws (per_cell/), same plain-ECDF
# percentile convention as analyze_power_deltaB.R and the Jul-24
# analyze_power_v080.R (only the null changes, so the D.4 comparison
# isolates the null swap). Every power cell sits exactly on a
# v3 grid node (v3 axis sets are supersets of the v2 resolved axes).
# Output: tpr_percentile_convention_v3final.rds + tpr_by_prev_v3final.rds
# + console digest for D.4.
suppressMessages(library(parallel))
S7 <- "/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/tier1/stage7_power_deltaB"
obj <- local({
  e <- new.env()
  load("/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/R/sysdata.rda", e)
  get("delta_null_ecdf", e)
})
stopifnot(identical(obj$version, "v3-resolved-lattice-intdelta"))
vals <- t(apply(sweep(obj$codes, 1L, obj$scale, "*"), 1L, cumsum))
idx <- obj$index
key <- paste(idx$k, idx$N, idx$q, idx$prev)
FINE <- obj$probs

files <- list.files(file.path(S7, "per_cell"), pattern = "^cell_[0-9]+\\.rds$",
                    full.names = TRUE)
one <- function(f) {
  x <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(x)) return(NULL)
  cell <- x$cell
  if (cell$k < 3) return(NULL)
  i <- match(paste(cell$k, cell$N, cell$q, cell$prev), key)
  if (is.na(i)) return(NULL)
  d <- x$draws$delta[is.finite(x$draws$delta)]
  if (length(d) < 100) return(NULL)
  pct <- approx(x = vals[i, ], y = FINE, xout = d, rule = 2,
                ties = "ordered")$y
  data.frame(k = cell$k, N = cell$N, q = cell$q, A = cell$A,
             prev = cell$prev, n = length(d),
             tpr95 = mean(pct >= 0.95), tpr99 = mean(pct >= 0.99))
}
res <- do.call(rbind, mclapply(files, one, mc.cores = 6))
cat("cells scored:", nrow(res), " (skipped k<3 and off-grid)\n")
saveRDS(res, file.path(S7, "tpr_by_prev_v3final.rds"))
agg <- aggregate(cbind(tpr95, tpr99) ~ k + N + q + A, data = res, FUN = mean)
saveRDS(agg, file.path(S7, "tpr_percentile_convention_v3final.rds"))

# digest for D.4
a20 <- agg[agg$A == 0.20, ]
cat(sprintf("\n== D.4 digest (v3 final null) ==\n"))
cat(sprintf("TPR at A=0.20: divergent mean %.3f  median %.3f  (caution mean %.3f)\n",
            mean(a20$tpr99), median(a20$tpr99), mean(a20$tpr95)))
byq <- aggregate(cbind(tpr99) ~ q, data = a20, FUN = mean)
cat("divergent TPR at A=0.20 by q:\n"); print(byq, row.names = FALSE)
byN <- aggregate(cbind(tpr99) ~ N, data = a20, FUN = mean)
cat("by N:\n"); print(byN, row.names = FALSE)
cat("\nPOWER RESCORE V3 COMPLETE\n")
