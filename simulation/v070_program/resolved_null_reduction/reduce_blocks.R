# Reduce calibration block bundles to per-cell fine quantile grids.
# Input: a glob of block_*.rds files (env BLOCK_GLOB), each the
# run_calibration_block output (block meta + 50k per-draw rows).
# Output (env OUT_RDS): list(index, probs, values) where values is
# n_cells x n_probs delta quantiles over finite draws. The 0.05% prob
# step sits at the MC-noise floor of a 50k-draw block, so downstream
# encodings evaluated against this grid lose nothing to the reduction.
# Duplicated block_ids (a block present in two bundles) keep the first
# copy and are reported.
suppressMessages({library(parallel)})
files <- Sys.glob(Sys.getenv("BLOCK_GLOB"))
stopifnot(length(files) > 0)
out_rds <- Sys.getenv("OUT_RDS")
cores <- as.integer(Sys.getenv("CORES", unset = "2"))
probs <- sort(unique(c(seq(0.001, 0.999, by = 0.001), 0.9995)))

one <- function(f) {
  r <- readRDS(f)
  b <- r$block
  d <- r$draws$delta
  fin <- d[is.finite(d)]
  data.frame(
    block_id = b$block_id, program = b$program,
    k = b$k, N = b$N, q = b$q, prev = b$prev,
    draws = b$draws, n_finite = length(fin),
    frac_zero = mean(fin <= 1e-12),
    q_pabak_med = stats::median(r$draws$q_pabak[is.finite(r$draws$q_pabak)]),
    package_version = r$package_version, file = f,
    t(stats::quantile(fin, probs = probs, names = FALSE, type = 7))
  )
}

res <- mclapply(files, one, mc.cores = cores)
bad <- vapply(res, inherits, logical(1), "try-error") |
  !vapply(res, is.data.frame, logical(1))
if (any(bad)) { cat("FAILED files:\n"); print(files[bad]) }
stopifnot(!any(bad))
df <- do.call(rbind, res)
dup <- duplicated(df$block_id)
if (any(dup)) cat(sprintf("dropping %d duplicated block_ids: %s\n",
                          sum(dup), paste(head(df$block_id[dup], 20), collapse = ",")))
df <- df[!dup, ]
df <- df[order(df$block_id), ]
qcols <- grepl("^X", names(df))
values <- as.matrix(df[, qcols]); colnames(values) <- as.character(probs)
index <- df[, !qcols]
saveRDS(list(index = index, probs = probs, values = values,
             created = format(Sys.time())), out_rds, compress = "xz")
cat(sprintf("reduced %d blocks -> %s (%.1f MB)\n", nrow(index), out_rds,
            file.size(out_rds) / 1e6))
