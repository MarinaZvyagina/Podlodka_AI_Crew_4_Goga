#!/usr/bin/env bash
# AC5 (conditional): If a manually-managed (non-TTLCache) cache dict was added to
# DataProvider, it must be reset inside the EXISTING clear_cache() method rather
# than a bespoke new reset method. If caching instead uses PeriodicCache/TTLCache
# (self-expiring), or lives entirely in Exchange (dataprovider.py untouched),
# this check is not applicable and is accepted as a pass by inspection.
set -uo pipefail
REPO="${1:-.}"
DP_FILE="$REPO/freqtrade/data/dataprovider.py"

if [[ ! -f "$DP_FILE" ]]; then
    echo "FAIL: $DP_FILE not found"
    exit 1
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository, cannot inspect diff"
    exit 1
fi

DP_DIFF=$(git -C "$REPO" diff HEAD -- freqtrade/data/dataprovider.py)

if [[ -z "$DP_DIFF" ]]; then
    echo "PASS (not applicable): freqtrade/data/dataprovider.py was not modified -- caching lives in Exchange instead; accepted as pass by inspection."
    exit 0
fi

ADDED=$(echo "$DP_DIFF" | awk '/^\+/ && !/^\+\+\+/ { line=$0; sub(/^\+/, "", line); print line }')

USES_TTLCACHE=$(echo "$ADDED" | grep -E 'PeriodicCache|TTLCache' || true)

if [[ -n "$USES_TTLCACHE" ]]; then
    echo "PASS (not applicable): DataProvider caching uses PeriodicCache/TTLCache (self-expiring); no manual dict-reset lifecycle needed. Accepted as pass by inspection."
    exit 0
fi

MANUAL_CACHE=$(echo "$ADDED" | grep -E '(_ticker_cache|_price_cache)[[:space:]]*[:=]' || true)

if [[ -z "$MANUAL_CACHE" ]]; then
    echo "PASS (not applicable): no new manually-managed ticker/price cache dict detected in the DataProvider diff; nothing that requires clear_cache() integration."
    exit 0
fi

CLEAR_CACHE_START=$(grep -n 'def clear_cache' "$DP_FILE" | head -1 | cut -d: -f1)
if [[ -z "$CLEAR_CACHE_START" ]]; then
    echo "FAIL: manual cache dict found ($MANUAL_CACHE) but clear_cache() method no longer exists in $DP_FILE"
    exit 1
fi

TOTAL_LINES=$(wc -l < "$DP_FILE" | tr -d ' ')
NEXT_DEF_OFFSET=$(tail -n +"$((CLEAR_CACHE_START + 1))" "$DP_FILE" | grep -n '^    def ' | head -1 | cut -d: -f1)
if [[ -n "$NEXT_DEF_OFFSET" ]]; then
    CLEAR_CACHE_END=$((CLEAR_CACHE_START + NEXT_DEF_OFFSET - 1))
else
    CLEAR_CACHE_END="$TOTAL_LINES"
fi
CLEAR_CACHE_BODY=$(sed -n "${CLEAR_CACHE_START},${CLEAR_CACHE_END}p" "$DP_FILE")

ATTR_NAME=$(echo "$MANUAL_CACHE" | grep -oE '(_ticker_cache|_price_cache)' | head -1)

if echo "$CLEAR_CACHE_BODY" | grep -q "$ATTR_NAME"; then
    echo "PASS: manual cache dict '$ATTR_NAME' is reset inside the existing clear_cache() method."
    exit 0
fi

BESPOKE=$(echo "$ADDED" | grep -E 'def clear_ticker_cache|def reset_ticker_cache|def invalidate_ticker' || true)

echo "FAIL: manual cache dict '$ATTR_NAME' was added to DataProvider but is NOT reset inside the existing clear_cache() method."
echo "clear_cache() body: $(echo "$CLEAR_CACHE_BODY" | tr '\n' ' ' | head -c 300)"
if [[ -n "$BESPOKE" ]]; then
    echo "A separate bespoke reset method was found instead (duplicating clear_cache()'s responsibility): $BESPOKE"
fi
exit 1
