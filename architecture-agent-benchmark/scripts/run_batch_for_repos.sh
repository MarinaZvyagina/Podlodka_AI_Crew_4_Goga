#!/usr/bin/env bash
# Like run_batch.sh, but only processes run_numbers whose repository is in a given list.
# This is the building block for moderate parallelism: launch several instances of this
# script concurrently, each pinned to a disjoint set of repositories, so no two workers
# ever touch the same base git clone at the same time (avoids `git worktree add` lock
# contention -- see scripts/run_batch_parallel.sh for the launcher and rationale).
#
# Usage: run_batch_for_repos.sh <start> <end> <REPO1,REPO2,...>
set -uo pipefail
cd "$(dirname "$0")/.."

START="$1"
END="$2"
REPOS="$3"   # comma-separated, e.g. "R01,R05,R08"

RESULTS_CSV="results/runs.csv"

for i in $(seq "$START" "$END"); do
  ROW=$(python3 -c "
import csv
with open('experiment_plan.csv') as f:
    for row in csv.DictReader(f):
        if int(row['run_number']) == $i:
            print(row['run_id'] + ',' + row['repository']); break
")
  RUN_ID="${ROW%,*}"
  REPO="${ROW##*,}"

  case ",$REPOS," in
    *",$REPO,"*) ;;  # this worker owns this repo -- proceed
    *) continue ;;   # not ours, skip silently (another worker owns it)
  esac

  if [ -f "$RESULTS_CSV" ] && grep -qE "^${RUN_ID}(-RETRY[0-9]+)?,.*,VALID," "$RESULTS_CSV"; then
    echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ][$REPOS] Skipping run_number=$i ($RUN_ID) -- already VALID ==="
    continue
  fi
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ][$REPOS] Starting run_number=$i ($RUN_ID) ==="
  python3 scripts/execute_run.py "$i"
  echo "=== [$( date '+%Y-%m-%d %H:%M:%S') ][$REPOS] Finished run_number=$i ==="
  df -H / | tail -1
done
