# Build the v0.8.0 delta_null_ecdf sysdata object, v3 — the complete
# prevalence-resolved lattice (2026-07-25 campaign; supersedes the
# v2 hybrid resolved+pooled object).
#
# Source: the final truth object (pkgopt/01_prep.R over ALL campaign
# reductions): 11,616 cells = k {3,4,5,6,7,8,10,12,15,20,25} x twelve
# N (15..1000 incl. 25) x eleven q (0.65..0.99) x eight prevalence
# levels (0.05..0.95 incl. 0.875), 50k draws per cell, every cell
# prevalence-resolved. The prev_pooled column is GONE — nothing pools;
# the corresponding lookup/asymmetry branches and card note are removed
# in R/ alongside this build.
#
# Layout: knot quantile grid + per-cell integer delta coding, same
# audit standard as v2 (round-trip within one scale unit). Knot budget
# and quantization follow the frontier pick on the FINAL lattice
# (pkgopt/frontier_FINAL.csv); default is the v2 knee (100 knots,
# int-delta) pending that pick.
#
# Env: TRUTH_RDS (pkgopt truth object), OUT_RDS, KNOTS (default 100).

truth <- readRDS(Sys.getenv("TRUTH_RDS"))
pr <- truth$probs
nk <- as.integer(Sys.getenv("KNOTS", unset = "100"))
if (nk == 100) {
  kidx <- vapply(sort(unique(c(seq(0.01, 0.99, 0.01), 0.995))),
                 function(p) which.min(abs(pr - p)), integer(1))
} else stop("non-default knot budgets take their grid from the frontier pick")
knot_probs <- round(pr[kidx], 4)

index <- data.frame(k = truth$index$k, N = truth$index$N,
                    q = truth$index$q, prev = truth$index$prev,
                    n_draws = truth$index$n_finite)
values <- truth$values[, kidx, drop = FALSE]
o <- order(index$k, index$N, index$q, index$prev)
index <- index[o, ]; values <- values[o, , drop = FALSE]
rownames(index) <- NULL

stopifnot(nrow(index) == 11616, !is.unsorted(knot_probs),
          all(apply(values, 1L, function(v) !is.unsorted(v))),
          !anyNA(index$prev))

d <- t(apply(values, 1L, function(x) diff(c(0, x))))
sc <- apply(d, 1L, max) / 32767
sc[sc == 0] <- 1
delta_null_ecdf <- list(
  version = "v3-resolved-lattice-intdelta",
  index = index,
  probs = knot_probs,
  scale = signif(sc, 6),
  codes = matrix(as.integer(round(sweep(d, 1L, sc, "/"))), nrow(values)),
  flag_conventions = c(caution = 0.95, divergent = 0.99)
)

dec <- t(apply(sweep(delta_null_ecdf$codes, 1L, delta_null_ecdf$scale, "*"),
               1L, cumsum))
stopifnot(max(abs(dec - values) / pmax(sc, 1e-12)) < (ncol(values) / 2))
cat(sprintf("cells %d | knots %d | max round-trip err %.3g (delta units)\n",
            nrow(index), length(knot_probs), max(abs(dec - values))))
saveRDS(delta_null_ecdf, Sys.getenv("OUT_RDS"), compress = "xz")
cat(sprintf("wrote %s (%.0f KB)\n", Sys.getenv("OUT_RDS"),
            file.size(Sys.getenv("OUT_RDS")) / 1024))
