#!/bin/bash
# Launch the laptop q99 slice as soon as the laptop is on AC power.
# Exits after launching (or if the run is already complete/running).
Q=/Users/austinsemmel/Desktop/PABAK_Investigation/grassr/simulation/v070_program/q99_node
while true; do
  if grep -q "FULL50K VERIFY PASS" "$Q/full50k/logs/run.log" 2>/dev/null; then
    echo "[watchdog] run already complete"; exit 0; fi
  if pgrep -f "driver_laptop50k.sh" >/dev/null; then
    echo "[watchdog] driver already running"; exit 0; fi
  if pmset -g batt | grep -q "AC Power"; then
    echo "[watchdog] AC detected $(date '+%H:%M:%S') — launching laptop slice"
    nohup caffeinate -ims "$Q/driver_laptop50k.sh" > "$Q/laptop50k_launch.log" 2>&1 &
    echo "$(date '+%F %T')" > "$Q/LAPTOP_LAUNCHED"
    exit 0
  fi
  sleep 60
done
