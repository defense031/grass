# delta_null.R — matched-null lookup and percentile positioning for the
# cross-coefficient diagnostic.
#
# The per-(k, N) threshold table is retired (0.7.0). delta_hat is reported
# as its percentile on the null distribution of delta_hat at the matched
# (k, N, q_hat) cell, calibrated by the production-pipeline null program.
# Flags are conventions on that percentile: caution at the 95th, divergent
# at the 99th. The percentile is computed by interpolation on a stored
# fine quantile grid (1% steps + 99.5%).
#
# v0.7.1 (Option B): delta_hat is the implied-quality spread in quality
# percentage points (design/v0.7.1_position_redesign.md). The stored null
# MUST be calibrated in the same units — the stage 6 regeneration under
# the Option-B pipeline replaces the 0.7.0 percentile-spread null.

# Decode cache: the v2 sysdata stores integer-delta codes; the quantile
# matrix is reconstructed once per session and reused.
.delta_null_env <- new.env(parent = emptyenv())
.delta_null_values <- function(obj) {
  if (is.null(.delta_null_env$values) ||
      !identical(.delta_null_env$version, obj$version)) {
    .delta_null_env$values <-
      t(apply(sweep(obj$codes, 1L, obj$scale, "*"), 1L, cumsum))
    .delta_null_env$version <- obj$version
  }
  .delta_null_env$values
}

# Resolve the calibrated null at (k, N, q_hat, pi_hat) on the v0.8.0
# hybrid grid. k snaps to the nearest calibrated rater count (resolved
# preferred on ties). At the prevalence-resolved rater counts the stored
# quantile vectors interpolate trilinearly between the bracketing nodes
# in q, log10 N, and prevalence; at the prevalence-pooled fill counts
# (k = 4, 7, 12, 20) the same interpolation runs over q and log10 N and
# the pooling is disclosed via prev_pooled. Queries outside the grid
# clamp to the edge node and are disclosed via `snapped`. Exact node
# hits reproduce the stored (decoded) cell.
lookup_delta_null <- function(k, N, q_hat, pi_hat) {
  # k = 2 is NOT calibrated and must never snap to k = 3: at k = 2 the
  # agreement family is PABAK + AC1, whose implied qualities coincide by
  # construction (delta_hat is identically zero — 2.75M Option-B null
  # draws produced no exception). delta_hat carries no information at
  # k = 2; check_asymmetry() reports not_applicable there.
  if (as.numeric(k) < 3) return(NULL)
  obj <- tryCatch(
    get("delta_null_ecdf", envir = asNamespace("grassr"), inherits = FALSE),
    error = function(e) NULL)
  if (is.null(obj) || !identical(obj$version, "v2-hybrid-intdelta"))
    return(NULL)
  vals <- .delta_null_values(obj)
  idx <- obj$index

  ks <- sort(unique(idx$k))
  kd <- abs(ks - as.numeric(k))
  cand <- ks[kd == min(kd)]
  pooled_ks <- sort(unique(idx$k[idx$prev_pooled]))
  k_node <- if (any(!cand %in% pooled_ks)) cand[!cand %in% pooled_ks][1L]
            else cand[1L]
  pooled <- k_node %in% pooled_ks

  sub <- idx$k == k_node & (if (pooled) idx$prev_pooled else !idx$prev_pooled)
  Ns <- sort(unique(idx$N[sub]))
  qs <- sort(unique(idx$q[sub]))
  prevs <- if (pooled) NA_real_ else sort(unique(idx$prev[sub]))

  q_eff <- min(max(as.numeric(q_hat), qs[1L]), qs[length(qs)])
  N_eff <- min(max(as.numeric(N), Ns[1L]), Ns[length(Ns)])
  p_eff <- if (pooled) NA_real_ else
    min(max(as.numeric(pi_hat), prevs[1L]), prevs[length(prevs)])

  bracket <- function(nodes, x, transform = identity) {
    i <- findInterval(x, nodes, rightmost.closed = TRUE)
    i <- max(1L, min(i, length(nodes) - 1L))
    lo <- nodes[i]; hi <- nodes[i + 1L]
    w <- (transform(x) - transform(lo)) / (transform(hi) - transform(lo))
    list(lo = lo, hi = hi, w = w)
  }
  qb <- bracket(qs, q_eff)
  Nb <- bracket(Ns, N_eff, transform = log10)
  pb <- if (pooled) list(lo = NA, hi = NA, w = 0) else bracket(prevs, p_eff)

  corners <- expand.grid(
    q = c(qb$lo, qb$hi), N = c(Nb$lo, Nb$hi),
    p = if (pooled) NA_real_ else c(pb$lo, pb$hi))
  corners$w <- ifelse(corners$q == qb$lo, 1 - qb$w, qb$w) *
    ifelse(corners$N == Nb$lo, 1 - Nb$w, Nb$w) *
    (if (pooled) 1 else ifelse(corners$p == pb$lo, 1 - pb$w, pb$w))
  # collapse duplicated corners from degenerate (exact-hit) brackets
  corners <- corners[!duplicated(corners[, c("q", "N", "p")]), , drop = FALSE]

  values <- 0
  n_draws <- integer(0)
  for (j in which(corners$w > 0)) {
    cell_i <- which(sub & idx$N == corners$N[j] & idx$q == corners$q[j] &
                      (if (pooled) TRUE else idx$prev == corners$p[j]))
    if (length(cell_i) != 1L) return(NULL)
    values <- values + corners$w[j] * vals[cell_i, ]
    n_draws <- c(n_draws, idx$n_draws[cell_i])
  }
  list(
    k = k_node, N = as.integer(N_eff), q = q_eff,
    prev = p_eff, prev_pooled = pooled,
    n_draws = min(n_draws),
    unstable_tail = FALSE,
    # snapped = the resolved design differs from the query (k off the
    # calibrated set, or an axis clamped at a grid edge). Interior
    # off-node queries are served by interpolation, not snapping.
    snapped = (k_node != as.numeric(k) || N_eff != as.numeric(N) ||
                 abs(q_eff - as.numeric(q_hat)) > 1e-9 ||
                 (!pooled && abs(p_eff - as.numeric(pi_hat)) > 1e-9)),
    interpolated = (qb$w > 0 && qb$w < 1) || (Nb$w > 0 && Nb$w < 1) ||
      (!pooled && pb$w > 0 && pb$w < 1),
    probs = obj$probs,
    values = values,
    conventions = obj$flag_conventions
  )
}

