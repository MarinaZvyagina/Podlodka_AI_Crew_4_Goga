#!/usr/bin/env bash
# AC3: Pause state is represented via PairLocks, not a parallel structure.
# (1) The new handler file should only return ProtectionReturn objects, never
#     call PairLocks/lock_pair itself (that's ProtectionManager's job).
# (2) freqtrade/freqtradebot.py must not gain a new dict/set/list attribute
#     that looks like a second "paused pairs" tracker (e.g.
#     self._paused_pairs / self._loss_streak_locks / self._consecutive_loss_pairs).
set -uo pipefail
REPO="${1:-.}"
DIR="$REPO/freqtrade/plugins/protections"
BOT="$REPO/freqtrade/freqtradebot.py"

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
    echo "FAIL: no new handler file found under $DIR to inspect"
    exit 1
fi

FAIL_REASON=""

for f in "${NEW_FILES[@]}"; do
    HAS_PROTRETURN=$(grep -cE 'ProtectionReturn\(' "$f")
    if [[ "$HAS_PROTRETURN" -eq 0 ]]; then
        FAIL_REASON="$FAIL_REASON\n$f never constructs a ProtectionReturn -- unclear how it signals a lock."
        continue
    fi
    DIRECT_LOCK=$(grep -nE 'PairLocks|\.lock_pair\(' "$f" || true)
    if [[ -n "$DIRECT_LOCK" ]]; then
        FAIL_REASON="$FAIL_REASON\n$f calls PairLocks/lock_pair directly instead of returning ProtectionReturn for ProtectionManager to persist:\n$DIRECT_LOCK"
    fi
done

# Check freqtradebot.py for a new ad hoc pause-tracking attribute.
if [[ -f "$BOT" ]]; then
    if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        BOT_DIFF=$(git -C "$REPO" diff -- freqtrade/freqtradebot.py)
    else
        BOT_DIFF=""
    fi
    SUSPICIOUS=$(echo "$BOT_DIFF" | grep -nE '^\+.*self\.[A-Za-z_]*(pause|streak|consecutive|loss)[A-Za-z_]*\s*(:.*)?=' || true)
    if [[ -n "$SUSPICIOUS" ]]; then
        FAIL_REASON="$FAIL_REASON\nfreqtradebot.py diff adds a suspicious new attribute that looks like a parallel pause tracker:\n$SUSPICIOUS"
    fi
fi

if [[ -n "$FAIL_REASON" ]]; then
    echo -e "FAIL:$FAIL_REASON"
    exit 1
fi

echo "PASS: new handler(s) (${NEW_FILES[*]}) only return ProtectionReturn, no direct PairLocks/lock_pair calls; no new ad hoc pause-tracking attribute found in freqtradebot.py diff"
exit 0
