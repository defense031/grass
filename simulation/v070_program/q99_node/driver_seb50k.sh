#!/bin/bash
# q=0.99 node, Sebastian slice: blocks 2392-2551 @ 50k draws, 8 workers.
set -uo pipefail
ROOT=/Users/sebastian/grasscalc/q99_run
CELLS="$ROOT/cells.csv"; W=8
IDS_ALL=$(cat "$ROOT/ids_seb160.txt")
IFS=',' read -ra ARR <<< "$IDS_ALL"
mkdir -p "$ROOT/seb50k/logs"
log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$ROOT/seb50k/logs/run.log"; }
log "=== q=0.99 SEB 50k run start: ${#ARR[@]} blocks, $W workers ==="
pids=""
for ((w=0; w<W; w++)); do
  ids=""
  for ((j=w; j<${#ARR[@]}; j+=W)); do ids="$ids,${ARR[j]}"; done
  ids="${ids#,}"; [ -z "$ids" ] && continue
  wd="$ROOT/seb50k/worker_$(printf '%02d' $w)"
  IDS="$ids" CELLS="$CELLS" WDIR="$wd" DRAWS=50000 /usr/local/bin/Rscript "$ROOT/worker.R" > "$ROOT/seb50k/logs/w$(printf '%02d' $w).log" 2>&1 &
  pids="$pids $!"
done
fail=0; for p in $pids; do wait "$p" || fail=1; done
log "workers done (fail=$fail)"
[ "$fail" -eq 0 ] || { log "WORKER_FAIL"; exit 1; }
log "merging + self-verifying"
ROOT="$ROOT/seb50k" EXPECT_IDS="$IDS_ALL" /usr/local/bin/Rscript "$ROOT/verify_q99.R" >> "$ROOT/seb50k/logs/verify.log" 2>&1
if [ "$?" -eq 0 ]; then log "=== SEB50K VERIFY PASS ==="; else log "=== SEB50K VERIFY_FAIL ==="; exit 1; fi
