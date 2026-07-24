#!/bin/bash
# Wait for Sebastian's verify PASS, pull his bundle, merge with the
# laptop bundle into the full 385-block node, then run the pkgopt chain.
set -uo pipefail
V0=/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program
Q=$V0/q99_node
for i in $(seq 1 40); do
  if ssh -o ConnectTimeout=10 -o BatchMode=yes sebastian 'grep -q "SEB50K VERIFY PASS" /Users/sebastian/grasscalc/q99_run/seb50k/logs/run.log' 2>/dev/null; then
    echo "[chain] Sebastian PASS detected"; break
  fi
  if ssh -o ConnectTimeout=10 -o BatchMode=yes sebastian 'grep -q "VERIFY_FAIL" /Users/sebastian/grasscalc/q99_run/seb50k/logs/run.log' 2>/dev/null; then
    echo "[chain] SEBASTIAN VERIFY_FAIL — aborting"; exit 1
  fi
  [ "$i" -eq 40 ] && { echo "[chain] timed out waiting for Sebastian PASS"; exit 1; }
  sleep 60
done
rsync -a --quiet sebastian:/Users/sebastian/grasscalc/q99_run/seb50k/bundle/ "$Q/seb50k_bundle/"
mkdir -p "$Q/full50k_bundle"
cp "$Q/full50k/bundle/"block_*.rds "$Q/full50k_bundle/"
cp "$Q/seb50k_bundle/"block_*.rds "$Q/full50k_bundle/"
head -1 "$Q/full50k/bundle/bundle_manifest.csv" > "$Q/full50k_bundle/bundle_manifest.csv"
tail -n +2 "$Q/full50k/bundle/bundle_manifest.csv" >> "$Q/full50k_bundle/bundle_manifest.csv"
tail -n +2 "$Q/seb50k_bundle/bundle_manifest.csv" >> "$Q/full50k_bundle/bundle_manifest.csv"
N=$(ls "$Q/full50k_bundle/"block_*.rds | wc -l | tr -d " ")
echo "[chain] merged bundle: $N blocks (expect 385)"
[ "$N" -eq 385 ] || { echo "[chain] MERGE COUNT WRONG"; exit 1; }
bash "$V0/pkgopt/04_collect_and_full_sweep.sh"
echo "[chain] FULL SWEEP COMPLETE"
