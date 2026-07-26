#!/bin/bash
set -uo pipefail
ROOT=/private/tmp/claude-501/-Users-austinsemmel-Desktop-PABAK-Investigation/e4d050b9-9d8e-45a8-aeea-87e27486e786/scratchpad/q99_run
CELLS="$ROOT/cells.csv"; W=14
IDS_ALL=$(cat "$ROOT/ids_local.txt")
IFS=',' read -ra ARR <<< "$IDS_ALL"
mkdir -p "$ROOT/local/logs"
log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$ROOT/local/logs/run.log"; }
log "=== q=0.99 LOCAL run start: ${#ARR[@]} blocks, $W workers ==="
pids=""
for ((w=0; w<W; w++)); do
  ids=""
  for ((j=w; j<${#ARR[@]}; j+=W)); do ids="$ids,${ARR[j]}"; done
  ids="${ids#,}"; [ -z "$ids" ] && continue
  wd="$ROOT/local/worker_$(printf '%02d' $w)"
  IDS="$ids" CELLS="$CELLS" WDIR="$wd" DRAWS=12000 Rscript "$ROOT/worker.R" > "$ROOT/local/logs/w$(printf '%02d' $w).log" 2>&1 &
  pids="$pids $!"
done
fail=0; for p in $pids; do wait "$p" || fail=1; done
log "workers done (fail=$fail)"
[ "$fail" -eq 0 ] || { log "WORKER_FAIL"; exit 1; }
log "merging + self-verifying"
ROOT="$ROOT/local" EXPECT_IDS="$IDS_ALL" Rscript "$ROOT/verify_q99.R" >> "$ROOT/local/logs/verify.log" 2>&1
if [ "$?" -eq 0 ]; then log "=== LOCAL VERIFY PASS ==="; else log "=== LOCAL VERIFY_FAIL ==="; exit 1; fi
