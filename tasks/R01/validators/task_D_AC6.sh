#!/usr/bin/env bash
# AC6: Backtesting/hyperopt are unaffected. Runs the real, unmodified
# tests/optimize/test_backtesting.py and tests/optimize/test_hyperopt.py suites
# and requires them to pass, plus confirms the new caching code did not add a
# new coupling/import from freqtrade/optimize/ specific to live ticker fetching.
set -uo pipefail
REPO="${1:-.}"

if [[ ! -d "$REPO" ]]; then
    echo "FAIL: $REPO does not exist"
    exit 1
fi

if [[ -f "$REPO/.venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$REPO/.venv/bin/activate"
fi

if ! command -v pytest >/dev/null 2>&1; then
    echo "FAIL: pytest not found on PATH and no $REPO/.venv available to activate"
    exit 1
fi

OUTPUT=$(cd "$REPO" && pytest tests/optimize/test_backtesting.py tests/optimize/test_hyperopt.py -q 2>&1)
STATUS=$?

if [[ $STATUS -ne 0 ]]; then
    echo "FAIL: tests/optimize/test_backtesting.py and/or tests/optimize/test_hyperopt.py did not pass unchanged (pytest exit $STATUS)"
    echo "$OUTPUT" | tail -30
    exit 1
fi

COUPLING=""
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    DIFF=$(git -C "$REPO" diff HEAD -- freqtrade/exchange/exchange.py freqtrade/data/dataprovider.py freqtrade/util/periodic_cache.py 2>/dev/null || true)
    COUPLING=$(echo "$DIFF" | awk '/^\+/ && !/^\+\+\+/ && (/from freqtrade\.optimize/ || /import freqtrade\.optimize/)')
fi

if [[ -n "$COUPLING" ]]; then
    echo "FAIL: new coupling from caching code into freqtrade/optimize/ detected: $COUPLING"
    exit 1
fi

echo "PASS: tests/optimize/test_backtesting.py and tests/optimize/test_hyperopt.py pass unchanged; no new optimize/ coupling introduced by the caching code."
echo "$OUTPUT" | tail -5
exit 0
