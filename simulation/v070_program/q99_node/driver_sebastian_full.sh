#!/bin/bash
# Overnight FULL run: all 385 q=0.99 cells at 50,000 draws on Sebastian.
set -uo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
ROOT=/Users/sebastian/grasscalc/q99_run
CELLS="$ROOT/cells.csv"; W=8; DRAWS=50000
IDS_ALL=$(cat "$ROOT/ids_full.txt")
IFS=',' read -ra ARR <<< "$IDS_ALL"
mkdir -p "$ROOT/seb_full/logs"
log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$ROOT/seb_full/logs/run.log"; }
log "=== q=0.99 FULL overnight run start: ${#ARR[@]} blocks x $DRAWS draws, $W workers ==="
pids=""
for ((w=0; w<W; w++)); do
  ids=""
  for ((j=w; j<${#ARR[@]}; j+=W)); do ids="$ids,${ARR[j]}"; done
  ids="${ids#,}"; [ -z "$ids" ] && continue
  wd="$ROOT/seb_full/worker_$(printf '%02d' $w)"
  IDS="$ids" CELLS="$CELLS" WDIR="$wd" DRAWS=$DRAWS nohup Rscript "$ROOT/worker.R" > "$ROOT/seb_full/logs/w$(printf '%02d' $w).log" 2>&1 &
  pids="$pids $!"
done
fail=0; for p in $pids; do wait "$p" || fail=1; done
log "workers done (fail=$fail)"
[ "$fail" -eq 0 ] || { log "WORKER_FAIL"; exit 1; }
log "merging + self-verifying"
ROOT="$ROOT/seb_full" EXPECT_IDS="$IDS_ALL" Rscript "$ROOT/verify_q99.R" >> "$ROOT/seb_full/logs/verify.log" 2>&1
if [ "$?" -eq 0 ]; then log "=== FULL VERIFY PASS ==="; else log "=== FULL VERIFY_FAIL ==="; exit 1; fi
