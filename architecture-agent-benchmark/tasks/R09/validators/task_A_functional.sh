#!/usr/bin/env bash
# R09 Task A (TabDataStore backup-cleanup fix) — FUNCTIONAL validator
#
# Ticket: "Orphaned backup files after removing a browser window's saved tab data" — fixing
# DefaultTabDataStore.removeWindowData(forUUIDs:) (BrowserKit/Sources/TabDataStore/TabDataStore.swift)
# so it deletes both the primary AND backup window-data file for each removed UUID.
#
# This script performs a real, black-box functional check: it injects a standalone XCTest fixture
# (validators/fixtures/task_A_test.swift) into the target repo's TabDataStoreTests test target and
# executes it for real via `xcodebuild test`. The fixture only calls the public TabDataStore API
# (removeWindowData(forUUIDs:)) through the pre-existing MockTabFileManager test double that ships
# with the repo — it does not depend on any candidate-specific private helper, so it is agnostic to
# *how* a correct submission implements the fix.
#
# Why `xcodebuild test` and not `swift test` (per the task's own functional_check_command hint):
# plain `swift build`/`swift test` fail in this environment because the `Common` BrowserKit target
# unconditionally `import UIKit`, and a bare SwiftPM invocation resolves against the host macOS SDK
# (no UIKit), not an iOS SDK — confirmed by direct reproduction. `xcodebuild test` against the
# auto-generated per-target `TabDataStore` scheme, targeting an iOS Simulator destination, is the
# actually-working equivalent used throughout Phase 5 (see ../CONTROL_RESULTS.md) and is used here
# for the same reason.
#
# Usage: task_A_functional.sh [path-to-repo-root]  (default: .)
# Exit codes: 0 = PASS, 1 = FAIL.

set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  echo "FAIL: could not resolve repo path '$1'"
  exit 1
fi

BK="$REPO/BrowserKit"
if [ ! -d "$BK" ]; then
  echo "FAIL: BrowserKit directory not found at $BK"
  exit 1
fi

TEST_DIR="$BK/Tests/TabDataStoreTests"
if [ ! -d "$TEST_DIR" ]; then
  echo "FAIL: $TEST_DIR not found"
  exit 1
fi

FIXTURE_SRC="$SCRIPT_DIR/fixtures/task_A_test.swift"
if [ ! -f "$FIXTURE_SRC" ]; then
  echo "FAIL: fixture not found at $FIXTURE_SRC"
  exit 1
fi

TEST_FILE="$TEST_DIR/R09TaskAFunctionalTests.swift"

if [ -f "$TEST_FILE" ]; then
  echo "FAIL: $TEST_FILE already exists in the target repo; refusing to overwrite. Remove it and re-run."
  exit 1
fi

cleanup() { rm -f "$TEST_FILE"; }
trap cleanup EXIT

cp "$FIXTURE_SRC" "$TEST_FILE"

SIM_NAME=$(xcrun simctl list devices available 2>/dev/null | grep -m1 'iPhone' | sed -E 's/^[[:space:]]*([A-Za-z0-9 ]+) \(.*/\1/')
SIM_NAME="${SIM_NAME:-iPhone 17}"

pushd "$BK" >/dev/null || { echo "FAIL: could not cd into $BK"; exit 1; }
OUTPUT=$(xcodebuild test \
  -scheme TabDataStore \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -only-testing:TabDataStoreTests/R09TaskAFunctionalTests \
  2>&1)
STATUS=$?
popd >/dev/null

echo "$OUTPUT" | tail -100

if [ "$STATUS" -eq 0 ] && echo "$OUTPUT" | grep -q '\*\* TEST SUCCEEDED \*\*'; then
  echo "PASS: Task A functional check — removeWindowData(forUUIDs:) removes both primary and backup files for a targeted UUID, leaves untouched windows/backups alone, tolerates a missing backup file without throwing, and clearAllWindowsData() still clears both directories wholesale. (real xcodebuild test run on iOS Simulator '$SIM_NAME')"
  exit 0
else
  echo "FAIL: Task A functional check — the injected black-box regression test did not build or pass (see xcodebuild output above). This means removeWindowData(forUUIDs:) does not correctly remove backup files (or a related regression was introduced)."
  exit 1
fi
