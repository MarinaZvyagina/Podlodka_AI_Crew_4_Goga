#!/usr/bin/env bash
# Runs execute_run.py --replacement 1 for a fixed list of run_numbers that
# previously errored out (e.g. due to hitting the account's session limit before the
# auto-retry-with-backoff fix existed). Skips any run_id that already has a VALID row.
set -uo pipefail
cd "$(dirname "$0")/.."

RESULTS_CSV="results/runs.csv"

for i in "$@"; do
  RUN_ID=$(python3 -c "
import csv
with open('experiment_plan.csv') as f:
    for row in csv.DictReader(f):
        if int(row['run_number']) == $i:
            print(row['run_id']); break
")
  if [ -f "$RESULTS_CSV" ] && grep -q "^${RUN_ID}-RETRY.*,VALID," "$RESULTS_CSV"; then
    echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Skipping run_number=$i ($RUN_ID) -- replacement already VALID ==="
    continue
  fi
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Replacing run_number=$i ($RUN_ID) ==="
  python3 scripts/execute_run.py "$i" --replacement 1
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Finished replacement for run_number=$i ==="
done
