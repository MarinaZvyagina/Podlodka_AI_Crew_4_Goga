#!/usr/bin/env bash
# Task B functional validator: ticket R05-TB ("Protect vmagent from runaway target counts
# coming from a single scrape job").
#
# This injects a Go test (fixtures/task_B_test.go, package promscrape) into the target
# repo's lib/promscrape package and runs it. It does not hardcode the new flag's name -
# it discovers, by name pattern, whichever -promscrape.* flag mentions both "target" and
# "job", sets it to a small limit, and checks (via the pre-existing, unmodified
# Config.parseData / Config.getStaticScrapeWork / droppedTargetsMap / WriteAPIV1Targets
# entry points) that: a job under the limit is unaffected, a job over the limit is
# truncated and the excluded targets become visible via the existing dropped-targets
# status surface, and the documented default leaves jobs unaffected.
#
# Usage: task_B_functional.sh [repo_path]   (repo_path defaults to ".")
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_B_test.go"

if [ ! -d "$REPO" ]; then
  echo "FAIL: repo path '$REPO' does not exist"
  exit 1
fi
if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

REPO_ABS="$(cd "$REPO" && pwd)"
TARGET_DIR="$REPO_ABS/lib/promscrape"
TARGET_FILE="$TARGET_DIR/zzz_task_B_functional_test.go"

if [ ! -d "$TARGET_DIR" ]; then
  echo "FAIL: $TARGET_DIR not found in repo '$REPO_ABS' (has lib/promscrape been moved/removed?)"
  exit 1
fi

cleanup() {
  rm -f "$TARGET_FILE"
}
trap cleanup EXIT

cp "$FIXTURE" "$TARGET_FILE"

cd "$REPO_ABS" || { echo "FAIL: cannot cd to '$REPO_ABS'"; exit 1; }

OUTPUT="$(go test ./lib/promscrape/ -run '^TestFunctional_MaxTargetsPerJob$' -v 2>&1)"
STATUS=$?

if [ $STATUS -ne 0 ]; then
  echo "FAIL: task B functional check failed (per-job_name max-scrape-targets cap missing, not applied uniformly to static_configs, or not visible via the existing dropped-targets status surface)"
  echo "----- go test output -----"
  echo "$OUTPUT"
  exit 1
fi

echo "PASS: a -promscrape.* flag enforcing a per-job_name target cap was found; jobs under the limit are unaffected, jobs over the limit are truncated to the limit with the excluded targets visible via droppedTargetsMap/WriteAPIV1Targets, and the documented default leaves jobs unaffected"
echo "----- go test output -----"
echo "$OUTPUT"
exit 0
