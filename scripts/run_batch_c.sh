#!/usr/bin/env bash
# Runs execute_run_c.py sequentially for a range of run_numbers from experiment_plan_c.csv
# (Condition C -- Goga-Native Architecture). Resumable, mirrors scripts/run_batch_b2.sh.
# Rows for repos whose condition-c-rXX-v1 tag doesn't exist yet are written as SKIPPED (not
# VALID) by execute_run_c.py, so they are retried for free on every pass until the tag appears.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"

START="$1"
END="$2"

RESULTS_CSV="results/runs_experiment_c.csv"

for i in $(seq "$START" "$END"); do
  RUN_ID=$(python3 -c "
import csv
with open('experiment_plan_c.csv') as f:
    for row in csv.DictReader(f):
        if int(row['run_number']) == $i:
            print(row['run_id']); break
")
  if [ -f "$RESULTS_CSV" ] && grep -qE "^${RUN_ID}(-RETRY[0-9]+)?,.*,VALID," "$RESULTS_CSV"; then
    echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Skipping run_number=$i ($RUN_ID) -- already VALID in results/runs_experiment_c.csv ==="
    continue
  fi
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Starting run_number=$i ($RUN_ID) ==="
  python3 scripts/execute_run_c.py "$i"
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Finished run_number=$i ==="
  df -H / | tail -1
done
