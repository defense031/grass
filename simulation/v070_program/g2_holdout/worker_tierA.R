# Tier A held-out worker: like the q99 node worker but q and prev come
# from the cells file (off-grid points). Resume-safe: blocks already on
# disk at the right draw count are reused (deterministic seeds).
suppressMessages(library(grassr))
rcb   <- get("run_calibration_block", getNamespace("grassr"))
ids   <- as.integer(strsplit(Sys.getenv("IDS"), ",")[[1]])
cells <- read.csv(Sys.getenv("CELLS"), stringsAsFactors = FALSE)
DRAWS <- as.integer(Sys.getenv("DRAWS", unset = "25000"))
wdir  <- Sys.getenv("WDIR"); dir.create(wdir, showWarnings = FALSE, recursive = TRUE)
rows  <- vector("list", length(ids))
mkrow <- function(id, c, r, f) data.frame(
  block_id = id, program = "prev_strata", k = c$k, N = c$N, q = c$q,
  prev = c$prev, draws = DRAWS, seed = 20300000L + id,
  wall_secs = r$wall_secs, file = f,
  md5 = tools::md5sum(file.path(wdir, f))[[1]], demo = FALSE,
  package_version = r$package_version, r_version = r$r_version,
  stringsAsFactors = FALSE)
for (i in seq_along(ids)) {
  id <- ids[i]; c <- cells[cells$block_id == id, ]
  b <- data.frame(block_id = id, program = "prev_strata", k = c$k, N = c$N,
                  q = c$q, prev = c$prev, draws = DRAWS,
                  seed = 20300000L + id, stringsAsFactors = FALSE)
  f <- sprintf("block_%04d.rds", id)
  if (file.exists(file.path(wdir, f))) {
    r <- readRDS(file.path(wdir, f))
    if (identical(r$block$draws, DRAWS)) {
      rows[[i]] <- mkrow(id, c, r, f)
      cat(sprintf("[w] block %d already done, skipping\n", id)); next
    }
  }
  r <- rcb(b)
  saveRDS(r, file.path(wdir, f))
  rows[[i]] <- mkrow(id, c, r, f)
  cat(sprintf("[w] block %d (k%d N%d q%.3f prev%.3f draws%d) done\n",
              id, c$k, c$N, c$q, c$prev, DRAWS))
}
write.csv(do.call(rbind, rows), file.path(wdir, "bundle_manifest.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(wdir, "SESSIONINFO.txt"))
