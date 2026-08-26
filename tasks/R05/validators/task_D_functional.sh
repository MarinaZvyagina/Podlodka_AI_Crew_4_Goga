#!/usr/bin/env bash
# Task D functional validator: ticket R05-TD ("Identify which metrics are causing us to hit
# our series-limit settings").
#
# This injects a Go test (fixtures/task_D_test.go, package storage) into the target repo's
# lib/storage package and runs it. Since the ticket explicitly leaves the query API's "exact
# shape... up to you", the test does not hardcode any candidate-specific method/field name:
# it enables any newly-added boolean OpenOptions toggle via reflection, induces drops for
# thousands of distinct, uniquely-prefixed metric names via the pre-existing
# MustOpenStorage/AddRows/DebugFlush/UpdateMetrics entry points, and then uses reflection to
# find any newly-added exported *Storage method whose return value reports a per-metric-name
# drop count for one of the injected names - whatever that method happens to be called.
#
# Usage: task_D_functional.sh [repo_path]   (repo_path defaults to ".")
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_D_test.go"

if [ ! -d "$REPO" ]; then
  echo "FAIL: repo path '$REPO' does not exist"
  exit 1
fi
if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

REPO_ABS="$(cd "$REPO" && pwd)"
TARGET_DIR="$REPO_ABS/lib/storage"
TARGET_FILE="$TARGET_DIR/zzz_task_D_functional_test.go"

if [ ! -d "$TARGET_DIR" ]; then
  echo "FAIL: $TARGET_DIR not found in repo '$REPO_ABS' (has lib/storage been moved/removed?)"
  exit 1
fi

cleanup() {
  rm -f "$TARGET_FILE"
  # MustOpenStorage under this test name is normally removed by the test itself on success
  # (via testRemoveAll); in case of a failed/aborted run, make sure no test data is left behind.
  rm -rf "$TARGET_DIR/TestFunctional_PerMetricNameDropTracking"
}
trap cleanup EXIT

cp "$FIXTURE" "$TARGET_FILE"

cd "$REPO_ABS" || { echo "FAIL: cannot cd to '$REPO_ABS'"; exit 1; }

OUTPUT="$(go test ./lib/storage/ -run '^TestFunctional_PerMetricNameDropTracking$' -v 2>&1)"
STATUS=$?

if [ $STATUS -ne 0 ]; then
  echo "FAIL: task D functional check failed (no queryable per-metric-name drop-count tracking found for samples dropped due to -storage.maxHourlySeries/-storage.maxDailySeries)"
  echo "----- go test output -----"
  echo "$OUTPUT"
  exit 1
fi

echo "PASS: per-metric-name drop tracking is enabled and queryable - a newly-added exported *Storage method reports nonzero drop counts for injected metric names after -storage.maxHourlySeries was exceeded"
echo "----- go test output -----"
echo "$OUTPUT"
exit 0
