#!/usr/bin/env bash
# Runs execute_run.py sequentially for a range of run_numbers.
# Usage: run_batch.sh <start> <end>
set -uo pipefail
cd "$(dirname "$0")/.."

START="$1"
END="$2"

RESULTS_CSV="results/runs.csv"

for i in $(seq "$START" "$END"); do
  # Resumable: skip any run_number whose run_id already has a row in results/runs.csv.
  # This lets the batch be re-launched after a kill/crash without re-doing (and re-paying
  # for) already-completed runs, and without ever double-counting a run.
  RUN_ID=$(awk -F, -v n="$i" 'NR==1{next} $0 ~ "^"n","{next}' /dev/null 2>/dev/null)
  RUN_ID=$(python3 -c "
import csv
with open('experiment_plan.csv') as f:
    for row in csv.DictReader(f):
        if int(row['run_number']) == $i:
            print(row['run_id']); break
")
  # Only treat a run as "done" if it (or one of its -RETRYn replacements) recorded a
  # VALID row. ERROR/INVALID/TIMEOUT rows are infrastructure failures (e.g. a hit
  # session-usage limit, or a corrupted worktree), not real data -- they must not be
  # silently treated as complete, or the missing observation would just vanish from the
  # dataset. Use scripts/run_replacements.sh to explicitly re-run any such run_number.
  if [ -f "$RESULTS_CSV" ] && grep -qE "^${RUN_ID}(-RETRY[0-9]+)?,.*,VALID," "$RESULTS_CSV"; then
    echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Skipping run_number=$i ($RUN_ID) -- already VALID in results/runs.csv ==="
    continue
  fi
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Starting run_number=$i ($RUN_ID) ==="
  python3 scripts/execute_run.py "$i"
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ] Finished run_number=$i ==="
  df -H / | tail -1
done
