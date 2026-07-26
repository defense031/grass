# Re-encode the two large bundled arrays into their compact stored form
# (v0.8.0). Bit-exact: every reconstructed value is identical() to the value
# that shipped through v0.7.4, so no card number, band, or field-case result
# moves. See design/v0.8.0_surface_encoding.md for the measured frontier and
# R/sysdata-encoding.R for the format.
#
# Run from the package root:  Rscript data-raw/encode_sysdata_for_release.R
#
# What changes in sysdata.rda:
#   empirical_q_hat_surface$quantiles  -> $quantiles_enc   (4,314 -> 2,862 KB)
#   empirical_q_hat_surface$mean, $sd  -> dropped          (761 -> 0 KB)
#   fitted_icc_reference_curves$curves -> $curves_enc      (1,578 -> 163 KB)
#
# $mean and $sd have no reader in R/, tests/, or vignettes/ -- they are
# build products the release object never consulted. They are retained in
# the pre-encoding archive written below.

stopifnot(file.exists("DESCRIPTION"), file.exists("R/sysdata.rda"))
source("R/sysdata-encoding.R")

archive <- "data-raw/sysdata_plaindouble_v0.8.0.rda"
if (!file.exists(archive)) {
  file.copy("R/sysdata.rda", archive)
  cat("archived pre-encoding sysdata ->", archive, "\n")
} else {
  cat("pre-encoding archive already present ->", archive, "\n")
}

e <- new.env()
load(archive, envir = e)
objs <- ls(e)

kb <- function(x) {
  p <- tempfile(fileext = ".rds"); on.exit(unlink(p))
  saveRDS(x, p, compress = "xz"); round(file.size(p) / 1024)
}

## ---- empirical_q_hat_surface --------------------------------------------
surf <- e$empirical_q_hat_surface
q_before <- surf$quantiles
enc_q <- encode_int_delta_array(q_before, scale = 1e5, delta_axis = 3L)
stopifnot(identical(decode_int_delta_array(enc_q), q_before))
cat(sprintf("surface quantiles: %d -> %d KB (bit-exact)\n",
            kb(q_before), kb(enc_q)))

surf$quantiles_enc <- enc_q
surf$quantiles <- NULL
surf$mean <- NULL
surf$sd <- NULL
surf$encoding_note <- paste(
  "quantiles stored as int-delta-byteplane-v1 (see R/sysdata-encoding.R);",
  "reconstruction is exact. $mean and $sd dropped at v0.8.0 -- unused by the",
  "package; retained in data-raw/sysdata_plaindouble_v0.8.0.rda."
)
e$empirical_q_hat_surface <- surf

## ---- fitted_icc_reference_curves ----------------------------------------
icc <- e$fitted_icc_reference_curves
c_before <- icc$curves
enc_c <- encode_int_delta_array(c_before, scale = 1e5, delta_axis = 4L)
stopifnot(identical(decode_int_delta_array(enc_c), c_before))
cat(sprintf("fitted ICC curves: %d -> %d KB (bit-exact)\n",
            kb(c_before), kb(enc_c)))

icc$curves_enc <- enc_c
icc$curves <- NULL
icc$encoding_note <- paste(
  "curves stored as int-delta-byteplane-v1 (see R/sysdata-encoding.R);",
  "reconstruction is exact."
)
e$fitted_icc_reference_curves <- icc

## ---- write --------------------------------------------------------------
before <- file.size("R/sysdata.rda")
save(list = objs, envir = e, file = "R/sysdata.rda",
     compress = "xz", compression_level = 9)
after <- file.size("R/sysdata.rda")
cat(sprintf("\nsysdata.rda: %.2f -> %.2f MB (%.1f%% smaller)\n",
            before / 1e6, after / 1e6, 100 * (1 - after / before)))

## ---- verify against the archive -----------------------------------------
v <- new.env(); load("R/sysdata.rda", envir = v)
stopifnot(identical(sort(ls(v)), sort(objs)))
stopifnot(identical(decode_int_delta_array(v$empirical_q_hat_surface$quantiles_enc),
                    q_before))
stopifnot(identical(decode_int_delta_array(v$fitted_icc_reference_curves$curves_enc),
                    c_before))
stopifnot(identical(v$empirical_q_hat_surface$index, e$empirical_q_hat_surface$index))
stopifnot(identical(v$delta_null_ecdf, e$delta_null_ecdf))
cat("round-trip verified against the archive: both arrays bit-exact.\n")
