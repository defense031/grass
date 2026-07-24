## Self-verify a q=0.99 bundle: count, implied-q, finite rate, and REPLAY a sample bit-for-bit.
suppressMessages(library(grassr))
rcb  <- get("run_calibration_block", getNamespace("grassr"))
root <- Sys.getenv("ROOT"); expect <- as.integer(strsplit(Sys.getenv("EXPECT_IDS"), ",")[[1]])
out  <- file.path(root, "bundle"); dir.create(out, showWarnings = FALSE)
wd   <- sort(Sys.glob(file.path(root, "worker_*")))
man  <- do.call(rbind, lapply(wd, function(d) read.csv(file.path(d, "bundle_manifest.csv"), stringsAsFactors = FALSE)))
man  <- man[order(man$block_id), ]; rownames(man) <- NULL
for (d in wd) for (f in Sys.glob(file.path(d, "block_*.rds"))) file.copy(f, file.path(out, basename(f)), overwrite = TRUE)
file.copy(file.path(wd[1], "SESSIONINFO.txt"), file.path(out, "SESSIONINFO.txt"), overwrite = TRUE)
write.csv(man, file.path(out, "bundle_manifest.csv"), row.names = FALSE)

stopifnot(nrow(man) == length(expect), identical(sort(man$block_id), sort(expect)),
          all(man$q == 0.99), all(man$seed == 20300000L + man$block_id), !any(duplicated(man$block_id)),
          length(unique(man$draws)) == 1L)
cat(sprintf("draws per block: %d\n", man$draws[1]))
# implied q ~ 0.99 and finite rate across all blocks
iq <- fin <- numeric(nrow(man))
for (i in seq_len(nrow(man))) { r <- readRDS(file.path(out, man$file[i]))
  iq[i] <- median(r$draws$q_pabak[is.finite(r$draws$q_pabak)]); fin[i] <- r$n_finite / nrow(r$draws) }
cat(sprintf("blocks=%d implied_q median=%.4f (min %.4f max %.4f) finite min=%.4f\n",
            nrow(man), median(iq), min(iq), max(iq), min(fin)))
# q=0.99 corner: small-N extreme-prev panels are legitimately degenerate (high NA).
# Floor guards against a truly broken block (~0 finite) while passing the N=15/prev-extreme cells.
cat(sprintf("blocks with finite<0.90: %d (expected: N=15 extreme-prev)\n", sum(fin < 0.90)))
stopifnot(abs(median(iq) - 0.99) < 0.01, min(fin) > 0.50)
# REPLAY a sample: regenerate 5 blocks, require bit-identical delta (the anti-fraud/repro guarantee)
set.seed(1); samp <- sample(man$block_id, min(5, nrow(man)))
ok <- TRUE
for (id in samp) { r <- readRDS(file.path(out, sprintf("block_%04d.rds", id)))
  r2 <- rcb(r$block)   # replay at the block's OWN draw count
  if (!identical(r$draws$delta, r2$draws$delta)) { ok <- FALSE; cat("REPLAY MISMATCH", id, "\n") } }
cat(sprintf("replay sample (%s): %s\n", paste(samp, collapse = ","), if (ok) "ALL BIT-IDENTICAL" else "FAIL"))
stopifnot(ok)
cat(sprintf("Q99 BUNDLE VERIFIED (%d blocks)\n", nrow(man)))
