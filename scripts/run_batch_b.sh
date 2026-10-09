#!/usr/bin/env bash
# Runs execute_run_b.py sequentially for a range of run_numbers from experiment_plan_b.csv
# (Condition B' -- Goga Full Workflow). Resumable: mirrors scripts/run_batch.sh's skip-if-VALID
# logic against results/runs_experiment_b.csv, so it can be relaunched after a kill/crash
# without re-doing or double-paying for completed runs.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"

START="$1"
END="$2"

RESULTS_CSV="results/runs_experiment_b.csv"

for i in $(seq "$START" "$END"); do
  RUN_ID=$(python3 -c "
import csv
with open('experiment_plan_b.csv') as f:
    for row in csv.DictReader(f):
        if int(row['run_number']) == $i:
            print(row['run_id']); break
")
  if [ -f "$RESULTS_CSV" ] && grep -qE "^${RUN_ID}(-RETRY[0-9]+)?,.*,VALID," "$RESULTS_CSV"; then
    echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Skipping run_number=$i ($RUN_ID) -- already VALID in results/runs_experiment_b.csv ==="
    continue
  fi
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Starting run_number=$i ($RUN_ID) ==="
  python3 scripts/execute_run_b.py "$i"
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Finished run_number=$i ==="
  df -H / | tail -1
done
