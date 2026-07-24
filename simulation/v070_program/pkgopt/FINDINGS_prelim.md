# Package-structure optimization — preliminary findings (2026-07-23 night)

Prelim sweep over the prevalence-resolved null (1,925 cells, 50k draws each,
q=0.99 axis pending tonight's run). Scoring is in OUTPUT units: the percentile
the package would report, read with the shipped mid-p convention on each
candidate's native stored grid, against the 1000-point fine-grid read of the
50k-draw truth. Bytes are honest post-xz file sizes of the shippable object.
Table: `frontier_prelim.csv`; full results `sweep_prelim.rds`.

## Headline results

1. **The grid cannot be thinned — on any axis.** Structured axis-thinning is
   expensive everywhere: dropping 4 of 11 N-nodes costs 25 pp worst-case /
   1.5 pp mean read error; collapsing prevalence to 3 nodes costs 86 pp
   worst-case / 9–10 pp mean. The free-form greedy peel could not find a
   single interior cell droppable under a 1.0 pp read-error cap. The
   (k, N, q, prev) grid is near-minimal for its fidelity — every cell carries
   real information. (The prev result is the thesis in miniature: the null
   moves hard in prevalence, which is why pooling it was miscalibrated.)

2. **The bytes come from the quantile axis, not the cell axis.** Integer
   delta-coding of the quantile vectors (per-cell scale + cumulative-sum
   int diffs; monotone by construction, xz-friendly) is the dominant win:
   - `K100_intdelta` — 286 KB, mean read error 0.045 pp, flag cuts within
     3e-4 pp of truth: fidelity indistinguishable from exact storage at
     2.35x smaller than the signif-5 baseline (673 KB).
   - `K50_intdelta` — 147 KB, mean 0.11 pp: half the bytes again for a mean
     error still far under the 1-percentile-point requirement.
   - Low-rank (SVD score) layouts are the smallest but fail worst-case
     (25–43 pp at tail cells) — rejected.

3. **Worst-case is a shared discreteness floor, not an encoding defect.**
   Every faithful candidate (including exact signif-5 storage) shows the
   same ~7.7–9.4 pp worst-case at k3/N15/q0.97/prev0.95-class cells: at
   hyper-discrete corners the 100-knot representation itself cannot resolve
   the plateau structure the 1000-knot truth read sees. The same floor
   exists in the CURRENTLY SHIPPED pooled null. Likewise realized flag size
   at such cells ([0.043, 0.070] even under exact storage) is distribution
   discreteness, not reconstruction error. Relevant to the App D flag-size
   scoping text, not to the encoding decision.

## Implied recommendation (to confirm on the full grid with q=0.99)

Ship the prevalence-resolved null + q=0.99 node as **all 2,310 cells,
100-knot grid, integer-delta layout** (~345 KB projected, vs 0.32 MB raw for
today's 385-cell pooled null) — or K50 (~180 KB) if bytes are tight. No cell
dropping, no low-rank. The 5 MB sysdata pressure is not the null: the
44,616-cell `empirical_q_hat_surface` (31 MB raw) dominates the 6.85 MB rda
and is a separate optimization if wanted.

## Method notes (defect history that shaped the scorer)

- v1 scored percentiles by interpolating stored knots to the fine grid then
  reading plainly — this destroys tie runs and charged plateau cells ~half
  the plateau mass (a 5 pp phantom error on the exact baseline). v3 reads
  mid-p on the candidate's native grid, mirroring `delta_null_percentile`.
- v1's dropped-cell reconstruction bracketed on marginal node availability
  (NA for every free-form drop); v3 searches outward for the smallest
  axis-aligned box with all corners retained, averaging minimal-depth ties.
- Reconstruction weights are trilinear in (log10 N, q, prev) at fixed k —
  the operator class `lookup_delta_null` now uses at query time, extended
  by the prev axis the resolved null will add.
