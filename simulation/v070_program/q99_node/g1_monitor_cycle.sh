#!/bin/bash
# One G1 monitoring cycle: gather health of both q99 runs, append a
# status line, print ALERT/ALL_DONE tokens for the monitoring agent,
# then sleep 9 minutes. Exit code always 0; the agent reads the tokens.
Q=/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/q99_node
S=$Q/g1_status.log
TS=$(date '+%F %T')
ALERTS=""

# --- Sebastian ---
SEB=$(ssh -o ConnectTimeout=10 -o BatchMode=yes sebastian '
  b=$(ls /Users/sebastian/grasscalc/q99_run/seb50k/worker_*/block_*.rds 2>/dev/null | wc -l | tr -d " ")
  w=$(pgrep -f worker.R | wc -l | tr -d " ")
  r=$(pgrep -f verify_q99.R | wc -l | tr -d " ")
  pass=$(grep -c "SEB50K VERIFY PASS" /Users/sebastian/grasscalc/q99_run/seb50k/logs/run.log 2>/dev/null)
  fail=$(grep -cE "WORKER_FAIL|VERIFY_FAIL" /Users/sebastian/grasscalc/q99_run/seb50k/logs/run.log 2>/dev/null)
  echo "$b $w $r ${pass:-0} ${fail:-0}"' 2>/dev/null)
if [ -z "$SEB" ]; then
  ALERTS="$ALERTS ALERT:sebastian-unreachable"
  SEB="NA NA NA NA NA"
fi
read SB SW SR SPASS SFAIL <<< "$SEB"
[ "$SFAIL" != "NA" ] && [ "$SFAIL" -gt 0 ] && ALERTS="$ALERTS ALERT:sebastian-run-failed"
if [ "$SW" = "0" ] && [ "$SR" = "0" ] && [ "$SPASS" = "0" ] && [ "$SB" != "NA" ]; then
  ALERTS="$ALERTS ALERT:sebastian-workers-dead-no-pass"
fi
# stall: same block count as previous line's seb count, workers alive
PREV_SB=$(tail -1 "$S" 2>/dev/null | awk '{print $3}' | cut -d= -f2)
if [ -n "$PREV_SB" ] && [ "$PREV_SB" = "$SB" ] && [ "$SW" != "0" ] && [ "$SW" != "NA" ]; then
  PREV2_SB=$(tail -2 "$S" 2>/dev/null | head -1 | awk '{print $3}' | cut -d= -f2)
  [ "$PREV2_SB" = "$SB" ] && ALERTS="$ALERTS ALERT:sebastian-stalled"
fi

# --- Laptop ---
PWR=$(pmset -g batt | grep -o "AC Power\|Battery Power" | head -1)
LB=$(ls $Q/full50k/worker_*/block_*.rds 2>/dev/null | wc -l | tr -d " ")
LRUN=$(pgrep -f "driver_laptop50k.sh" | wc -l | tr -d " ")
LPASS=$(grep -c "FULL50K VERIFY PASS" $Q/full50k/logs/run.log 2>/dev/null); LPASS=${LPASS:-0}
LFAIL=$(grep -cE "WORKER_FAIL|VERIFY_FAIL" $Q/full50k/logs/run.log 2>/dev/null); LFAIL=${LFAIL:-0}
[ "$LFAIL" -gt 0 ] && ALERTS="$ALERTS ALERT:laptop-run-failed"
if [ "$LRUN" -gt 0 ] && [ "$PWR" = "Battery Power" ]; then
  ALERTS="$ALERTS ALERT:laptop-compute-on-battery"
fi
DISK=$(df -g /Users | tail -1 | awk '{print $4}')
[ "$DISK" -lt 5 ] && ALERTS="$ALERTS ALERT:disk-low"

DONE=""
if [ "$SPASS" != "NA" ] && [ "$SPASS" -gt 0 ] && [ "$LPASS" -gt 0 ]; then DONE="ALL_DONE"; fi

LINE="$TS seb=$SB/160 sw=$SW spass=$SPASS laptop=$LB/225 lrun=$LRUN lpass=$LPASS pwr=${PWR:-unknown} disk=${DISK}G$ALERTS $DONE"
echo "$LINE" >> "$S"
echo "$LINE"
sleep 540
