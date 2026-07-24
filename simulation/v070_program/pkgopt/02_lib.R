# Package-structure optimization — encoding + scoring library (v2).
#
# A candidate encoding is (anchor set, knot set, quantization, layout).
# Decoding reconstructs each truth cell's full quantile vector; scoring
# measures error in OUTPUT units — the percentile the package would
# report, read with the shipped MID-P tie convention — never raw
# quantile RMSE. Bytes are measured honestly: the object a candidate
# would ship is built and saved with xz, and the file size is the rate.
#
# v2 fixes (validated against the v1 prelim run):
# - dropped-cell reconstruction searches outward for the smallest
#   axis-aligned box whose corners are ALL retained (v1 bracketed on
#   marginal availability and returned NA for every free-form drop);
# - percentile reads replicate delta_null_percentile's mid-p tie
#   handling (v1's plain interpolation penalized plateau cells by half
#   the plateau mass — a 5 pp phantom error on the exact baseline);
# - low-rank reconstruction is clamped nonnegative before
#   re-monotonizing; MC-SE ratios carry a 1e-6 delta-unit floor.

# ---- knot sets -----------------------------------------------------------
knots_tailweighted <- function(m, probs) {
  fixed <- c(0.5, 0.95, 0.99, min(probs), max(probs))
  n_tail <- ceiling((m - length(fixed)) / 2)
  n_body <- (m - length(fixed)) - n_tail
  body <- seq(min(probs), 0.90, length.out = n_body + 2L)[-c(1L, n_body + 2L)]
  tail <- seq(0.90, max(probs), length.out = n_tail + 2L)[-c(1L, n_tail + 2L)]
  snap <- function(x) probs[vapply(x, function(z)
    which.min(abs(probs - z)), integer(1L))]
  sort(unique(snap(c(fixed, body, tail))))
}

# ---- quantization --------------------------------------------------------
quant_signif <- function(digits) list(
  name = sprintf("signif%d", digits),
  pack = function(v) signif(v, digits),
  unpack = identity
)
quant_intdelta <- function(levels = 32767) list(
  name = sprintf("intdelta%d", levels),
  pack = function(v) {
    d <- t(apply(v, 1L, function(x) diff(c(0, x))))
    sc <- apply(d, 1L, max) / levels
    sc[sc == 0] <- 1
    list(scale = signif(sc, 6),
         ints = matrix(as.integer(round(sweep(d, 1L, sc, "/"))), nrow(v)))
  },
  unpack = function(o) t(apply(sweep(o$ints, 1L, o$scale, "*"), 1L, cumsum))
)
# Dictionary / value-pooling (Austin's layout, 2026-07-23): quantize,
# store each unique value once, ship integer codes into the dictionary.
# Exact for the discrete small-N cells where achievable delta values form
# a finite set that recurs within and across cells.
quant_dict <- function(digits = 5) list(
  name = sprintf("dict%d", digits),
  pack = function(v) {
    q <- signif(v, digits)
    u <- sort(unique(as.vector(q)))
    list(values = u,
         codes = matrix(match(as.vector(q), u), nrow(q)))
  },
  unpack = function(o) matrix(o$values[o$codes], nrow(o$codes))
)
quant_lowrank <- function(rank, levels = 32767) list(
  name = sprintf("rank%d", rank),
  pack = function(v) {
    ctr <- colMeans(v)
    s <- svd(sweep(v, 2L, ctr), nu = rank, nv = rank)
    scores <- s$u %*% diag(s$d[seq_len(rank)], rank)
    sc <- apply(abs(scores), 2L, max) / levels
    sc[sc == 0] <- 1
    list(center = ctr, basis = s$v[, seq_len(rank), drop = FALSE], scale = sc,
         ints = matrix(as.integer(round(sweep(scores, 2L, sc, "/"))), nrow(v)))
  },
  unpack = function(o) {
    v <- sweep(o$ints, 2L, o$scale, "*") %*% t(o$basis)
    v <- pmax(sweep(v, 2L, o$center, "+"), 0)
    t(apply(v, 1L, cummax))
  }
)

# ---- encode / decode -----------------------------------------------------
encode <- function(truth, anchors, knot_idx, quant) {
  list(
    meta = truth$index[anchors, c("k", "N", "q", "prev")],
    anchors = which(anchors),
    probs = truth$probs[knot_idx],
    payload = quant$pack(truth$values[anchors, knot_idx, drop = FALSE])
  )
}
object_bytes <- function(obj, tag) {
  f <- file.path(tempdir(), paste0("pkgopt_", tag, ".rda"))
  save(obj, file = f, compress = "xz")
  on.exit(unlink(f))
  file.size(f)
}

