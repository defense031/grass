#!/bin/bash
# After the q=0.99 full 50k run completes: gate on its self-verify, reduce
# the bundle, rebuild the truth object with the q=0.99 axis, run the full
# rate-distortion sweep.
set -euo pipefail
V0=/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program
Q99="$V0/q99_node/full50k"
RD="$V0/resolved_null_reduction"
PK="$V0/pkgopt"

grep -q "FULL50K VERIFY PASS" "$Q99/logs/run.log" || {
  echo "q99 laptop share has not passed self-verify — aborting"; exit 1; }
N=$(ls "$V0/q99_node/full50k_bundle/"block_*.rds 2>/dev/null | wc -l)
[ "$N" -eq 385 ] || {
  echo "merged bundle has $N blocks, expected 385 — run the merge first"; exit 1; }

BLOCK_GLOB="$V0/q99_node/full50k_bundle/block_*.rds" \
  OUT_RDS="$RD/cell_quantiles_q99_50k.rds" \
  CORES=8 Rscript "$RD/reduce_blocks.R"

CONTRIB_RDS="$RD/cell_quantiles_contrib50k.rds" \
  Q99_RDS="$RD/cell_quantiles_q99_50k.rds" \
  OUT_RDS="$PK/truth_full.rds" Rscript "$PK/01_prep.R"

PKGOPT_DIR="$PK" TRUTH_RDS="$PK/truth_full.rds" \
  OUT_CSV="$PK/frontier_full.csv" OUT_RDS="$PK/sweep_full.rds" \
  Rscript "$PK/03_run_sweep.R"
