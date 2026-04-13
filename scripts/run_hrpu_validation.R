#!/usr/bin/env Rscript
# run_hrpu_validation.R — Apply GRASS to the HRPU inter-rater agreement study
#
# External validation: does GRASS produce interpretable, consistent results
# on real binary agreement data with varying prevalence?

library(data.table)

# ------------------------------------------------------------------
# 1. Load HRPU data
# ------------------------------------------------------------------
cat("Loading HRPU data...\n")
hrpu <- fread("/Users/austinsemmel/Desktop/USMA/Research/HRPU_Study/theGoods/hrpu_consolidated.csv")
cat(sprintf("Rows: %d, Videos: %d, Graders: %d, Tests: %d\n",
    nrow(hrpu), length(unique(hrpu$Video)), length(unique(hrpu$Grader)), length(unique(hrpu$Test))))

# ------------------------------------------------------------------
# 2. Load GRASS thresholds from unified simulation
# ------------------------------------------------------------------
res <- readRDS("output/unified_sim/unified_results.rds")
grass_thresh <- res$thresholds

# ------------------------------------------------------------------
# 3. For each Video x Test, compute pairwise agreement metrics
# ------------------------------------------------------------------
cat("Computing pairwise agreement metrics...\n")

# Function to compute metrics from a 2x2 table
compute_metrics <- function(tab) {
  a <- tab[1, 1]; b <- tab[1, 2]; c <- tab[2, 1]; d <- tab[2, 2]
  N <- a + b + c + d
  if (N == 0) return(NULL)

  P0 <- (a + d) / N
  Pe <- ((a+b)*(a+c) + (c+d)*(b+d)) / (N*N)
  kappa <- if (Pe == 1) ifelse(P0 == 1, 1, 0) else (P0 - Pe) / (1 - Pe)
  PABAK <- 2 * P0 - 1

  pi_hat <- ((c+d)/N + (b+d)/N) / 2
  Pe_ac1 <- 2 * pi_hat * (1 - pi_hat)
  AC1 <- if (Pe_ac1 == 1) ifelse(P0 == 1, 1, 0) else (P0 - Pe_ac1) / (1 - Pe_ac1)

  pos_denom <- 2*d + b + c
  P_pos <- if (pos_denom == 0) NA_real_ else 2*d / pos_denom
  neg_denom <- 2*a + b + c
  P_neg <- if (neg_denom == 0) NA_real_ else 2*a / neg_denom

  PI <- abs(d - a) / N
  BI <- abs(b - c) / N
  prev_est <- pi_hat

  data.table(N = N, P0 = P0, kappa = kappa, PABAK = PABAK, AC1 = AC1,
             P_pos = P_pos, P_neg = P_neg, PI = PI, BI = BI, prev_est = prev_est)
}

# Get all pairwise comparisons within each Video x Test
graders <- sort(unique(hrpu$Grader))
videos <- sort(unique(hrpu$Video))
tests <- sort(unique(hrpu$Test))

results_list <- list()
idx <- 0

for (v in videos) {
  for (t in tests) {
    sub <- hrpu[Video == v & Test == t]
    reps <- sort(unique(sub$Rep_Number))

    for (i in 1:(length(graders) - 1)) {
      for (j in (i + 1):length(graders)) {
        g1 <- graders[i]; g2 <- graders[j]
        d1 <- sub[Grader == g1, .(Rep_Number, O1 = Outcome)]
        d2 <- sub[Grader == g2, .(Rep_Number, O2 = Outcome)]
        merged <- merge(d1, d2, by = "Rep_Number")

        if (nrow(merged) < 5) next  # Skip if too few shared reps

        tab <- table(factor(merged$O1, levels = 0:1), factor(merged$O2, levels = 0:1))
        metrics <- compute_metrics(tab)
        if (is.null(metrics)) next

        idx <- idx + 1
        metrics[, `:=`(video = v, test = t, grader1 = g1, grader2 = g2)]
        results_list[[idx]] <- metrics
      }
    }
  }
}

pairwise <- rbindlist(results_list)
cat(sprintf("Pairwise comparisons: %d\n", nrow(pairwise)))

# ------------------------------------------------------------------
# 4. Apply GRASS thresholds
# ------------------------------------------------------------------
cat("Applying GRASS thresholds...\n")

# Find nearest prevalence row for each comparison
find_nearest_prev <- function(p, thresh_prevs) {
  thresh_prevs[which.min(abs(thresh_prevs - p))]
}

