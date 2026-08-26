#!/usr/bin/env bash
# AC4: No new direct Exchange dependency was added to the strategy layer
# (freqtrade/strategy/interface.py). At the base commit, this file only
# imports timeframe_to_* helper functions from freqtrade.exchange, never the
# Exchange class itself -- strategies reach exchange data only through
# self.dp (DataProvider) or config values.
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

FILE="freqtrade/strategy/interface.py"
if [[ ! -f "$REPO/$FILE" ]]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

DIFF=$(git -C "$REPO" diff -- "$FILE")

if [[ -z "$DIFF" ]]; then
    echo "PASS: $FILE has no diff at all -- no new Exchange import possible"
    exit 0
fi

ADDED_LINES=$(echo "$DIFF" | grep -E '^\+' | grep -vE '^\+\+\+')

# Any newly-added import line mentioning the Exchange class by name.
BAD_IMPORT=$(echo "$ADDED_LINES" | grep -E '^\+[[:space:]]*(from|import)' | grep -E '\bExchange\b' || true)
if [[ -n "$BAD_IMPORT" ]]; then
    echo "FAIL: new import referencing the Exchange class added to $FILE:"
    echo "$BAD_IMPORT"
    exit 1
fi

# Any newly-added reference to the bare Exchange class (instantiation, type
# hint, isinstance check, etc.) -- the base file never uses this identifier.
SUSPICIOUS_USE=$(echo "$ADDED_LINES" | grep -E '\bExchange\(|:[[:space:]]*Exchange\b|\bExchange\b[[:space:]]*[,)\]]' || true)
if [[ -n "$SUSPICIOUS_USE" ]]; then
    echo "FAIL: $FILE newly references the Exchange class directly (outside of the pre-existing timeframe_to_* helper imports):"
    echo "$SUSPICIOUS_USE"
    exit 1
fi

echo "PASS: $FILE diff is non-empty but contains no new Exchange import or reference"
echo "--- diff for manual context ---"
echo "$DIFF" | head -60
exit 0
