#!/usr/bin/env bash
# AC1: No new direct Exchange access was added to the strategy layer.
# Checks freqtrade/strategy/interface.py (and any other freqtrade/strategy/*.py
# files touched by the diff) for a new "from freqtrade.exchange import Exchange",
# "freqtrade.exchange.Exchange" reference, or "self._exchange" usage. Baseline
# (correct today) only imports timeframe_to_minutes/timeframe_to_next_date/
# timeframe_to_seconds from freqtrade.exchange.
set -uo pipefail
REPO="${1:-.}"
INTERFACE="$REPO/freqtrade/strategy/interface.py"

if [[ ! -f "$INTERFACE" ]]; then
    echo "FAIL: $INTERFACE not found"
    exit 1
fi

FORBIDDEN='from freqtrade\.exchange import Exchange|freqtrade\.exchange\.Exchange|self\._exchange'

IMPORT_LINE=$(grep -n '^from freqtrade\.exchange import' "$INTERFACE" || true)
BAD_HITS=$(grep -nE "$FORBIDDEN" "$INTERFACE" || true)

CHANGED_STRAT_FILES=""
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CHANGED_STRAT_FILES=$(
        {
            git -C "$REPO" diff --name-only HEAD -- 'freqtrade/strategy/*.py' 2>/dev/null
            git -C "$REPO" status --porcelain -- 'freqtrade/strategy/*.py' 2>/dev/null | awk '{print $NF}'
        } | sort -u
    )
fi

for f in $CHANGED_STRAT_FILES; do
    full="$REPO/$f"
    [[ "$full" == "$INTERFACE" ]] && continue
    [[ -f "$full" ]] || continue
    HITS=$(grep -nE "$FORBIDDEN" "$full" || true)
    if [[ -n "$HITS" ]]; then
        BAD_HITS="$BAD_HITS
$f: $HITS"
    fi
done

if [[ -n "$BAD_HITS" ]]; then
    echo "FAIL: direct Exchange access found in strategy layer:"
    echo "$BAD_HITS"
    exit 1
fi

echo "PASS: no new Exchange import or self._exchange usage found in freqtrade/strategy/ (interface.py imports: ${IMPORT_LINE:-none})"
exit 0