# Percentile of an observed delta_hat on the matched null ECDF, in
# [~0.5, 99.5+] percent. Values beyond the stored 99.5th report as > 99.5.
#
# Tied quantile runs (point masses) use the MID-P convention:
#   percentile = 100 * (P(D < d) + 0.5 * P(D = d))
# the standard treatment for discrete nulls. Small-N Option-B nulls carry
# real point mass at delta_hat = 0 (41% of the grid at k=5/N=1000/q=0.97);
# reporting the BOTTOM of the tie run understates the position (the 0.7.0
# v[1] short-circuit bug: "1.0 percentile" where P(D <= 0) was ~35%) and
# reporting the TOP misfires the flag convention on heavily-plateaued
# cells (an observed 0 on a mostly-zero null would read as extreme).
delta_null_percentile <- function(delta_hat, cell) {
  if (!is.finite(delta_hat) || is.null(cell)) return(NA_real_)
  v <- cell$values; p <- cell$probs
  tol <- 1e-12
  if (delta_hat <= v[1L] + tol) {
    # Observation at (or below) the grid floor. Tie run = every stored
    # quantile equal to the floor value; P(D < d) ~ 0 below the stored
    # grid, P(D <= d) ~ prob at the top of the run.
    run_top <- max(which(v <= v[1L] + tol))
    return(100 * 0.5 * p[run_top])
  }
  if (delta_hat >= v[length(v)] - tol) {
    # At or beyond the stored ceiling. If the ceiling itself is a tie
    # run (mass at the max), mid-p between the run bottom and the cap;
    # strictly beyond the ceiling reports the cap.
    if (delta_hat > v[length(v)] + tol) return(100 * p[length(p)])
    run_bot <- min(which(v >= v[length(v)] - tol))
    lo <- if (run_bot == 1L) 0 else p[run_bot - 1L]
    return(100 * 0.5 * (lo + p[length(p)]))
  }
  # Interior: if d lands inside a tie run, mid-p across the run;
  # otherwise plain interpolation on the strictly-increasing segments.
  ties_at <- which(abs(v - delta_hat) <= tol)
  if (length(ties_at) > 1L) {
    lo <- if (min(ties_at) == 1L) 0 else p[min(ties_at) - 1L]
    return(100 * 0.5 * (lo + p[max(ties_at)]))
  }
  100 * stats::approx(x = v, y = p, xout = delta_hat,
                      rule = 2, ties = "ordered")$y
}

# Flag from the percentile conventions. A cell with an unstable tail
# still flags (the ECDF is stable); the instability is surfaced as a
# note, not a verdict change.
delta_flag_from_percentile <- function(pct, conventions = c(caution = 0.95,
                                                            divergent = 0.99)) {
  if (!is.finite(pct)) return("not_calibrated")
  if (pct >= 100 * conventions[["divergent"]]) return("divergent")
  if (pct >= 100 * conventions[["caution"]]) return("caution")
  "aligned"
}
