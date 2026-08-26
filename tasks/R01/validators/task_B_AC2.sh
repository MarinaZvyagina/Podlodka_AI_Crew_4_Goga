#!/usr/bin/env bash
# AC2: Backtesting was actually wired up, not just live/dry-run.
#
# The single most decisive check for this task's known trap ("dangerous
# success"): a narrow functional test of freqtradebot.py's execute_entry() can
# pass perfectly while freqtrade/optimize/backtesting.py is never touched, so
# the cap silently does nothing in backtests. This script fails hard and
# immediately if freqtrade/optimize/backtesting.py has an empty diff, and
# otherwise looks for a genuinely new call site in its entry-sizing path.
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

BT_FILE="freqtrade/optimize/backtesting.py"
if [[ ! -f "$REPO/$BT_FILE" ]]; then
    echo "FAIL: $BT_FILE not found"
    exit 1
fi

BT_DIFF=$(git -C "$REPO" diff -- "$BT_FILE")
if [[ -z "$BT_DIFF" ]]; then
    echo "FAIL: $BT_FILE diff is empty -- backtesting.py was not touched at all. The exposure cap (if implemented) only affects live/dry-run and silently does nothing in backtests -- this is precisely the trap this task warns about."
    exit 1
fi

# Strong signal: a newly-added call into a shared Wallets method (not one of the
# methods that already existed at the base commit) from backtesting.py.
KNOWN_BASE_WALLETS_METHODS='get_trade_stake_amount|get_available_stake_amount|validate_stake_amount|update|get_total\b|get_free\b|get_used\b|get_owned\b|check_exit_amount|get_starting_balance|get_total_stake_amount|get_collateral|get_all_balances|get_all_positions|record_wallet_state'

NEW_WALLET_CALLS=$(echo "$BT_DIFF" | grep -E '^\+' | grep -oE 'self\.wallets\.[a-zA-Z_][a-zA-Z0-9_]*\(' \
    | sed -E 's/self\.wallets\.([a-zA-Z_0-9]*)\(/\1/' | sort -u \
    | grep -vE "^(${KNOWN_BASE_WALLETS_METHODS})\$" || true)

if [[ -n "$NEW_WALLET_CALLS" ]]; then
    echo "PASS: $BT_FILE gained new call site(s) to previously-nonexistent Wallets method(s) in its entry-sizing path:"
    echo "$NEW_WALLET_CALLS" | sed 's/^/  self.wallets./'
    exit 0
fi

# Weaker fallback signal: backtesting.py diff mentions exposure/base-currency
# terminology at all (covers the case where the new logic isn't routed through
# self.wallets.<method> but some other shared helper/import).
FALLBACK=$(echo "$BT_DIFF" | grep -iE 'exposure|base_currency|currency_cap|pair_cap|currency_limit|max_pair_exposure' || true)
if [[ -n "$FALLBACK" ]]; then
    echo "PASS (weak signal): $BT_FILE diff references exposure/base-currency logic, but not via an obviously-new self.wallets.<method>() call -- verify manually that this is a real call into the shared implementation, not just a comment or unrelated match:"
    echo "$FALLBACK"
    exit 0
fi

echo "FAIL: $BT_FILE has a non-empty diff, but nothing in it resembles a call into a new shared exposure-check function -- the change looks unrelated to the exposure cap feature."
echo "$BT_DIFF" | head -40
exit 1
