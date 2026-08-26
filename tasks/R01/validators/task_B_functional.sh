#!/usr/bin/env bash
# Functional validator for R01-TB: per-underlying-currency exposure cap.
#
# Drives two real, stable public entry points every correct implementation must route
# a new trade through: FreqtradeBot.execute_entry() (live/dry-run) and
# Backtesting._enter_trade() (backtesting). Configures `max_pair_exposure` (the config
# key name both the verified positive and negative reference implementations use) and
# asserts a second trade sharing a base currency with an already-open position gets
# resized down consistently.
#
# IMPORTANT: per the task prompt, identical live-vs-backtest behavior is itself a
# FUNCTIONAL requirement ("this needs to behave identically whether someone is running
# the bot live/dry-run or running a backtest... We've been burned before by features
# that quietly only worked in one of those two modes"). Consequently an implementation
# that only wires the cap into the live path (and leaves backtesting.py untouched) is
# expected to FAIL this functional check on its backtest half, even though it would
# pass a narrower, live-only test - see FUNCTIONAL_VALIDATORS.md for the observed
# result against the documented negative/trap control.
#
# Usage: task_B_functional.sh [REPO_DIR]   (default REPO_DIR: .)
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
FIXTURE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/task_B_test.py"
FIXTURE_DST="$REPO/tests/test_r01_tb_functional.py"

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
OUTPUT="$("$PYTHON_BIN" -m pytest "tests/test_r01_tb_functional.py" -q 2>&1)"
STATUS=$?

echo "$OUTPUT" | tail -25

if [[ $STATUS -eq 0 ]]; then
    echo "PASS: max_pair_exposure caps/resizes a trade that would breach the configured base-currency exposure limit, IDENTICALLY in both the live/dry-run and backtesting engines."
    exit 0
else
    echo "FAIL: functional check for R01-TB did not pass (see pytest output above). Note: if only the live/dry-run test failed while backtesting diverged, this is the documented 'dangerous success' trap shape for this task - the feature works live but is silently absent from backtests."
    exit 1
fi
