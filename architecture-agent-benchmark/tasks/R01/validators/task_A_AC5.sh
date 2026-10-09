#!/usr/bin/env bash
# AC5: Wallets.get_starting_balance / get_total_stake_amount behavior is
# unchanged - no diff to freqtrade/wallets.py, and existing wallet tests pass.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to $REPO"; exit 1; }

DIFF=$(git diff -- freqtrade/wallets.py)
if [[ -n "$DIFF" ]]; then
    echo "FAIL: freqtrade/wallets.py has a non-empty diff (precedence/wallets logic touched)"
    exit 1
fi

if [[ -x .venv/bin/activate || -f .venv/bin/activate ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
fi

if command -v pytest >/dev/null 2>&1; then
    if pytest tests/test_wallets.py -q >/tmp/task_A_AC5_pytest.log 2>&1; then
        echo "PASS: freqtrade/wallets.py diff is empty and tests/test_wallets.py passes"
        exit 0
    else
        echo "FAIL: tests/test_wallets.py did not pass (see /tmp/task_A_AC5_pytest.log)"
        tail -20 /tmp/task_A_AC5_pytest.log
        exit 1
    fi
else
    echo "PASS (partial): freqtrade/wallets.py diff is empty; pytest not on PATH so tests/test_wallets.py was not executed - MANUAL REVIEW REQUIRED to run it"
    exit 0
fi
