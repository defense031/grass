# Package-structure optimization — data prep.
# Builds the truth object for the null-family rate-distortion sweep:
# per-cell fine quantile grids (from the block reductions) plus a
# per-cell, per-prob MC-SE floor, and axis indexing for interpolation.
#
# Inputs (env):
#   CONTRIB_RDS  reduction of the 2,166 contributed blocks
#   Q99_RDS      reduction of the q=0.99 corner node ("" to skip — prelim mode)
#   OUT_RDS      output truth object
#
# MC-SE of the p-th sample quantile from n draws:
#   SE(Q_p) ~= sqrt(p(1-p)/n) * dQ/dp,  dQ/dp by central difference on the
# stored grid (plateaus give 0 — the quantile is pinned by point mass).

contrib <- readRDS(Sys.getenv("CONTRIB_RDS"))
q99_path <- Sys.getenv("Q99_RDS", unset = "")

keep <- contrib$index$program == "prev_strata"
index <- contrib$index[keep, c("block_id", "k", "N", "q", "prev", "draws",
                               "n_finite", "frac_zero")]
values <- contrib$values[keep, , drop = FALSE]
probs <- contrib$probs

if (nzchar(q99_path)) {
  q99 <- readRDS(q99_path)
  stopifnot(identical(q99$probs, probs))
  k9 <- q99$index$program == "prev_strata"   # q99 blocks reuse the program tag
  index <- rbind(index, q99$index[k9, names(index)])
  values <- rbind(values, q99$values[k9, , drop = FALSE])
}
o <- order(index$k, index$N, index$q, index$prev)
index <- index[o, ]; values <- values[o, , drop = FALSE]
rownames(index) <- NULL

ks <- sort(unique(index$k)); Ns <- sort(unique(index$N))
qs <- sort(unique(index$q)); prevs <- sort(unique(index$prev))
stopifnot(nrow(index) == length(ks) * length(Ns) * length(qs) * length(prevs))

# row id lookup array [N, q, prev, k]
cell_id <- array(NA_integer_, dim = c(length(Ns), length(qs), length(prevs),
                                      length(ks)),
                 dimnames = list(Ns, qs, prevs, ks))
for (i in seq_len(nrow(index)))
  cell_id[as.character(index$N[i]), as.character(index$q[i]),
          as.character(index$prev[i]), as.character(index$k[i])] <- i

# MC-SE floor per cell x prob
h <- 3L  # central-difference half-width in grid steps (3 x 0.001)
np <- length(probs)
lo <- pmax(1L, seq_len(np) - h); hi <- pmin(np, seq_len(np) + h)
dp <- probs[hi] - probs[lo]
mcse <- values  # same shape
for (i in seq_len(nrow(values))) {
  dQdp <- (values[i, hi] - values[i, lo]) / dp
  mcse[i, ] <- sqrt(probs * (1 - probs) / index$n_finite[i]) * dQdp
}

saveRDS(list(index = index, probs = probs, values = values, mcse = mcse,
             cell_id = cell_id, ks = ks, Ns = Ns, qs = qs, prevs = prevs),
        Sys.getenv("OUT_RDS"), compress = "xz")
cat(sprintf("truth: %d cells (k %s | N %d nodes | q %s | prev %s)\n",
            nrow(index), paste(ks, collapse = ","), length(Ns),
            paste(qs, collapse = ","), paste(prevs, collapse = ",")))
