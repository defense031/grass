#!/bin/bash
# q=0.99 corner node, FULL PRECISION: all 385 cells @ 50,000 draws, local run.
# Seeds 20300000+block_id (2167-2551); 12k approx bundle is the seed-exact prefix.
set -uo pipefail
ROOT=/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/q99_node
CELLS="$ROOT/cells.csv"; W=14
IDS_ALL=$(cat "$ROOT/ids_full.txt")
IFS=',' read -ra ARR <<< "$IDS_ALL"
mkdir -p "$ROOT/full50k/logs"
log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$ROOT/full50k/logs/run.log"; }
log "=== q=0.99 FULL 50k local run start: ${#ARR[@]} blocks, $W workers ==="
pids=""
for ((w=0; w<W; w++)); do
  ids=""
  for ((j=w; j<${#ARR[@]}; j+=W)); do ids="$ids,${ARR[j]}"; done
  ids="${ids#,}"; [ -z "$ids" ] && continue
  wd="$ROOT/full50k/worker_$(printf '%02d' $w)"
  IDS="$ids" CELLS="$CELLS" WDIR="$wd" DRAWS=50000 Rscript "$ROOT/worker.R" > "$ROOT/full50k/logs/w$(printf '%02d' $w).log" 2>&1 &
  pids="$pids $!"
done
fail=0; for p in $pids; do wait "$p" || fail=1; done
log "workers done (fail=$fail)"
[ "$fail" -eq 0 ] || { log "WORKER_FAIL"; exit 1; }
log "merging + self-verifying"
ROOT="$ROOT/full50k" EXPECT_IDS="$IDS_ALL" Rscript "$ROOT/verify_q99.R" >> "$ROOT/full50k/logs/verify.log" 2>&1
if [ "$?" -eq 0 ]; then log "=== FULL50K VERIFY PASS ==="; else log "=== FULL50K VERIFY_FAIL ==="; exit 1; fi
