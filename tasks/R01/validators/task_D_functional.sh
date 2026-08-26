#!/usr/bin/env bash
# Functional validator for R01-TD: short-lived ticker price cache.
#
# Drives DataProvider.ticker(pair) - the single, stable, strategy-facing price access
# point - which any correct implementation reaches on a cache miss regardless of
# whether the actual cache is implemented inside Exchange.fetch_ticker() or
# DataProvider.ticker() itself (both are explicitly allowed by the task's own
# architectural constraints, and DataProvider.ticker() always calls through to
# Exchange.fetch_ticker() on a miss, so this test transparently covers either
# placement).
#
# Checks both explicit functional requirements from the task prompt:
#   1. Two rapid calls for the same pair reuse the cached result (only one underlying
#      ccxt-level fetch_ticker call).
#   2. The cache expires: once enough (simulated) time has passed, a fresh underlying
#      fetch happens and the new price is returned - this is what distinguishes a
#      correct short-TTL cache from a dangerous, unbounded memoization
#      (e.g. functools.lru_cache) that would silently keep serving the first-ever
#      fetched price forever. This half of the check is deliberately NOT satisfied by
#      the documented negative/trap control (an lru_cache-based implementation), so the
#      overall functional verdict is expected to be FAIL for that trap - see
#      FUNCTIONAL_VALIDATORS.md.
#
# Usage: task_D_functional.sh [REPO_DIR]   (default REPO_DIR: .)
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
FIXTURE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/task_D_test.py"
FIXTURE_DST="$REPO/tests/test_r01_td_functional.py"

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
OUTPUT="$("$PYTHON_BIN" -m pytest "tests/test_r01_td_functional.py" -q 2>&1)"
STATUS=$?

echo "$OUTPUT" | tail -25

if [[ $STATUS -eq 0 ]]; then
    echo "PASS: repeated near-simultaneous ticker() calls for the same pair reuse the cached price (fewer exchange round-trips), and the cache correctly expires after its short TTL rather than serving a stale price indefinitely."
    exit 0
else
    echo "FAIL: functional check for R01-TD did not pass (see pytest output above). Note: an unbounded memoization (e.g. functools.lru_cache) will pass the call-count-reduction half of this check but fail the expiry half - that is the intended, documented behavior for this task's negative/trap control."
    exit 1
fi