pairwise[, nearest_prev := sapply(prev_est, find_nearest_prev, thresh_prevs = grass_thresh$prevalence)]
pairwise <- merge(pairwise, grass_thresh[, .(prevalence, kappa_thresh, PABAK_thresh, AC1_thresh)],
                  by.x = "nearest_prev", by.y = "prevalence")

# Classify
pairwise[, kappa_pass := kappa >= kappa_thresh]
pairwise[, PABAK_pass := PABAK >= PABAK_thresh]
pairwise[, AC1_pass := AC1 >= AC1_thresh]
pairwise[, all_agree := (kappa_pass == PABAK_pass) & (PABAK_pass == AC1_pass)]

# ------------------------------------------------------------------
# 5. Results
# ------------------------------------------------------------------
cat("\n=== GRASS External Validation: HRPU Study ===\n\n")

cat(sprintf("Total pairwise comparisons: %d\n", nrow(pairwise)))
cat(sprintf("Prevalence range: %.1f%% to %.1f%%\n",
    100 * min(pairwise$prev_est), 100 * max(pairwise$prev_est)))

cat(sprintf("\nMetric agreement rate: %.1f%% (%d of %d agree)\n",
    100 * mean(pairwise$all_agree), sum(pairwise$all_agree), nrow(pairwise)))

cat("\nAgreement by nearest prevalence:\n")
agree_by_prev <- pairwise[, .(
  n = .N,
  pct_agree = round(100 * mean(all_agree), 1),
  mean_kappa = round(mean(kappa, na.rm = TRUE), 3),
  mean_PABAK = round(mean(PABAK), 3),
  mean_AC1 = round(mean(AC1, na.rm = TRUE), 3)
), by = nearest_prev]
setorder(agree_by_prev, nearest_prev)
print(agree_by_prev)

# Discordance analysis
discord <- pairwise[all_agree == FALSE]
cat(sprintf("\nDiscordant comparisons: %d\n", nrow(discord)))
if (nrow(discord) > 0) {
  cat("\nDiscordance patterns:\n")
  discord[, pattern := paste0("k=", ifelse(kappa_pass, "P", "F"),
                               " P=", ifelse(PABAK_pass, "P", "F"),
                               " A=", ifelse(AC1_pass, "P", "F"))]
  print(table(discord$pattern))

  cat("\nDiscordance by prevalence:\n")
  disc_prev <- discord[, .N, by = nearest_prev]
  setorder(disc_prev, nearest_prev)
  print(disc_prev)
}

# Without GRASS: do L-K labels agree across metrics?
lk_label <- function(x) {
  cut(x, breaks = c(-Inf, 0, 0.20, 0.40, 0.60, 0.80, Inf),
      labels = c("poor", "slight", "fair", "moderate", "substantial", "almost_perfect"),
      right = TRUE)
}
pairwise[, lk_kappa := lk_label(kappa)]
pairwise[, lk_PABAK := lk_label(PABAK)]
pairwise[, lk_AC1 := lk_label(AC1)]
pairwise[, lk_all_same := (lk_kappa == lk_PABAK) & (lk_PABAK == lk_AC1)]

cat(sprintf("\n=== Without GRASS: L-K label agreement ===\n"))
cat(sprintf("All three metrics receive same L-K label: %.1f%% (%d of %d)\n",
    100 * mean(pairwise$lk_all_same), sum(pairwise$lk_all_same), nrow(pairwise)))

cat("\nBy prevalence:\n")
lk_by_prev <- pairwise[, .(
  n = .N,
  lk_agree = round(100 * mean(lk_all_same), 1)
), by = nearest_prev]
setorder(lk_by_prev, nearest_prev)
print(lk_by_prev)

# P_pos check (Step 4)
cat(sprintf("\n=== Step 4: P_pos check ===\n"))
cat(sprintf("P_pos >= 0.50: %.1f%% of comparisons\n", 100 * mean(pairwise$P_pos >= 0.50, na.rm = TRUE)))
cat(sprintf("P_pos >= 0.70: %.1f%% of comparisons\n", 100 * mean(pairwise$P_pos >= 0.70, na.rm = TRUE)))

# Save
saveRDS(pairwise, "output/unified_sim/hrpu_validation.rds")
cat("\nResults saved to output/unified_sim/hrpu_validation.rds\n")
