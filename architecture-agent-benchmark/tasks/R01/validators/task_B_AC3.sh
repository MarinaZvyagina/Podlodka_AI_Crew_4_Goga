#!/usr/bin/env bash
# AC3: Open-position lookup goes through the shared Trade/LocalTrade
# abstraction (LocalTrade.get_open_trades() / Trade.get_trades_proxy()), not a
# bespoke per-engine tracker (e.g. a hand-rolled dict/Counter that backtesting.py
# maintains on its own, independent of the trades the backtest engine actually
# recorded).
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

ALL_DIFF=$(git -C "$REPO" diff -- freqtrade/)
if [[ -z "$ALL_DIFF" ]]; then
    echo "FAIL: no changes under freqtrade/ at all"
    exit 1
fi

TRADE_LOOKUP_USES=$(echo "$ALL_DIFF" | grep -E '^\+' | grep -E 'get_open_trades\(|get_trades_proxy\(' || true)

if [[ -z "$TRADE_LOOKUP_USES" ]]; then
    echo "FAIL: no newly-added code calls LocalTrade.get_open_trades() / Trade.get_trades_proxy() anywhere in the diff -- open positions are not being read through the shared Trade/LocalTrade abstraction."
    exit 1
fi

BT_FILE="freqtrade/optimize/backtesting.py"
BT_DIFF=$(git -C "$REPO" diff -- "$BT_FILE")

# Heuristic for a hand-rolled, backtesting-only exposure tracker kept independent
# of Trade/LocalTrade state (e.g. `self._pair_exposure: dict = {}` plus manual
# increments), which would still "work" for a narrow test but drift from what the
# backtest engine actually recorded (partial fills, DCA, closes, etc.).
BESPOKE_TRACKER=$(echo "$BT_DIFF" | grep -E '^\+' \
    | grep -E 'self\.[a-zA-Z_]*(exposure|currency)[a-zA-Z_]*[[:space:]]*(:[^=]*)?=[[:space:]]*(\{\}|defaultdict|Counter\(|dict\(\))' || true)
BT_USES_TRADE_LOOKUP=$(echo "$BT_DIFF" | grep -E '^\+' | grep -E 'get_open_trades\(|get_trades_proxy\(' || true)

if [[ -n "$BESPOKE_TRACKER" && -z "$BT_USES_TRADE_LOOKUP" ]]; then
    echo "FAIL: $BT_FILE appears to introduce its own exposure counter/dict, independent of Trade/LocalTrade, and does not itself (or via an obvious shared call) route through get_open_trades()/get_trades_proxy():"
    echo "$BESPOKE_TRACKER"
    exit 1
fi

echo "PASS: found $(echo "$TRADE_LOOKUP_USES" | grep -c .) new call site(s) to get_open_trades()/get_trades_proxy() in the diff, and no bespoke exposure tracker detected in $BT_FILE:"
echo "$TRADE_LOOKUP_USES"
exit 0
