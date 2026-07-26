# G2 — Hold-out proof that interpolation generalizes (pre-registration)

Written 2026-07-23 night, BEFORE any Tier A cell is simulated. Purpose: show
the single-cell finding (snap ±45-48% threshold error vs interpolation +2%
at k=6/N=1000/prev=0.05/q=0.945) is not an artifact and generalizes across
the design space; v0.8.0 ships interpolation only if this passes.

## Tier A — held-out threshold fidelity (280 cells)

Direct nulls simulated at off-grid points the calibration grid never saw,
then both lookup rules are evaluated against each held-out truth:
- **snap** — nearest-node cell (the shipped 0.7.4 semantics, extended with
  the prev axis nearest-node);
- **interp** — trilinear in (q, log10 N, prev) at fixed k (the v0.8.0
  prototype semantics).

Cell design (all at true DGP parameters; k stays on-grid because k snaps by
design in both rules):

| Arm | Off-grid axis | Points | Crossed with | Cells |
|-----|--------------|--------|--------------|-------|
| A1 | q ∈ {0.70, 0.80, 0.885, 0.945, 0.98} | 5 | k {3,6,10,25} × N {30,300} × prev {0.05,0.5,0.95} | 120 |
| A2 | N ∈ {25, 62, 122, 245, 707} (log-midpoints) | 5 | k {3,6,10,25} × q {0.85,0.97} × prev {0.05,0.5} | 80 |
| A3 | prev ∈ {0.125, 0.35, 0.65, 0.875} (midpoints) | 4 | k {3,6,10,25} × q {0.85,0.97} × N {30,300} | 64 |
| A4 | all three off at once (stress) | (q,N,prev) ∈ {(0.945,62,0.125),(0.945,62,0.65),(0.98,25,0.875),(0.98,25,0.35)} | k {3,6,10,25} | 16 |

Total 280 cells, 25,000 draws each (≈1.9 h across laptop 14 + Mini 8
workers). Block ids 3001–3280, seeds 20300000 + id — disjoint from every
shipped and contributed program (ids ≤ 2551) — via the same
`run_calibration_block` pipeline as the calibration program, so blocks are
bit-reproducible and machine-splittable (cross-machine determinism verified
bit-identical on 0.7.4, 2026-07-23).

Reference grid for both lookup rules: the v0.8.0 candidate truth object
(2,310 cells = 1,925 prev-resolved + 385 q=0.99 node, 50k draws — gate G1).

Metrics per held-out cell, in output units (mid-p reads, as
`delta_null_percentile` does):
1. 95th/99th threshold error, absolute (quality pp) and relative, and in
   held-out MC-SE units;
2. percentile-read error at probe deltas (held-out truth quantiles at
   .50/.90/.95/.99);
3. realized flag size when each rule's cut is applied to the held-out truth
   (nominal .05/.01).

## Pass criteria (pre-registered — evaluate, then judge, in that order)

- P1. Interpolation's percentile read within **1.0 pp** of held-out truth at
  every probe in every cell, excluding cells where the discreteness floor
  binds (defined a priori as cells whose truth has a tie run wider than
  1 pp at the probe — reported separately, since no grid representation can
  read inside a point mass).
- P2. Interpolation's realized flag sizes within **[0.5×, 1.5×] nominal**
  across all cells.
- P3. Interpolation beats or matches snap (within MC noise) in **every arm**;
  no region where interpolation is materially worse.
- P4. The A1 near-ceiling arm reproduces the direction of the original
  probe: snap's threshold error is an order of magnitude larger than
  interpolation's at q = 0.945/0.98.

Any failure → investigate before shipping; the failure mode and cells are
reported regardless of outcome.

## Tier B — end-to-end operating characteristics (design sketch, built after Tier A)

D-lite-style: ~50–100 off-grid true (q, π) configurations; each draw
generates a panel through the production pipeline, estimates q̂ and π̂ from
the panel, performs the lookup, fires the flag. Three arms: snap /
interp-raw-π̂ / interp-bridged-π̂ (closed-form apparent→true inversion) —
the third arm settles the bridge question empirically. Realized flag size
vs nominal per arm. Reuses the `dlite/` machinery; criteria to be
registered in this file before it runs.
