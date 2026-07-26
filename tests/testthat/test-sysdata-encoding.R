# v0.8.0 stores the two large reference arrays as integer-delta byte planes
# (R/sysdata-encoding.R). Reconstruction must be exact -- if it drifts, every
# percentile, band, and field-case number in the paper drifts with it. The
# anchor sums and cell values below were captured from the plain-double
# sysdata that shipped through v0.7.4
# (data-raw/sysdata_plaindouble_v0.8.0.rda).

test_that("surface quantiles decode to the v0.7.4 plain-double array", {
  surf <- get("empirical_q_hat_surface",
              envir = asNamespace("grassr"), inherits = FALSE)
  q <- grassr:::surface_quantiles(surf)

  expect_equal(dim(q), c(44616L, 5L, 13L))
  expect_equal(dimnames(q)[[2]],
               c("pabak", "fleiss_kappa", "mean_ac1", "krippendorff_a", "icc"))
  # Checksum on the integer lattice: exact in double arithmetic (< 2^53),
  # platform-independent, and moved by any single-cell change.
  expect_equal(sum(round(q * 1e5)), 234186667189, tolerance = 0)
  expect_equal(q[1L, 1L, 1L], 0.50000, tolerance = 0)
  expect_equal(q[44616L, 5L, 13L], 0.99382, tolerance = 0)
  expect_equal(q[20000L, 3L, 7L], 0.94072, tolerance = 0)
})

test_that("fitted ICC curves decode to the v0.7.4 plain-double array", {
  bundle <- get("fitted_icc_reference_curves",
                envir = asNamespace("grassr"), inherits = FALSE)
  cv <- grassr:::fitted_icc_curves(bundle)

  expect_equal(dim(cv), c(52L, 5L, 8L, 501L))
  expect_equal(sum(round(cv * 1e5)), 35406820784, tolerance = 0)
  expect_equal(cv[1L, 1L, 1L, 1L], 0.09893, tolerance = 0)
  expect_equal(cv[52L, 5L, 8L, 501L], 0.95129, tolerance = 0)
  expect_equal(cv[26L, 3L, 4L, 250L], 0.24769, tolerance = 0)
})

test_that("the encoder is the exact inverse of the decoder", {
  surf <- get("empirical_q_hat_surface",
              envir = asNamespace("grassr"), inherits = FALSE)
  enc <- surf[["quantiles_enc", exact = TRUE]]
  skip_if(is.null(enc), "sysdata ships unencoded arrays")

  round_trip <- grassr:::encode_int_delta_array(
    grassr:::decode_int_delta_array(enc),
    scale = enc$scale, delta_axis = enc$delta_axis)
  expect_identical(round_trip$hi, enc$hi)
  expect_identical(round_trip$lo, enc$lo)
  expect_identical(round_trip$offset, enc$offset)
})

test_that("decoded values keep the 1e-5 lattice and prob-axis monotonicity", {
  surf <- get("empirical_q_hat_surface",
              envir = asNamespace("grassr"), inherits = FALSE)
  q <- grassr:::surface_quantiles(surf)

  expect_true(all(abs(q * 1e5 - round(q * 1e5)) < 1e-6))
  expect_true(all(q >= 0.5 & q <= 1))
  expect_true(all(q[, , -1L] - q[, , -13L] >= 0))
})

test_that("the decode cache returns the same object on repeat access", {
  surf <- get("empirical_q_hat_surface",
              envir = asNamespace("grassr"), inherits = FALSE)
  expect_identical(grassr:::surface_quantiles(surf),
                   grassr:::surface_quantiles(surf))
})

test_that("encode_int_delta_array() refuses lossy or non-monotone input", {
  x <- array(c(0.5, 0.500004), dim = c(1L, 2L))   # off the 1e-5 lattice
  expect_error(grassr:::encode_int_delta_array(x, scale = 1e5, delta_axis = 2L),
               "exact multiples")

  y <- array(c(0.6, 0.5), dim = c(1L, 2L))        # decreasing along the axis
  expect_error(grassr:::encode_int_delta_array(y, scale = 1e5, delta_axis = 2L),
               "monotone")
})
