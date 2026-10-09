#!/usr/bin/env bash
# AC4: The @retrier-decorated network call path is preserved on cache miss; no
# undecorated bypass call was introduced. Confirms @retrier still directly
# precedes "def fetch_ticker" in freqtrade/exchange/exchange.py, that there is
# still exactly one self._api.fetch_ticker(...) call site (inside that decorated
# method), and that no new file added a raw bypass call elsewhere.
set -uo pipefail
REPO="${1:-.}"
EXCHANGE_FILE="$REPO/freqtrade/exchange/exchange.py"

if [[ ! -f "$EXCHANGE_FILE" ]]; then
    echo "FAIL: $EXCHANGE_FILE not found"
    exit 1
fi

FETCH_LINE=$(grep -n '^    def fetch_ticker(' "$EXCHANGE_FILE" | head -1 | cut -d: -f1)
if [[ -z "$FETCH_LINE" ]]; then
    echo "FAIL: could not find 'def fetch_ticker' in $EXCHANGE_FILE"
    exit 1
fi

PREV_LINE=$((FETCH_LINE - 1))
DECORATOR=$(sed -n "${PREV_LINE}p" "$EXCHANGE_FILE")

if [[ "$DECORATOR" != *"@retrier"* ]]; then
    echo "FAIL: @retrier decorator no longer directly precedes 'def fetch_ticker' (line $PREV_LINE reads: '$DECORATOR')"
    exit 1
fi

API_CALLS=$(grep -n 'self\._api\.fetch_ticker(' "$EXCHANGE_FILE" | grep -v 'fetch_tickers(' || true)
NUM_CALLS=0
if [[ -n "$API_CALLS" ]]; then
    NUM_CALLS=$(echo "$API_CALLS" | grep -c .)
fi

if [[ "$NUM_CALLS" -eq 0 ]]; then
    echo "FAIL: no self._api.fetch_ticker(...) call found at all in $EXCHANGE_FILE"
    exit 1
fi

if [[ "$NUM_CALLS" -gt 1 ]]; then
    echo "FAIL: found $NUM_CALLS calls to self._api.fetch_ticker(...) in $EXCHANGE_FILE -- possible undecorated bypass added elsewhere:"
    echo "$API_CALLS"
    exit 1
fi

BYPASS_ELSEWHERE=""
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    DIFF=$(git -C "$REPO" diff HEAD -- . ':!freqtrade/exchange/exchange.py' ':!tests')
    BYPASS_ELSEWHERE=$(echo "$DIFF" | awk '/^\+/ && !/^\+\+\+/ && /_api\.fetch_ticker/')
fi

if [[ -n "$BYPASS_ELSEWHERE" ]]; then
    echo "FAIL: a new undecorated bypass call to fetch_ticker was added outside exchange.py:"
    echo "$BYPASS_ELSEWHERE"
    exit 1
fi

echo "PASS: @retrier still directly decorates fetch_ticker (line $PREV_LINE), exactly one self._api.fetch_ticker call site in exchange.py, no bypass found elsewhere. Call site: $API_CALLS"
exit 0
