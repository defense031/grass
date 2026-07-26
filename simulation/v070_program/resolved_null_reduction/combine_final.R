# Assemble THE final full-lattice reduction: grid_done (11k, 9q, 11N,
# 7prev) + qceil + n25 + prev875 (7k crosses) + kx (the 4 kfill-k
# crosses). Verify the complete 11k x 12N x 11q x 8prev lattice.
v0 <- "/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program"
rr <- file.path(v0, "resolved_null_reduction")
parts <- c("cell_quantiles_grid_done.rds", "qceil_reduction.rds",
           "n25_reduction.rds", "prev875_reduction.rds", "kx_reduction.rds")
idx <- NULL; val <- NULL; probs <- NULL
for (f in parts) {
  x <- readRDS(file.path(rr, f))
  if (is.null(probs)) probs <- x$probs else stopifnot(identical(x$probs, probs))
  idx <- rbind(idx, x$index); val <- rbind(val, x$values)
}
dup <- duplicated(idx$block_id)
if (any(dup)) cat(sprintf("dropping %d duplicated block_ids\n", sum(dup)))
idx <- idx[!dup, ]; val <- val[!dup, , drop = FALSE]
o <- order(idx$block_id); idx <- idx[o, ]; val <- val[o, , drop = FALSE]
# lattice completeness check over (k, N, q, prev), q99 handled by prep.
# CANONICAL axes hard-coded (audit 2026-07-25): deriving them from the
# data would let a wholly-missing axis value pass silently.
ks <- c(3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 25)
Ns <- c(15, 20, 25, 30, 50, 75, 100, 150, 200, 300, 500, 1000)
qs <- c(0.65, 0.70, 0.75, 0.80, 0.85, 0.885, 0.92, 0.945, 0.97, 0.98, 0.99)
# (385 q = 0.99 corner cells are expected missing here; the Q99_RDS
#  top-up in pkgopt/01_prep.R supplies them)
ps <- c(0.05, 0.2, 0.35, 0.5, 0.65, 0.8, 0.875, 0.95)
stopifnot(all(idx$k %in% ks), all(idx$N %in% Ns), all(idx$q %in% qs),
          all(is.na(idx$prev) | idx$prev %in% ps))
cat(sprintf("axes: k %d | N %d | q %d | prev %d -> expect %d cells (q99 corner via Q99_RDS tops up)\n",
            length(ks), length(Ns), length(qs), length(ps),
            length(ks) * length(Ns) * length(qs) * length(ps)))
have <- with(idx, paste(k, N, q, prev))
grid <- expand.grid(k = ks, N = Ns, q = qs, prev = ps)
need <- with(grid, paste(k, N, q, prev))
miss <- setdiff(need, have)
cat(sprintf("blocks: %d | missing lattice cells (pre-q99-topup): %d\n", nrow(idx), length(miss)))
if (length(miss) && length(miss) < 20) print(miss)
saveRDS(list(index = idx, probs = probs, values = val,
             created = format(Sys.time())),
        file.path(rr, "cell_quantiles_FINAL.rds"), compress = "xz")
cat(sprintf("wrote cell_quantiles_FINAL.rds (%.1f MB)\n",
            file.size(file.path(rr, "cell_quantiles_FINAL.rds")) / 1e6))
