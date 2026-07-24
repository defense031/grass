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

# Resolve the calibrated null at (k, N, q_hat). k snaps to the nearest
# calibrated panel size (panel size is discrete). q and N interpolate
# linearly between the two bracketing grid nodes (log10 scale for N),
# combining the stored quantile vectors cell-wise: the null is smooth in
# both, and nearest-node snapping mis-sizes off-grid thresholds by up to
# ~45% at near-ceiling q where interpolation recovers direct-simulation
# truth to ~2% (probe 2026-07-23). Queries outside the grid clamp to the
# edge node and are disclosed via `snapped`; q_hat above the top node
# cannot be bracketed until a higher-q node joins the grid.
lookup_delta_null <- function(k, N, q_hat) {
  # k = 2 is NOT calibrated and must never snap to k = 3: at k = 2 the
  # agreement family is PABAK + AC1, whose implied qualities coincide by
  # construction (delta_hat is identically zero — 2.75M Option-B null
  # draws produced no exception). delta_hat carries no information at
  # k = 2; check_asymmetry() reports not_applicable there.
  if (as.numeric(k) < 3) return(NULL)
  obj <- tryCatch(
    get("delta_null_ecdf", envir = asNamespace("grassr"), inherits = FALSE),
    error = function(e) NULL)
  if (is.null(obj)) return(NULL)
  idx <- obj$index
  ks <- sort(unique(idx$k))
  Ns <- sort(unique(idx$N))
  qs <- sort(unique(idx$q))
  k_node <- ks[which.min(abs(ks - k))]
  q_eff <- min(max(as.numeric(q_hat), qs[1L]), qs[length(qs)])
  N_eff <- min(max(as.numeric(N), Ns[1L]), Ns[length(Ns)])
  # Bracketing nodes and the weight on the upper node; an exact node hit
  # gives weight 0 or 1 and reproduces the stored cell bit-for-bit.
  bracket <- function(nodes, x, transform = identity) {
    i <- findInterval(x, nodes, rightmost.closed = TRUE)
    i <- max(1L, min(i, length(nodes) - 1L))
    lo <- nodes[i]; hi <- nodes[i + 1L]
    w <- (transform(x) - transform(lo)) / (transform(hi) - transform(lo))
    list(lo = lo, hi = hi, w = w)
  }
  qb <- bracket(qs, q_eff)
  Nb <- bracket(Ns, N_eff, transform = log10)
  grid_q <- c(qb$lo, qb$hi, qb$lo, qb$hi)
  grid_N <- c(Nb$lo, Nb$lo, Nb$hi, Nb$hi)
  wts <- c((1 - qb$w) * (1 - Nb$w), qb$w * (1 - Nb$w),
           (1 - qb$w) * Nb$w,       qb$w * Nb$w)
  values <- 0
  n_draws <- integer(0)
  unstable <- FALSE
  for (j in which(wts > 0)) {
    cell_i <- which(idx$k == k_node & idx$N == grid_N[j] & idx$q == grid_q[j])
    if (length(cell_i) != 1L) return(NULL)
    values <- values + wts[j] * obj$values[cell_i, ]
    n_draws <- c(n_draws, idx$n_draws[cell_i])
    unstable <- unstable || isTRUE(idx$unstable_tail[cell_i])
  }
  list(
    k = k_node, N = as.integer(N_eff), q = q_eff,
    n_draws = min(n_draws),
    unstable_tail = unstable,
    # snapped = the resolved design differs from the query (k off the
    # calibrated set, or N / q_hat clamped at a grid edge). Interior
    # off-node queries are served by interpolation, not snapping.
    snapped = (k_node != k || N_eff != as.numeric(N) ||
                 abs(q_eff - as.numeric(q_hat)) > 1e-9),
    interpolated = (qb$w > 0 && qb$w < 1) || (Nb$w > 0 && Nb$w < 1),
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
