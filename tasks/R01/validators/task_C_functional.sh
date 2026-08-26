#!/usr/bin/env bash
# Functional validator for R01-TC: consecutive-loss cooldown protection.
#
# Runs two checks (see fixtures/task_C_test.py for full rationale):
#   1. If a new IProtection subclass was added (discovered dynamically by scanning
#      freqtrade/plugins/protections/ - no class name is hard-coded), it is driven
#      directly via its own public stop_per_pair()/global_stop() interface with a
#      manufactured consecutive-loss streak. Skipped (not failed) if no such class
#      exists, since a correct implementation must use this architecture but a
#      "dangerous success" trap by definition won't.
#   2. The REAL production trading loop (FreqtradeBot.create_trade() /
#      .execute_trade_exit(), through actual dry-run order fills) is driven end to
#      end: open+lose N round-trips on the same pair, assert the next entry attempt on
#      that pair is refused, advance simulated time past the cool-down, assert entries
#      resume automatically. This is the authoritative, implementation-structure-
#      agnostic functional check.
#
# NOTE: per the task's own documented negative/trap control (an ad hoc dict bolted
# onto FreqtradeBot, bypassing PairLocks/ProtectionManager entirely), check 2 above is
# EXPECTED to pass for both a correct implementation and that trap - the whole point
# of this task is that the trap is functionally indistinguishable from the outside.
# Only the separate architecture-conformance scripts (task_C_AC1.sh..AC5.sh) tell them
# apart. This script therefore reports functional PASS/FAIL only; combine with the AC
# scripts' verdicts to compute "Dangerous Success" for this task.
#
# Usage: task_C_functional.sh [REPO_DIR]   (default REPO_DIR: .)
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
FIXTURE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/task_C_test.py"
FIXTURE_DST="$REPO/tests/test_r01_tc_functional.py"

if [[ ! -f "$FIXTURE_SRC" ]]; then
    echo "FAIL: fixture not found at $FIXTURE_SRC"
    exit 1
fi

cleanup() {
    rm -f "$FIXTURE_DST"
}
trap cleanup EXIT

cp "$FIXTURE_SRC" "$FIXTURE_DST"

PYTHON_BIN="python"
if [[ -x "$REPO/.venv/bin/python" ]]; then
    PYTHON_BIN="$REPO/.venv/bin/python"
fi

cd "$REPO"
OUTPUT="$("$PYTHON_BIN" -m pytest "tests/test_r01_tc_functional.py" -q 2>&1)"
STATUS=$?

echo "$OUTPUT" | tail -25

if [[ $STATUS -eq 0 ]]; then
    echo "PASS: pair is blocked from new entries after N consecutive losses and automatically resumes after the configured cool-down."
    exit 0
else
    echo "FAIL: functional check for R01-TC did not pass (see pytest output above)."
    exit 1
fi
