#!/usr/bin/env bash
# AC2: Caching logic is centralized in Exchange.fetch_ticker or DataProvider.ticker,
# not scattered at call sites. Scans the working-tree diff (against HEAD) for
# cache-related additions, and fails if they show up outside
# freqtrade/exchange/exchange.py or freqtrade/data/dataprovider.py (e.g. a second,
# independent cache bolted onto freqtradebot.py or rpc/rpc.py), or if BOTH files
# were touched (expected: exactly one cache layer).
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository, cannot inspect diff"
    exit 1
fi

DIFF=$(git -C "$REPO" diff HEAD)

if [[ -z "$DIFF" ]]; then
    echo "FAIL: no diff found against HEAD -- nothing to check"
    exit 1
fi

CACHE_RE='[Cc]ache|TTLCache|lru_cache|memoiz'

HIT_FILES=$(echo "$DIFF" | awk -v re="$CACHE_RE" '
    /^\+\+\+ b\// { file=$0; sub(/^\+\+\+ b\//, "", file); next }
    /^\+/ && !/^\+\+\+/ {
        line=$0
        sub(/^\+/, "", line)
        if (line ~ re) print file
    }
' | sort -u)

if [[ -z "$HIT_FILES" ]]; then
    echo "FAIL: no cache-related additions found anywhere in the diff"
    exit 1
fi

ALLOWED_RE='^freqtrade/exchange/exchange\.py$|^freqtrade/data/dataprovider\.py$|^freqtrade/util/periodic_cache\.py$|^tests/'
DISALLOWED=$(echo "$HIT_FILES" | grep -vE "$ALLOWED_RE" || true)

if [[ -n "$DISALLOWED" ]]; then
    echo "FAIL: cache-related additions found outside Exchange/DataProvider (scattered call-site caching): $DISALLOWED"
    exit 1
fi

CORE_HIT=$(echo "$HIT_FILES" | grep -E '^freqtrade/exchange/exchange\.py$|^freqtrade/data/dataprovider\.py$' || true)

if [[ -z "$CORE_HIT" ]]; then
    echo "FAIL: cache-related additions found only outside Exchange.fetch_ticker/DataProvider.ticker (e.g. only in tests): $HIT_FILES"
    exit 1
fi

NUM_CORE=$(echo "$CORE_HIT" | grep -c .)
if [[ "$NUM_CORE" -gt 1 ]]; then
    echo "FAIL: cache-related additions found in BOTH exchange.py and dataprovider.py -- expected exactly one cache layer: $(echo "$CORE_HIT" | tr '\n' ' ')"
    exit 1
fi

echo "PASS: exactly one cache layer touched ($CORE_HIT), no scattered call-site caching found outside Exchange/DataProvider"
exit 0
