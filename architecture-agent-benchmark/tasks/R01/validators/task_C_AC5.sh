#!/usr/bin/env bash
# AC5: Consecutive-loss streak counting must be genuinely distinct from
# LowProfitPairs' profit-sum approach -- iterate closed trades ordered by
# recency and stop counting at the first winning trade (streak logic), not
# sum(...) profit over a lookback window. This is inherently semantic, so this
# script only computes a heuristic signal and always prints
# "MANUAL REVIEW REQUIRED" plus the relevant snippet(s) for a human to judge --
# it does not claim to authoritatively settle AC5.
set -uo pipefail
REPO="${1:-.}"
DIR="$REPO/freqtrade/plugins/protections"

if [[ ! -d "$DIR" ]]; then
    echo "FAIL: $DIR not found"
    exit 1
fi

BASELINE="cooldown_period.py low_profit_pairs.py max_drawdown_protection.py stoploss_guard.py iprotection.py __init__.py"
NEW_FILES=()
for f in "$DIR"/*.py; do
    base=$(basename "$f")
    skip=0
    for b in $BASELINE; do
        [[ "$base" == "$b" ]] && skip=1 && break
    done
    [[ $skip -eq 0 ]] && NEW_FILES+=("$f")
done

if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
    echo "FAIL: no new handler file found under $DIR to review"
    exit 1
fi

echo "MANUAL REVIEW REQUIRED: AC5 (streak-vs-profit-sum) cannot be settled by grep alone."
echo "Heuristic signals below; a human must confirm the core evaluation method iterates"
echo "closed trades ordered by recency and stops at the first winning trade, rather than"
echo "summing profit (LowProfitPairs' approach, low_profit_pairs.py's _low_profit())."
echo

VERDICT_HINT="unclear"

for f in "${NEW_FILES[@]}"; do
    echo "----- $f -----"
    SUM_PROFIT=$(grep -nE 'sum\(' "$f" || true)
    LOOP_BREAK=$(grep -nE 'for .*trade.* in|while ' "$f" || true)
    EARLY_STOP=$(grep -nE '\bbreak\b|\breturn (None|0|streak|count)\b' "$f" || true)
    SORT_RECENCY=$(grep -nE 'sort|sorted|reverse=True|key=lambda.*close_date' "$f" || true)

    echo "  sum(...) usage (LowProfitPairs-style profit summation signal):"
    if [[ -n "$SUM_PROFIT" ]]; then
        echo "$SUM_PROFIT" | sed 's/^/    /'
    else
        echo "    (none found)"
    fi

    echo "  loop constructs (for/while, candidate streak iteration):"
    if [[ -n "$LOOP_BREAK" ]]; then
        echo "$LOOP_BREAK" | sed 's/^/    /'
    else
        echo "    (none found)"
    fi

    echo "  early break/return inside a loop (candidate 'stop at first win'):"
    if [[ -n "$EARLY_STOP" ]]; then
        echo "$EARLY_STOP" | sed 's/^/    /'
    else
        echo "    (none found)"
    fi

    echo "  explicit recency ordering (sorted/reverse/key=close_date):"
    if [[ -n "$SORT_RECENCY" ]]; then
        echo "$SORT_RECENCY" | sed 's/^/    /'
    else
        echo "    (none found -- note: get_trades_proxy may already return trades in a usable order; verify manually)"
    fi

    echo
    echo "  --- full file for review ---"
    sed 's/^/    /' "$f"
    echo

    if [[ -n "$LOOP_BREAK" && -n "$EARLY_STOP" && -z "$SUM_PROFIT" ]]; then
        VERDICT_HINT="looks_like_streak"
    elif [[ -n "$SUM_PROFIT" && -z "$LOOP_BREAK" ]]; then
        VERDICT_HINT="looks_like_profit_sum_copy"
    fi
done

echo "Heuristic verdict (NOT authoritative -- human must confirm): $VERDICT_HINT"

if [[ "$VERDICT_HINT" == "looks_like_profit_sum_copy" ]]; then
    echo "FAIL (heuristic): pattern resembles a sum()-based profit check with no streak loop -- likely a LowProfitPairs copy/rename. MANUAL REVIEW REQUIRED to confirm."
    exit 1
else
    echo "PASS (heuristic): pattern is consistent with streak/consecutive-loss counting. MANUAL REVIEW REQUIRED to confirm."
    exit 0
fi