# Axis candidate (lo, hi) node pairs for a grid value x, ordered by
# spread: exact hit first, then strict brackets widening outward,
# asymmetric depths included (needed when several consecutive nodes on
# one side are dropped).
.axis_pairs <- function(nodes, x, max_out = 3L) {
  below <- rev(nodes[nodes < x]); above <- nodes[nodes > x]
  pairs <- list(c(x, x)); depth <- 0
  for (s in 2:(2 * max_out)) for (i in seq_len(min(s - 1L, length(below)))) {
    j <- s - i
    if (j >= 1L && j <= length(above)) {
      pairs[[length(pairs) + 1L]] <- c(below[i], above[j])
      depth <- c(depth, s)
    }
  }
  list(pairs = pairs, depth = depth)
}

# Reconstruct one dropped cell from retained cells: smallest axis-aligned
# box (by total bracket depth over the three interpolable axes) whose
# corners are all retained; ties at the minimal depth are averaged.
# Weights are trilinear in (log10 N, q, prev) at fixed k — the operator
# class lookup_delta_null uses at query time.
.recon_cell <- function(truth, i, is_anchor, value_row) {
  k <- truth$index$k[i]; kc <- as.character(k)
  Np <- .axis_pairs(truth$Ns, truth$index$N[i])
  qp <- .axis_pairs(truth$qs, truth$index$q[i])
  pp <- .axis_pairs(truth$prevs, truth$index$prev[i])
  combos <- expand.grid(a = seq_along(Np$pairs), b = seq_along(qp$pairs),
                        c = seq_along(pp$pairs))
  combos$deg <- Np$depth[combos$a] + qp$depth[combos$b] + pp$depth[combos$c]
  combos <- combos[combos$deg > 0L, , drop = FALSE]  # deg 0 = the cell itself
  combos <- combos[order(combos$deg), , drop = FALSE]
  best_deg <- NA_integer_; acc <- NULL; n_ok <- 0L
  for (r in seq_len(nrow(combos))) {
    if (!is.na(best_deg) && combos$deg[r] > best_deg) break
    Nb <- Np$pairs[[combos$a[r]]]; qb <- qp$pairs[[combos$b[r]]]
    pb <- pp$pairs[[combos$c[r]]]
    corners <- expand.grid(N = unique(Nb), q = unique(qb), p = unique(pb))
    ci <- mapply(function(Nn, qn, pn)
      truth$cell_id[as.character(Nn), as.character(qn),
                    as.character(pn), kc],
      corners$N, corners$q, corners$p)
    if (!all(is_anchor[ci])) next
    wN <- if (Nb[1] == Nb[2]) 1 else
      (log10(truth$index$N[i]) - log10(Nb[1])) / (log10(Nb[2]) - log10(Nb[1]))
    wq <- if (qb[1] == qb[2]) 1 else
      (truth$index$q[i] - qb[1]) / (qb[2] - qb[1])
    wp <- if (pb[1] == pb[2]) 1 else
      (truth$index$prev[i] - pb[1]) / (pb[2] - pb[1])
    v <- 0
    for (j in seq_len(nrow(corners))) {
      w <- (if (corners$N[j] == Nb[1] && Nb[1] != Nb[2]) 1 - wN else if (Nb[1] != Nb[2]) wN else 1) *
        (if (corners$q[j] == qb[1] && qb[1] != qb[2]) 1 - wq else if (qb[1] != qb[2]) wq else 1) *
        (if (corners$p[j] == pb[1] && pb[1] != pb[2]) 1 - wp else if (pb[1] != pb[2]) wp else 1)
      v <- v + w * value_row(ci[j])
    }
    if (is.na(best_deg)) best_deg <- combos$deg[r]
    acc <- if (is.null(acc)) v else acc + v
    n_ok <- n_ok + 1L
  }
  if (n_ok == 0L) return(NULL)
  acc / n_ok
}

# Decode to the candidate's NATIVE knot grid (n_cells x n_knots). The
# package reads the stored grid directly (delta_null_percentile), so
# scoring must too — interpolating up to the fine grid first destroys
# tie runs and misreads plateau cells.
decode_all <- function(truth, enc, quant) {
  kv <- quant$unpack(enc$payload)
  n <- nrow(truth$index)
  is_anchor <- logical(n); is_anchor[enc$anchors] <- TRUE
  row_of <- integer(n); row_of[enc$anchors] <- seq_along(enc$anchors)
  out <- matrix(NA_real_, n, ncol(kv))
  out[enc$anchors, ] <- kv
  value_row <- function(ci) kv[row_of[ci], ]
  for (i in which(!is_anchor)) {
    v <- .recon_cell(truth, i, is_anchor, value_row)
    if (!is.null(v)) out[i, ] <- v
  }
  out
}

