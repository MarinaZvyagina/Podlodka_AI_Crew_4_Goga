#!/usr/bin/env bash
# Runs execute_run.py sequentially for a range of run_numbers.
# Usage: run_batch.sh <start> <end>
set -uo pipefail
cd "$(dirname "$0")/.."

START="$1"
END="$2"

for i in $(seq "$START" "$END"); do
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Starting run_number=$i ==="
  python3 scripts/execute_run.py "$i"
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Finished run_number=$i ==="
  df -H / | tail -1
done
