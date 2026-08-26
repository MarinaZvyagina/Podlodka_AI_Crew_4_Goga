#!/usr/bin/env bash
# Functional validator for R01-TA: conflicting capital-sizing config detection.
#
# Black-box check: instantiates a real FreqtradeBot (via the project's own
# get_patched_freqtradebot() test helper) with a config that sets both
# `available_capital` and a non-default `tradable_balance_ratio`, and asserts that
# starting the bot logs an unmissable warning naming both settings. This is
# implementation-location-agnostic: it doesn't assume the check lives in
# config_validation.py's aggregator specifically (that's what the separate
# task_A_AC*.sh architecture scripts verify) - it only checks the user-observable
# behavior of starting the bot with this misconfiguration, which is what the task
# prompt actually asks for ("fail fast... so users see the problem immediately when
# they try to start the bot").
#
# Usage: task_A_functional.sh [REPO_DIR]   (default REPO_DIR: .)
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
FIXTURE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/task_A_test.py"
FIXTURE_DST="$REPO/tests/test_r01_ta_functional.py"

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
OUTPUT="$("$PYTHON_BIN" -m pytest "tests/test_r01_ta_functional.py" -q 2>&1)"
STATUS=$?

echo "$OUTPUT" | tail -20

if [[ $STATUS -eq 0 ]]; then
    echo "PASS: bot start-up emits an unmissable warning when available_capital + a non-default tradable_balance_ratio are both set, and stays silent for the common non-conflicting configs."
    exit 0
else
    echo "FAIL: functional check for R01-TA did not pass (see pytest output above)."
    exit 1
fi
