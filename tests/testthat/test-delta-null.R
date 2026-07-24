# Tests for the v0.8.0 matched-null lookup: hybrid grid (prevalence-
# resolved + pooled k-fill), integer-delta decode, interpolation in
# q / log10 N / prevalence, mid-p percentile convention.

test_that("lookup_delta_null resolves exact nodes and discloses snaps", {
  cell <- grassr:::lookup_delta_null(k = 5, N = 200, q_hat = 0.85,
                                     pi_hat = 0.5)
  expect_equal(c(cell$k, cell$N), c(5, 200))
  expect_equal(cell$q, 0.85)
  expect_equal(cell$prev, 0.5)
  expect_false(cell$prev_pooled)
  expect_false(cell$snapped)
  expect_false(cell$interpolated)
  expect_gte(cell$n_draws, 44000)
  snap <- grassr:::lookup_delta_null(k = 9, N = 220, q_hat = 0.80,
                                     pi_hat = 0.5)
  expect_true(snap$snapped)
  expect_true(snap$k %in% c(8, 10))
  expect_false(snap$prev_pooled)
})

test_that("exact node hits reproduce the decoded stored cell", {
  obj <- get("delta_null_ecdf", envir = asNamespace("grassr"))
  vals <- grassr:::.delta_null_values(obj)
  i <- which(obj$index$k == 5 & obj$index$N == 200 & obj$index$q == 0.85 &
               !obj$index$prev_pooled & obj$index$prev == 0.5)
  cell <- grassr:::lookup_delta_null(k = 5, N = 200, q_hat = 0.85,
                                     pi_hat = 0.5)
  expect_equal(unname(cell$values), unname(vals[i, ]))
})

test_that("lookup interpolates q, log10 N, and prevalence", {
  lo <- grassr:::lookup_delta_null(5, 200, 0.85, 0.5)
  hi <- grassr:::lookup_delta_null(5, 200, 0.92, 0.5)
  mid <- grassr:::lookup_delta_null(5, 200, 0.885, 0.5)
  expect_true(mid$interpolated); expect_false(mid$snapped)
  w <- (0.885 - 0.85) / (0.92 - 0.85)
  expect_equal(unname(mid$values),
               unname((1 - w) * lo$values + w * hi$values))
  plo <- grassr:::lookup_delta_null(5, 200, 0.85, 0.2)
  pmid <- grassr:::lookup_delta_null(5, 200, 0.85, 0.35)
  wp <- (0.35 - 0.2) / (0.5 - 0.2)
  expect_true(pmid$interpolated)
  expect_equal(unname(pmid$values),
               unname((1 - wp) * plo$values + wp * lo$values))
  nlo <- grassr:::lookup_delta_null(5, 200, 0.85, 0.5)
  nhi <- grassr:::lookup_delta_null(5, 300, 0.85, 0.5)
  noff <- grassr:::lookup_delta_null(5, 220, 0.85, 0.5)
  wn <- (log10(220) - log10(200)) / (log10(300) - log10(200))
  expect_equal(unname(noff$values),
               unname((1 - wn) * nlo$values + wn * nhi$values))
})

test_that("the q = 0.99 node brackets near-ceiling quality", {
  top <- grassr:::lookup_delta_null(5, 200, 0.98, 0.5)
  expect_true(top$interpolated)
  expect_false(top$snapped)
  expect_equal(top$q, 0.98)
  beyond <- grassr:::lookup_delta_null(5, 200, 0.995, 0.5)
  expect_equal(beyond$q, 0.99)
  expect_true(beyond$snapped)
})

test_that("pooled k-fill counts serve exact-k cells with disclosure", {
  cell <- grassr:::lookup_delta_null(k = 4, N = 200, q_hat = 0.85,
                                     pi_hat = 0.5)
  expect_equal(cell$k, 4)
  expect_true(cell$prev_pooled)
  expect_true(is.na(cell$prev))
  # pooled cells have no q = 0.99 node; near-ceiling clamps at 0.97
  top <- grassr:::lookup_delta_null(k = 4, N = 200, q_hat = 0.99,
                                    pi_hat = 0.5)
  expect_equal(top$q, 0.97)
  expect_true(top$snapped)
})

