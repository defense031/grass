# Stage 7B re-analysis under the v0.8.0 prevalence-RESOLVED null.
# Same banked 22M draws (per_cell/), same plain-ECDF percentile
# convention as analyze_power_deltaB.R; the only change is the null:
# each (k, N, q, prev) power cell reads the resolved null at ITS OWN
# prevalence stratum (every power cell sits exactly on a resolved-null
# grid node) instead of the retired prevalence-pooled ridge.
# Output: tpr_percentile_convention_v080.rds + console digest for D.4.
suppressMessages(library(parallel))
S7 <- "/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/tier1/stage7_power_deltaB"
obj <- local({
  e <- new.env()
  load("/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/R/sysdata.rda", e)
  get("delta_null_ecdf", e)
})
stopifnot(identical(obj$version, "v2-hybrid-intdelta"))
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
agg <- aggregate(cbind(tpr95, tpr99) ~ k + N + q + A, data = res, FUN = mean)
saveRDS(agg, file.path(S7, "tpr_percentile_convention_v080.rds"))
saveRDS(res, file.path(S7, "tpr_by_prev_v080.rds"))

cat("== v0.8.0 resolved-null divergent TPR (>=99th), A = 0.20, q = 0.85 ==\n")
sub <- agg[agg$A == 0.20 & agg$q == 0.85, ]
print(sub[order(sub$k, sub$N), c("k", "N", "tpr95", "tpr99")], row.names = FALSE)
cat("\n== modal cell (k=5, N=200, q=0.85) across A ==\n")
print(agg[agg$k == 5 & agg$N == 200 & agg$q == 0.85,
          c("A", "tpr95", "tpr99")], row.names = FALSE)
cat("\n== pooled over designs and quality, divergent TPR at A=0.20 by N ==\n")
p <- aggregate(tpr99 ~ N, agg[agg$A == 0.20, ], mean)
print(p, row.names = FALSE)
cat("\nDONE\n")