# ---- percentile reader (mid-p, mirrors delta_null_percentile) ------------
pct_midp <- function(v, p, x, tol = 1e-12) {
  n <- length(v)
  if (x <= v[1L] + tol) {
    run_top <- max(which(v <= v[1L] + tol))
    return(100 * 0.5 * p[run_top])
  }
  if (x >= v[n] - tol) {
    if (x > v[n] + tol) return(100 * p[n])
    run_bot <- min(which(v >= v[n] - tol))
    lo <- if (run_bot == 1L) 0 else p[run_bot - 1L]
    return(100 * 0.5 * (lo + p[n]))
  }
  ties_at <- which(abs(v - x) <= tol)
  if (length(ties_at) > 1L) {
    lo <- if (min(ties_at) == 1L) 0 else p[min(ties_at) - 1L]
    return(100 * 0.5 * (lo + p[max(ties_at)]))
  }
  100 * stats::approx(x = v, y = p, xout = x, rule = 2, ties = "ordered")$y
}

# ---- scoring -------------------------------------------------------------
# Per-cell output-unit errors. Candidate reads happen on its native knot
# grid (as the package would); truth reads on the fine grid.
#  pct_shift_max: worst |mid-p read on recon knots − mid-p read on fine
#                 truth| over probe deltas (truth quantiles .50/.90/.95/.99)
#  cut95/99_pp:   flag-cut displacement, delta units
#  cut95/99_se:   same in MC-SE units (SE floored at 1e-6 delta units)
#  size95/99:     realized flag size using the recon cut against the
#                 truth distribution (nominal .05/.01), mid-p read
score_cells <- function(truth, recon, kprobs, probes = c(0.5, 0.9, 0.95, 0.99)) {
  pr <- truth$probs
  pi_ <- vapply(probes, function(p) which.min(abs(pr - p)), integer(1))
  i95 <- which.min(abs(pr - 0.95)); i99 <- which.min(abs(pr - 0.99))
  j95 <- which.min(abs(kprobs - 0.95)); j99 <- which.min(abs(kprobs - 0.99))
  stopifnot(abs(kprobs[j95] - 0.95) < 1e-9, abs(kprobs[j99] - 0.99) < 1e-9)
  n <- nrow(truth$values)
  out <- data.frame(pct_shift_max = rep(NA_real_, n), cut95_pp = NA_real_,
                    cut99_pp = NA_real_, cut95_se = NA_real_,
                    cut99_se = NA_real_, size95 = NA_real_, size99 = NA_real_)
  for (i in seq_len(n)) {
    vt <- truth$values[i, ]; vr <- recon[i, ]
    if (anyNA(vr)) next
    shifts <- vapply(vt[pi_], function(x)
      abs(pct_midp(vr, kprobs, x) - pct_midp(vt, pr, x)), numeric(1))
    out$pct_shift_max[i] <- max(shifts)
    out$cut95_pp[i] <- abs(vr[j95] - vt[i95])
    out$cut99_pp[i] <- abs(vr[j99] - vt[i99])
    out$cut95_se[i] <- out$cut95_pp[i] / max(truth$mcse[i, i95], 1e-6)
    out$cut99_se[i] <- out$cut99_pp[i] / max(truth$mcse[i, i99], 1e-6)
    out$size95[i] <- 1 - pct_midp(vt, pr, vr[j95]) / 100
    out$size99[i] <- 1 - pct_midp(vt, pr, vr[j99]) / 100
  }
  out
}

summarize_candidate <- function(tag, bytes, sc, truth) {
  ok <- !is.na(sc$pct_shift_max)
  wc_i <- which.max(ifelse(ok, sc$pct_shift_max, -Inf))
  data.frame(
    candidate = tag, kb = round(bytes / 1024, 1),
    pct_shift_wc = max(sc$pct_shift_max[ok]),
    pct_shift_mean = mean(sc$pct_shift_max[ok]),
    cut95_se_wc = max(sc$cut95_se[ok]),
    cut95_pp_wc = max(sc$cut95_pp[ok]),
    size95_lo = min(sc$size95[ok]), size95_hi = max(sc$size95[ok]),
    size99_hi = max(sc$size99[ok]),
    n_cells_na = sum(!ok),
    wc_cell = sprintf("k%d/N%d/q%.2f/pv%.2f", truth$index$k[wc_i],
                      truth$index$N[wc_i], truth$index$q[wc_i],
                      truth$index$prev[wc_i])
  )
}

run_candidate <- function(truth, tag, anchors, knot_idx, quant) {
  enc <- encode(truth, anchors, knot_idx, quant)
  bytes <- object_bytes(enc, tag)
  recon <- decode_all(truth, enc, quant)
  s <- summarize_candidate(tag, bytes,
                           score_cells(truth, recon, truth$probs[knot_idx]),
                           truth)
  s$n_anchor <- sum(anchors); s$n_knots <- length(knot_idx)
  s
}
