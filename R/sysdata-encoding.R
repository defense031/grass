# Compact storage for the two large bundled reference arrays.
#
# `empirical_q_hat_surface$quantiles` (44,616 x 5 x 13) and
# `fitted_icc_reference_curves$curves` (52 x 5 x 8 x 501) together account
# for roughly 5.9 MB of the shipped sysdata as plain doubles. Both hold
# values that are exact multiples of 1e-5 -- the surface because the release
# build rounds to five decimals, the ICC curves because they were built and
# stored the same way -- so a double is spending 64 bits on a quantity with
# at most 17 bits of content.
#
# The stored form scales each array to integers, takes first differences
# along the one axis it is monotone in (the probability axis for the
# surface, the q-grid axis for the ICC curves), and splits the resulting
# non-negative 16-bit values into two raw byte planes. xz compresses the
# planes far better than it compresses IEEE doubles. Reconstruction is
# exact: `decode_int_delta_array()` returns a double array `identical()` to
# the one that was encoded, so no bundled number moves.
#
# Cross-cell delta coding was measured and rejected. Adjacent surface cells
# are independent 2,000-replicate simulations, so differencing along k, N,
# q_true, or scenario adds noise rather than removing redundancy. See
# design/v0.8.0_surface_encoding.md for the measured frontier.

.sysdata_cache <- new.env(parent = emptyenv())

.sd_memo <- function(key, expr) {
  if (exists(key, envir = .sysdata_cache, inherits = FALSE))
    return(get(key, envir = .sysdata_cache, inherits = FALSE))
  val <- expr
  assign(key, val, envir = .sysdata_cache, inherits = FALSE)
  val
}

# Encode a numeric array whose entries are exact multiples of 1/scale and
# which is non-decreasing along `delta_axis`. Errors rather than losing
# precision: an array that violates either property is a build-time defect,
# not something to silently round. Called only from
# data-raw/encode_sysdata_for_release.R.
encode_int_delta_array <- function(x, scale = 1e5, delta_axis = length(dim(x))) {
  stopifnot(is.array(x), is.numeric(x), all(is.finite(x)))
  ix <- round(x * scale)
  if (max(abs(x - ix / scale)) > 0) {
    stop("encode_int_delta_array(): values are not exact multiples of 1/scale.",
         call. = FALSE)
  }
  offset <- as.integer(min(ix))
  a <- array(as.integer(ix) - offset, dim = dim(x))

  n <- dim(a)[delta_axis]
  ii <- lapply(dim(a), seq_len)
  hi_i <- ii; hi_i[[delta_axis]] <- 2:n
  lo_i <- ii; lo_i[[delta_axis]] <- 1:(n - 1L)
  d <- do.call(`[`, c(list(a), hi_i, list(drop = FALSE))) -
       do.call(`[`, c(list(a), lo_i, list(drop = FALSE)))
  if (min(d) < 0) {
    stop("encode_int_delta_array(): array is not monotone along delta_axis.",
         call. = FALSE)
  }
  a <- do.call(`[<-`, c(list(a), hi_i, list(value = d)))

  if (max(a) > 65535L) {
    stop("encode_int_delta_array(): delta exceeds the 16-bit plane range.",
         call. = FALSE)
  }
  list(
    .encoding  = "int-delta-byteplane-v1",
    scale      = scale,
    offset     = offset,
    delta_axis = as.integer(delta_axis),
    dim        = dim(x),
    dimnames   = dimnames(x),
    hi         = as.raw(a %/% 256L),
    lo         = as.raw(a %% 256L)
  )
}

# Inverse of encode_int_delta_array(). Returns a double array identical to
# the input the encoder saw.
decode_int_delta_array <- function(enc) {
  if (!identical(enc$.encoding, "int-delta-byteplane-v1")) {
    stop("decode_int_delta_array(): unrecognised encoding '",
         enc$.encoding, "'.", call. = FALSE)
  }
  a <- array(as.integer(enc$hi) * 256L + as.integer(enc$lo), dim = enc$dim)

  ax <- enc$delta_axis
  n <- enc$dim[ax]
  ii <- lapply(enc$dim, seq_len)
  for (j in 2:n) {
    cur <- ii; cur[[ax]] <- j
    prv <- ii; prv[[ax]] <- j - 1L
    a <- do.call(`[<-`, c(list(a), cur, list(
      value = do.call(`[`, c(list(a), prv, list(drop = FALSE))) +
              do.call(`[`, c(list(a), cur, list(drop = FALSE)))
    )))
  }
  array((a + enc$offset) / enc$scale, dim = enc$dim, dimnames = enc$dimnames)
}

# Accessor for the surface quantile array. Decodes once per session
# (~60 ms) and caches; every caller sees the same double array the package
# shipped as plain doubles through v0.7.4.
#
# Both accessors index with [[exact = TRUE]] rather than `$`: the encoded
# element name extends the plain one ("quantiles_enc" vs "quantiles"), and
# `$` partial-matches, so `surf$quantiles` on an encoded object would
# silently return the raw byte planes.
surface_quantiles <- function(surf) {
  plain <- surf[["quantiles", exact = TRUE]]
  if (!is.null(plain)) return(plain)                     # unencoded fallback
  .sd_memo("empirical_q_hat_surface$quantiles",
           decode_int_delta_array(surf[["quantiles_enc", exact = TRUE]]))
}

# Accessor for the fitted-ICC reference curve array.
fitted_icc_curves <- function(bundle) {
  plain <- bundle[["curves", exact = TRUE]]
  if (!is.null(plain)) return(plain)                     # unencoded fallback
  .sd_memo("fitted_icc_reference_curves$curves",
           decode_int_delta_array(bundle[["curves_enc", exact = TRUE]]))
}
