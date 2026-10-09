#!/usr/bin/env bash
# Like run_batch_b2.sh, but only processes run_numbers whose repository is in a given list.
# Mirrors scripts/run_batch_for_repos.sh's moderate-parallelism pattern.
#
# Usage: run_batch_b2_for_repos.sh <start> <end> <REPO1,REPO2,...>
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"

START="$1"
END="$2"
REPOS="$3"

RESULTS_CSV="results/runs_experiment_b2.csv"

for i in $(seq "$START" "$END"); do
  ROW=$(python3 -c "
import csv
with open('experiment_plan_b2.csv') as f:
    for row in csv.DictReader(f):
        if int(row['run_number']) == $i:
            print(row['run_id'] + ',' + row['repository']); break
")
  RUN_ID="${ROW%,*}"
  REPO="${ROW##*,}"

  case ",$REPOS," in
    *",$REPO,"*) ;;
    *) continue ;;
  esac

  if [ -f "$RESULTS_CSV" ] && grep -qE "^${RUN_ID}(-RETRY[0-9]+)?,.*,VALID," "$RESULTS_CSV"; then
    echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ][$REPOS] Skipping run_number=$i ($RUN_ID) -- already VALID ==="
    continue
  fi
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ][$REPOS] Starting run_number=$i ($RUN_ID) ==="
  python3 scripts/execute_run_b2.py "$i"
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ][$REPOS] Finished run_number=$i ==="
  df -H / | tail -1
done
