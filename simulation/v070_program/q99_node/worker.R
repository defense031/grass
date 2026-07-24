suppressMessages(library(grassr))
rcb   <- get("run_calibration_block", getNamespace("grassr"))
ids   <- as.integer(strsplit(Sys.getenv("IDS"), ",")[[1]])
cells <- read.csv(Sys.getenv("CELLS"), stringsAsFactors = FALSE)
DRAWS <- as.integer(Sys.getenv("DRAWS", unset = "50000"))
wdir  <- Sys.getenv("WDIR"); dir.create(wdir, showWarnings = FALSE, recursive = TRUE)
rows  <- vector("list", length(ids))
for (i in seq_along(ids)) {
  id <- ids[i]; c <- cells[cells$block_id == id, ]
  b <- data.frame(block_id = id, program = "prev_strata", k = c$k, N = c$N,
                  q = 0.99, prev = c$prev, draws = DRAWS, seed = 20300000L + id,
                  stringsAsFactors = FALSE)
  f <- sprintf("block_%04d.rds", id)
  # resume support: a block already on disk at the right draw count is
  # reused (seeds are deterministic; recomputation would be bit-identical)
  if (file.exists(file.path(wdir, f))) {
    r <- readRDS(file.path(wdir, f))
    if (identical(r$block$draws, DRAWS)) {
      rows[[i]] <- data.frame(block_id = id, program = "prev_strata", k = c$k,
                              N = c$N, q = 0.99, prev = c$prev, draws = DRAWS,
                              seed = 20300000L + id, wall_secs = r$wall_secs,
                              file = f,
                              md5 = tools::md5sum(file.path(wdir, f))[[1]],
                              demo = FALSE,
                              package_version = r$package_version,
                              r_version = r$r_version, stringsAsFactors = FALSE)
      cat(sprintf("[w] block %d already done, skipping\n", id)); next
    }
  }
  r <- rcb(b)
  saveRDS(r, file.path(wdir, f))
  rows[[i]] <- data.frame(block_id = id, program = "prev_strata", k = c$k, N = c$N,
                          q = 0.99, prev = c$prev, draws = DRAWS, seed = 20300000L + id,
                          wall_secs = r$wall_secs, file = f,
                          md5 = tools::md5sum(file.path(wdir, f))[[1]], demo = FALSE,
                          package_version = r$package_version, r_version = r$r_version,
                          stringsAsFactors = FALSE)
  cat(sprintf("[w] block %d (k%d N%d prev%.2f draws%d) done\n", id, c$k, c$N, c$prev, DRAWS))
}
write.csv(do.call(rbind, rows), file.path(wdir, "bundle_manifest.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(wdir, "SESSIONINFO.txt"))
