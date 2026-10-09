#!/usr/bin/env bash
# Task A functional validator: ticket R05-TA ("Support trimming whitespace from label values
# during relabeling").
#
# This injects a black-box Go test (fixtures/task_A_test.go, package promrelabel_test) into
# the target repo's lib/promrelabel package and runs it. The test only uses promrelabel's
# public API (ParseRelabelConfigsData / ParsedConfigs.Apply / SortLabels / LabelsToString),
# the same entry points any relabel_configs consumer (scrape-time or remote-write) goes
# through, so it is agnostic to *how* a candidate implemented the new action - only that a
# `trim` or `trim_space` relabel_configs action exists, works, and is validated at load time.
#
# Usage: task_A_functional.sh [repo_path]   (repo_path defaults to ".")
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_A_test.go"

if [ ! -d "$REPO" ]; then
  echo "FAIL: repo path '$REPO' does not exist"
  exit 1
fi
if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

REPO_ABS="$(cd "$REPO" && pwd)"
TARGET_DIR="$REPO_ABS/lib/promrelabel"
TARGET_FILE="$TARGET_DIR/zzz_task_A_functional_test.go"

if [ ! -d "$TARGET_DIR" ]; then
  echo "FAIL: $TARGET_DIR not found in repo '$REPO_ABS' (has lib/promrelabel been moved/removed?)"
  exit 1
fi

cleanup() {
  rm -f "$TARGET_FILE"
}
trap cleanup EXIT

cp "$FIXTURE" "$TARGET_FILE"

cd "$REPO_ABS" || { echo "FAIL: cannot cd to '$REPO_ABS'"; exit 1; }

OUTPUT="$(go test ./lib/promrelabel/... -run '^TestFunctional_TrimRelabelAction$' -v 2>&1)"
STATUS=$?

if [ $STATUS -ne 0 ]; then
  echo "FAIL: task A functional check failed (relabel_configs 'trim'/'trim_space' action missing or not behaving as specified)"
  echo "----- go test output -----"
  echo "$OUTPUT"
  exit 1
fi

echo "PASS: relabel_configs trim/trim_space action is implemented via lib/promrelabel's public API and behaves correctly (whitespace trimmed, multi-source-label concatenation preserved, missing source_labels/target_label rejected at load time)"
echo "----- go test output -----"
echo "$OUTPUT"
exit 0
