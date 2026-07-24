#!/bin/bash
# Tier A held-out run, laptop share (170 blocks @ 25k draws, 14 workers).
# Launch plugged-in only, AFTER the G1 q99 run completes:
#   caffeinate -ims driver_tierA_laptop.sh
set -uo pipefail
ROOT=/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/g2_holdout
CELLS="$ROOT/cells_tierA.csv"; W=14
IDS_ALL=$(cat "$ROOT/ids_laptop.txt")
IFS=',' read -ra ARR <<< "$IDS_ALL"
mkdir -p "$ROOT/tierA_local/logs"
log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$ROOT/tierA_local/logs/run.log"; }
log "=== Tier A LAPTOP run start: ${#ARR[@]} blocks, $W workers ==="
pids=""
for ((w=0; w<W; w++)); do
  ids=""
  for ((j=w; j<${#ARR[@]}; j+=W)); do ids="$ids,${ARR[j]}"; done
  ids="${ids#,}"; [ -z "$ids" ] && continue
  wd="$ROOT/tierA_local/worker_$(printf '%02d' $w)"
  IDS="$ids" CELLS="$CELLS" WDIR="$wd" DRAWS=25000 Rscript "$ROOT/worker_tierA.R" > "$ROOT/tierA_local/logs/w$(printf '%02d' $w).log" 2>&1 &
  pids="$pids $!"
done
fail=0; for p in $pids; do wait "$p" || fail=1; done
log "workers done (fail=$fail)"
[ "$fail" -eq 0 ] && log "=== TIERA LAPTOP COMPLETE ===" || { log "TIERA_WORKER_FAIL"; exit 1; }
