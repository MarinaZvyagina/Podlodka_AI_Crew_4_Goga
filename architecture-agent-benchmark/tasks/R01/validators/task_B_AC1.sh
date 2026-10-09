#!/usr/bin/env bash
# AC1: Exposure-limit logic is implemented once, in a module shared by both live
# (freqtrade/freqtradebot.py) and backtest (freqtrade/optimize/backtesting.py)
# engines -- not duplicated as two independently-written inline blocks.
#
# Heuristic: find newly-added function/method definitions (added lines, `git diff`
# vs HEAD) in a changed file OTHER than freqtradebot.py/backtesting.py/interface.py
# whose name hints at base-currency exposure accounting. If such a function is
# called from BOTH freqtradebot.py and backtesting.py, that's exactly the "one
# shared implementation, two call sites" shape the task wants. If no such shared
# function is found, but both engine files independently gained
# exposure/base-currency-related code, that's the "two hand-duplicated blocks" trap.
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

LIVE_FILE="freqtrade/freqtradebot.py"
BT_FILE="freqtrade/optimize/backtesting.py"

DIFF_STAT=$(git -C "$REPO" diff --stat)
if [[ -z "$DIFF_STAT" ]]; then
    echo "FAIL: no changes found (git diff --stat is empty) -- nothing was implemented"
    exit 1
fi

CHANGED_FILES=$(git -C "$REPO" diff --name-only -- freqtrade/)
SHARED_CANDIDATES=$(echo "$CHANGED_FILES" | grep -vE "^${LIVE_FILE}\$|^${BT_FILE}\$|^freqtrade/strategy/interface\.py\$" || true)

NAME_RE='exposure|currency_cap|pair_cap|base_currency|currency_exposure|currency_limit|max_pair_exposure'

FOUND_FN=""
FOUND_FILE=""
for f in $SHARED_CANDIDATES; do
    [[ -f "$REPO/$f" ]] || continue
    NEWDEFS=$(git -C "$REPO" diff -- "$f" | grep -E '^\+[[:space:]]*def [a-zA-Z_][a-zA-Z0-9_]*\(' \
        | sed -E 's/^\+[[:space:]]*def ([a-zA-Z_][a-zA-Z0-9_]*)\(.*/\1/')
    for fn in $NEWDEFS; do
        if echo "$fn" | grep -qiE "$NAME_RE"; then
            CALL_LIVE=$(grep -n "\.${fn}(" "$REPO/$LIVE_FILE" 2>/dev/null || true)
            CALL_BT=$(grep -n "\.${fn}(" "$REPO/$BT_FILE" 2>/dev/null || true)
            if [[ -n "$CALL_LIVE" && -n "$CALL_BT" ]]; then
                FOUND_FN="$fn"
                FOUND_FILE="$f"
                break 2
            fi
        fi
    done
done

if [[ -n "$FOUND_FN" ]]; then
    echo "PASS: single shared exposure function '$FOUND_FN' defined in $FOUND_FILE, called from both $LIVE_FILE and $BT_FILE"
    exit 0
fi

# No shared function found. Check whether exposure-ish logic was instead added
# independently inline in both engine files (the duplication trap).
LIVE_DIFF=$(git -C "$REPO" diff -- "$LIVE_FILE")
BT_DIFF=$(git -C "$REPO" diff -- "$BT_FILE")
LIVE_HAS_EXPOSURE=$(echo "$LIVE_DIFF" | grep -icE "$NAME_RE" || true)
BT_HAS_EXPOSURE=$(echo "$BT_DIFF" | grep -icE "$NAME_RE" || true)

if [[ "$LIVE_HAS_EXPOSURE" -gt 0 && "$BT_HAS_EXPOSURE" -gt 0 ]]; then
    echo "FAIL: exposure/base-currency related changes found independently inline in both $LIVE_FILE and $BT_FILE, but no single shared function (in a module imported by both) could be found -- looks like duplicated, hand-written logic rather than one shared implementation."
    exit 1
fi

if [[ "$LIVE_HAS_EXPOSURE" -gt 0 && "$BT_HAS_EXPOSURE" -eq 0 ]]; then
    echo "FAIL: exposure/base-currency related changes found only in $LIVE_FILE, none in $BT_FILE -- looks like a live-only implementation (see AC2)."
    exit 1
fi

echo "FAIL: could not find a shared exposure-calculation function called from both $LIVE_FILE and $BT_FILE"
exit 1
