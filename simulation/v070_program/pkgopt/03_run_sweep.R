# Package-structure optimization — sweep driver (v2).
# Traces the empirical rate-distortion frontier for the null family:
# (post-xz bytes) vs (worst-case, total) OUTPUT error, over knot budget,
# quantization family, structured axis-thinning, and free-form greedy
# anchor peeling. Env: TRUTH_RDS, OUT_CSV, OUT_RDS, PKGOPT_DIR.
source(file.path(Sys.getenv("PKGOPT_DIR"), "02_lib.R"))
truth <- readRDS(Sys.getenv("TRUTH_RDS"))
n_cells <- nrow(truth$index)
cat(sprintf("truth loaded: %d cells, %d probs\n", n_cells, length(truth$probs)))

pr <- truth$probs
k100 <- vapply(sort(unique(c(seq(0.01, 0.99, 0.01), 0.995))),
               function(p) which.min(abs(pr - p)), integer(1))
k50 <- match(knots_tailweighted(50, pr), pr)
k25 <- match(knots_tailweighted(25, pr), pr)
all_anchors <- rep(TRUE, n_cells)

results <- list()
add <- function(s) { results[[length(results) + 1L]] <<- s
  cat(sprintf("  %-26s %8.1f KB  wc %.3f pp  mean %.4f pp  cut95 %.1e pp  size95 [%.3f, %.3f]  na %d\n",
              s$candidate, s$kb, s$pct_shift_wc, s$pct_shift_mean,
              s$cut95_pp_wc, s$size95_lo, s$size95_hi, s$n_cells_na)) }

cat("== baseline + knot sweep ==\n")
add(run_candidate(truth, "K100_signif5", all_anchors, k100, quant_signif(5)))
add(run_candidate(truth, "K50_signif5",  all_anchors, k50,  quant_signif(5)))
add(run_candidate(truth, "K25_signif5",  all_anchors, k25,  quant_signif(5)))

cat("== quantization sweep ==\n")
add(run_candidate(truth, "K100_signif4", all_anchors, k100, quant_signif(4)))
add(run_candidate(truth, "K100_signif3", all_anchors, k100, quant_signif(3)))
add(run_candidate(truth, "K100_intdelta", all_anchors, k100, quant_intdelta()))
add(run_candidate(truth, "K50_intdelta",  all_anchors, k50,  quant_intdelta()))
add(run_candidate(truth, "K100_dict5", all_anchors, k100, quant_dict(5)))
add(run_candidate(truth, "K100_dict4", all_anchors, k100, quant_dict(4)))
add(run_candidate(truth, "K50_dict4",  all_anchors, k50,  quant_dict(4)))
add(run_candidate(truth, "K100_rank10", all_anchors, k100, quant_lowrank(10)))
add(run_candidate(truth, "K100_rank20", all_anchors, k100, quant_lowrank(20)))
add(run_candidate(truth, "K100_rank40", all_anchors, k100, quant_lowrank(40)))

cat("== structured axis-thinning ==\n")
thin <- function(tag, keepN = truth$Ns, keepQ = truth$qs, keepP = truth$prevs,
                 knots = k100, quant = quant_signif(5)) {
  a <- truth$index$N %in% keepN & truth$index$q %in% keepQ &
    truth$index$prev %in% keepP
  add(run_candidate(truth, tag, a, knots, quant))
}
thin("thinN7_signif5",  keepN = c(15, 30, 50, 100, 200, 500, 1000))
thin("thinN5_signif5",  keepN = c(15, 50, 150, 500, 1000))
thin("thinP3_signif5",  keepP = c(0.05, 0.5, 0.95))
thin("thinN7P3_signif5", keepN = c(15, 30, 50, 100, 200, 500, 1000),
     keepP = c(0.05, 0.5, 0.95))
thin("thinN7_K50_intdelta", keepN = c(15, 30, 50, 100, 200, 500, 1000),
     knots = k50, quant = quant_intdelta())
thin("thinN7P3_K50_intdelta", keepN = c(15, 30, 50, 100, 200, 500, 1000),
     keepP = c(0.05, 0.5, 0.95), knots = k50, quant = quant_intdelta())

# ---- free-form greedy anchor peel ---------------------------------------
# Cost-capped: a cell is only dropped if its standalone reconstruction
# (from the current anchor set, read on the knot grid as the package
# would) stays under PEEL_CAP percentile points. Small rounds with an
# adjacency exclusion limit interaction effects; the honest full decode
# + score after each round is what goes in the table.
cat("== anchor peel (mid-p scoring, cost-capped) ==\n")
PEEL_CAP <- 1.0
idx <- truth$index
edge <- idx$N %in% range(truth$Ns) | idx$q %in% range(truth$qs) |
  idx$prev %in% range(truth$prevs)
anchors <- all_anchors
kp100 <- pr[k100]
probe_i <- vapply(c(0.5, 0.9, 0.95, 0.99),
                  function(p) which.min(abs(pr - p)), integer(1))
slab_pos <- cbind(match(idx$N, truth$Ns), match(idx$q, truth$qs),
                  match(idx$prev, truth$prevs))
knot_row <- function(ci) truth$values[ci, k100]

drop_cost <- function(i, anchors) {
  a2 <- anchors; a2[i] <- FALSE
  vr <- .recon_cell(truth, i, a2, knot_row)
  if (is.null(vr)) return(Inf)
  vt <- truth$values[i, ]
  max(vapply(vt[probe_i], function(x)
    abs(pct_midp(vr, kp100, x) - pct_midp(vt, pr, x)), numeric(1)))
}

peel_traj <- list()
for (round in 1:6) {
  cand <- which(anchors & !edge)
  if (!length(cand)) break
  costs <- vapply(cand, drop_cost, numeric(1), anchors = anchors)
  ord <- cand[order(costs)]
  accepted <- integer(0)
  for (i in ord) {
    if (length(accepted) >= ceiling(length(cand) / 10)) break
    if (costs[match(i, cand)] > PEEL_CAP) break
    if (length(accepted)) {
      same_k <- idx$k[accepted] == idx$k[i]
      if (any(same_k & rowSums(abs(slab_pos[accepted, , drop = FALSE] -
                                   matrix(slab_pos[i, ], length(accepted), 3,
                                          byrow = TRUE))) <= 1)) next
    }
    accepted <- c(accepted, i)
  }
  if (!length(accepted)) { cat(sprintf("  peel stops at round %d (no cell under cap %.1f pp)\n", round, PEEL_CAP)); break }
  anchors[accepted] <- FALSE
  tag <- sprintf("peel_r%d_a%d", round, sum(anchors))
  s <- run_candidate(truth, tag, anchors, k100, quant_signif(5))
  add(s)
  peel_traj[[round]] <- list(anchors = which(anchors), summary = s)
}

cat("== combined: peeled anchors x compact layouts ==\n")
add(run_candidate(truth, "peel_K50_intdelta", anchors, k50, quant_intdelta()))
add(run_candidate(truth, "peel_K50_signif5", anchors, k50, quant_signif(5)))

tab <- do.call(rbind, results)
tab <- tab[order(tab$kb), ]
write.csv(tab, Sys.getenv("OUT_CSV"), row.names = FALSE)
saveRDS(list(table = tab, peel = peel_traj, final_anchors = which(anchors)),
        Sys.getenv("OUT_RDS"), compress = "xz")
cat("\n== frontier table (by size) ==\n")
print(tab, row.names = FALSE, digits = 3)
