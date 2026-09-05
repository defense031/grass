# Fixes from the 2026-09-05 usability test and three-reader cold read of the
# vignette. Each test pins a behavior a first-time user tripped on.

.cr_panel <- function(seed = 2026L, N = 120L, k = 4L, prev = 0.25,
                      Se = c(0.90, 0.92, 0.88, 0.90),
                      Sp = c(0.90, 0.88, 0.91, 0.62)) {
  set.seed(seed)
  truth <- rbinom(N, 1, prev)
  Y <- sapply(seq_len(k), function(j)
    ifelse(truth == 1, rbinom(N, 1, Se[j]), rbinom(N, 1, 1 - Sp[j])))
  colnames(Y) <- c("A", "B", "C", "D")
  Y
}

test_that("factor labels that read as a positive call are recognized", {
  Y <- .cr_panel()
  d <- as.data.frame(lapply(as.data.frame(Y), function(v)
    factor(ifelse(v == 1L, "present", "absent"))))
  expect_equal(unname(normalize_ratings(d)), unname(Y))
  d2 <- as.data.frame(lapply(as.data.frame(Y), function(v)
    factor(ifelse(v == 1L, "Yes", "No"))))
  expect_equal(unname(normalize_ratings(d2)), unname(Y))
})

test_that("character columns are accepted under the same rule", {
  Y <- .cr_panel()
  d <- as.data.frame(lapply(as.data.frame(Y), function(v)
    ifelse(v == 1L, "positive", "negative")), stringsAsFactors = FALSE)
  expect_equal(unname(normalize_ratings(d)), unname(Y))
})

test_that("unrecognizable labels stop instead of silently inverting", {
  Y <- .cr_panel()
  d <- as.data.frame(lapply(as.data.frame(Y), function(v)
    factor(ifelse(v == 1L, "dehisced", "intact"))))
  expect_error(normalize_ratings(d), "Cannot tell which level")
  expect_error(grass_report(d, bootstrap_B = 10), "Cannot tell which level")
})

test_that("summary() shows bands as suppressed on a divergent card", {
  Y <- .cr_panel()
  card <- grass_report(Y, bootstrap_B = 25)
  skip_if_not(identical(card$delta$flag, "divergent"),
              "panel did not flag divergent under the installed null")
  txt <- capture.output(summary(card))
  expect_true(any(grepl("band suppressed (divergent)", txt, fixed = TRUE)))
  expect_false(any(grepl("quality 0\\.[0-9]+-0\\.[0-9]+", txt)))
})

test_that("latent-class table uses the column names as rater labels", {
  Y <- .cr_panel()
  card <- grass_report(Y, bootstrap_B = 25)
  skip_if_not(!is.null(card$per_rater) && nrow(card$per_rater) > 0L,
              "no per-rater table on this card")
  expect_setequal(as.character(card$per_rater$rater), colnames(Y))
})

test_that("card strings no longer carry the retired vocabulary", {
  Y <- .cr_panel()
  card <- grass_report(Y, bootstrap_B = 25)
  txt <- paste(capture.output(print(card)), collapse = "\n")
  for (bad in c("panel-agg.", "pooled-reference", "alongside pairwise",
                "pairwise/bounds path", "clamped to nearest sim-grid",
                "agreed more tightly", "do not need")) {
    expect_false(grepl(bad, txt, fixed = TRUE), info = bad)
  }
})
