# grassr

**G**uide for **R**ater **A**greement under **S**tructural **S**kew.

Fixed labels for rater-reliability coefficients, the Landis-Koch bands
and their descendants, drift with prevalence, rater count, and sample
size: the same rater panel can land in a different category because the
finding got rarer. grassr replaces the fixed scale with a calibrated
reference. The rating matrix goes in, and a Report Card comes out that
positions each coefficient among the values the study's own design can
produce, bounds the panel qualities consistent with the observation,
and flags panels whose coefficients disagree about the quality they
imply.

## Install

```r
install.packages("grassr")                    # CRAN release (0.7.4)

remotes::install_github("defense031/grassr")  # development head (0.8.0)
```

## A 30-second example

```r
library(grassr)
set.seed(29)

# Five raters, 200 subjects, Se = Sp = 0.85, prevalence 0.30.
truth <- rbinom(200, 1, 0.30)
Y <- sapply(1:5, function(j) {
  ifelse(truth == 1, rbinom(200, 1, 0.85), rbinom(200, 1, 0.15))
})

grass_report(ratings = Y)
```

```
GRASS Report Card

  sample      = 5 raters, N = 200, pi_hat = 0.35
  PABAK        = 0.41  ->  62nd percentile | quality 0.78-0.85  <- primary
  AC1          = 0.46  ->  62nd percentile | quality 0.77-0.85
  Fleiss kappa = 0.36  ->  62nd percentile | quality 0.77-0.85
  ICC          = 0.46  ->  61st percentile | quality 0.76-0.85  [distribution-sensitive]
  read: this panel agreed more tightly than 62% of what panels at this
        design can produce; the data are consistent with panel quality 0.78-0.85.
  delta       = 0.01 pp implied-quality spread (aligned)
  matched null = (k=5, N=200, q=0.82): delta_hat at the 27.1 percentile

  See `summary(...)` for full panel and CI details.
  See `plot(...)` for a surface-position visualization.
```

The percentile reads against a reference calibrated at the study's
rater count, sample size, and observed positive rate, not against a
fixed cutoff table. The consistency band (quality 0.78 to 0.85, which
contains the planted 0.85) is the set of panel qualities consistent
with the observed coefficient at this design; its width is the
precision this design can achieve. `delta = 0.01 pp (aligned)` means the three
agreement coefficients imply the same panel quality, so any one of
them can be cited as the panel's agreement level. When they diverge, the card suppresses the panel summary
and routes to per-rater output: a pairwise PABAK matrix,
pooled-reference sensitivity and specificity per rater, and a
latent-class fit.

## The functions

- `grass_report(ratings = Y)` returns the card. `summary()`,
  `as.data.frame()`, and seven `plot()` views are available on the
  result.
- `position_on_surface(ratings = Y, metric = ...)` positions one
  coefficient and returns its percentile, consistency band, and
  implied quality.
- `check_asymmetry(ratings = Y)` returns the implied-quality spread
  `delta_hat` and its aligned / caution / divergent flag, read from
  the spread's percentile on a null distribution matched to the
  design (caution at the 95th percentile, divergent at the 99th).
- `pairwise_agreement(ratings = Y)` gives the per-rater breakdown
  when the coefficients diverge.
- `latent_class_fit(ratings = Y)` returns per-rater Dawid-Skene
  estimates at k >= 3 and Hui-Walter bounds at k = 2, with bootstrap
  intervals.
- `plot_surface(metric, ...)` draws a coefficient's reference surface
  before any data exist, for prospective design.

The full walkthrough is `vignette("grassr")`.

## Calibration

The bundled reference holds 44,616 surface cells at 2,000 draws each
and an 11,616-cell null lattice for `delta_hat` at 50,000 draws each,
spanning rater counts 2 through 25 and sample sizes 15 through 1,000.
Designs between calibrated cells are read by interpolation; rater
count snaps to the nearest calibrated value, and the card discloses
the cell it read. ICC is reported beside the agreement family with a
`[distribution-sensitive]` marker: its reference depends on the full
subject-prevalence distribution, represented by 52 calibrated
profiles, and it stays out of `delta_hat`.

## Status

v0.8.0 (development head): the `delta_hat` null now varies with
prevalence, and lookups interpolate between calibrated cells. v0.7.4 is the release on CRAN. Binary
inter-rater and intra-rater families are implemented; `?grass_roadmap`
lists planned families (ordinal, multi-rater nominal, continuous), and
`NEWS.md` has the release history.

The package implements the method of Semmel & Gidaro (2026), *A context-conditioned
reporting convention for rater reliability on binary outcomes*
(working paper).
