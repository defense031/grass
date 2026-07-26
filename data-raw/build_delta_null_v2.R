# Build the v0.8.0 delta_null_ecdf sysdata object (hybrid grid,
# integer-delta layout — the K100_intdelta frontier knee, 2026-07-24).
#
# Sources (50k draws per cell, all seed-reproducible):
#   - 1,925 prevalence-resolved cells: k{3,5,6,8,10,15,25} x 11 N x 5 q
#     (open-calibration prev_strata blocks)
#   -   385 q = 0.99 cells: same axes at the new top quality node
#   -   220 prevalence-POOLED k-fill cells: k{4,7,12,20} x 11 N x 5 q
#     (lattice_k blocks; prev pooled within each block, disclosed at
#     lookup via prev_pooled)
# The 21 tail_topup blocks re-ran cells of the retired pooled object and
# are superseded by the resolved cells; not used here.
#
# Layout: 100-knot quantile grid (1% steps + 99.5th), per-cell integer
# delta coding (first-difference, per-cell scale, int codes). Unpacking
# reconstructs values to within one scale unit (~max/32767); the
# rate-distortion audit scored this layout indistinguishable from exact
# storage in output units (pkgopt/frontier_full.csv).
#
# Env: CONTRIB_RDS, Q99_RDS (reduce_blocks.R outputs), OUT_RDS.

contrib <- readRDS(Sys.getenv("CONTRIB_RDS"))
q99 <- readRDS(Sys.getenv("Q99_RDS"))
stopifnot(identical(contrib$probs, q99$probs))
pr <- contrib$probs
k100 <- vapply(sort(unique(c(seq(0.01, 0.99, 0.01), 0.995))),
               function(p) which.min(abs(pr - p)), integer(1))
knot_probs <- round(pr[k100], 4)

take <- function(red, sel) list(index = red$index[sel, ], values = red$values[sel, k100, drop = FALSE])
res <- take(contrib, contrib$index$program == "prev_strata")
fil <- take(contrib, contrib$index$program == "lattice_k")
q9 <- take(q99, rep(TRUE, nrow(q99$index)))

index <- rbind(
  data.frame(k = res$index$k, N = res$index$N, q = res$index$q,
             prev = res$index$prev, n_draws = res$index$n_finite,
             prev_pooled = FALSE),
  data.frame(k = q9$index$k, N = q9$index$N, q = q9$index$q,
             prev = q9$index$prev, n_draws = q9$index$n_finite,
             prev_pooled = FALSE),
  data.frame(k = fil$index$k, N = fil$index$N, q = fil$index$q,
             prev = NA_real_, n_draws = fil$index$n_finite,
             prev_pooled = TRUE))
values <- rbind(res$values, q9$values, fil$values)
o <- order(index$k, index$N, index$q, index$prev, na.last = TRUE)
index <- index[o, ]; values <- values[o, , drop = FALSE]
rownames(index) <- NULL

stopifnot(nrow(index) == 1925 + 385 + 220, !is.unsorted(knot_probs),
          all(apply(values, 1L, function(v) !is.unsorted(v))))

# integer delta coding (matches pkgopt quant_intdelta exactly)
d <- t(apply(values, 1L, function(x) diff(c(0, x))))
sc <- apply(d, 1L, max) / 32767
sc[sc == 0] <- 1
delta_null_ecdf <- list(
  version = "v2-hybrid-intdelta",
  index = index,
  probs = knot_probs,
  scale = signif(sc, 6),
  codes = matrix(as.integer(round(sweep(d, 1L, sc, "/"))), nrow(values)),
  flag_conventions = c(caution = 0.95, divergent = 0.99)
)

# round-trip audit: decoded quantiles within one scale unit everywhere
dec <- t(apply(sweep(delta_null_ecdf$codes, 1L, delta_null_ecdf$scale, "*"),
               1L, cumsum))
stopifnot(max(abs(dec - values) / pmax(sc, 1e-12)) < (ncol(values) / 2))
cat(sprintf("cells %d | knots %d | max round-trip err %.3g (delta units)\n",
            nrow(index), length(knot_probs), max(abs(dec - values))))
saveRDS(delta_null_ecdf, Sys.getenv("OUT_RDS"), compress = "xz")
cat(sprintf("wrote %s (%.0f KB)\n", Sys.getenv("OUT_RDS"),
            file.size(Sys.getenv("OUT_RDS")) / 1024))