test_that("k = 2 is refused, never snapped", {
  expect_null(grassr:::lookup_delta_null(2, 200, 0.85, 0.5))
})

test_that("delta_null_percentile is monotone and bounded", {
  cell <- grassr:::lookup_delta_null(5, 200, 0.85, 0.5)
  v_lo  <- cell$values[[which.min(abs(cell$probs - 0.05))]]
  v_mid <- cell$values[[which.min(abs(cell$probs - 0.5))]]
  v_hi  <- 2 * max(cell$values) + 1
  p_lo  <- grassr:::delta_null_percentile(v_lo, cell)
  p_mid <- grassr:::delta_null_percentile(v_mid, cell)
  p_hi  <- grassr:::delta_null_percentile(v_hi, cell)
  expect_lt(p_lo, p_mid); expect_lt(p_mid, p_hi)
  expect_gt(p_mid, 40); expect_lt(p_mid, 60)
  expect_lte(p_hi, 99.5 + 1e-9)
})

test_that("delta_null_percentile applies the MID-P convention at plateaus", {
  cell <- list(values = c(0, 0, 0, 0.5, 1),
               probs  = c(0.01, 0.05, 0.10, 0.5, 0.99))
  expect_equal(grassr:::delta_null_percentile(0, cell), 5)
  expect_equal(grassr:::delta_null_percentile(-1, cell), 5)
  cell0 <- list(values = rep(0, 5), probs = c(0.01, 0.05, 0.10, 0.5, 0.995))
  expect_lt(grassr:::delta_null_percentile(0, cell0), 60)
})

test_that("flag conventions map percentiles correctly", {
  f <- grassr:::delta_flag_from_percentile
  expect_equal(f(50), "aligned")
  expect_equal(f(96), "caution")
  expect_equal(f(99.2), "divergent")
  expect_equal(f(NA_real_), "not_calibrated")
})

test_that("check_asymmetry emits matched-null fields with prevalence", {
  set.seed(11)
  Y <- matrix(rbinom(500 * 5, 1, 0.5), 500, 5)
  a <- check_asymmetry(Y)
  expect_true(is.finite(a$delta_percentile))
  expect_equal(a$thresholds_source, "matched_null_ecdf")
  expect_named(a$thresholds, c("caution", "divergent"))
  expect_false(a$matched_null$prev_pooled)
  expect_equal(a$matched_null$prev_apparent, mean(Y))
  # mid-prevalence: the bridge barely moves the estimate
  expect_lt(abs(a$matched_null$prev - mean(Y)), 0.05)
})

test_that("the lookup conditions on bridged true prevalence, not apparent", {
  # true pi = 0.15, q = 0.87 -> apparent ~ 0.24; the bridge must recover
  # ~0.15 (G2 Tier B verdict 2026-07-24: bridged holds realized flag
  # size at nominal at skewed prevalence; raw runs ~2x)
  set.seed(42)
  N <- 2000L; k <- 5L; q <- 0.87
  z <- rbinom(N, 1L, 0.15)
  Y <- matrix(rbinom(N * k, 1L, ifelse(z == 1L, q, 1 - q)), N, k)
  a <- check_asymmetry(Y)
  expect_true(a$matched_null$prev_bridged)
  expect_lt(a$matched_null$prev, a$matched_null$prev_apparent)
  expect_lt(abs(a$matched_null$prev - 0.15), 0.04)
})

test_that("the bridge falls back to apparent prevalence at degenerate quality", {
  # near-chance raters: 2q - 1 ~ 0; inversion must not amplify noise
  set.seed(7)
  Y <- matrix(rbinom(200 * 5, 1L, 0.5), 200, 5)
  a <- check_asymmetry(Y)
  qh <- a$matched_null$q_hat_panel
  if (is.finite(qh) && (2 * qh - 1) <= 0.10) {
    expect_false(a$matched_null$prev_bridged)
    expect_equal(a$matched_null$prev, a$matched_null$prev_apparent)
  } else succeed("panel estimated above the fallback band; covered elsewhere")
})
