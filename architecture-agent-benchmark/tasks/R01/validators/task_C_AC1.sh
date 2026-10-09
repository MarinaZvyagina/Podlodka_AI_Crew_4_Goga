#!/usr/bin/env bash
# AC1: New handler subclasses IProtection rather than being a standalone/ad hoc
# class. We look under freqtrade/plugins/protections/*.py for a class that (a)
# is not one of the four pre-existing built-ins (CooldownPeriod, LowProfitPairs,
# MaxDrawdown, StoplossGuard) and (b) inherits from IProtection, in a file that
# also defines short_desc/global_stop/stop_per_pair (the abstract methods).
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
    echo "FAIL: no new files found under $DIR beyond the four built-in handlers (cooldown_period.py, low_profit_pairs.py, max_drawdown_protection.py, stoploss_guard.py)"
    exit 1
fi

FOUND=""
for f in "${NEW_FILES[@]}"; do
    CLASS_LINE=$(grep -nE '^class [A-Za-z_][A-Za-z0-9_]*\(.*IProtection.*\):' "$f" || true)
    if [[ -n "$CLASS_LINE" ]]; then
        HAS_SHORT_DESC=$(grep -cE 'def short_desc\(' "$f")
        HAS_GLOBAL_STOP=$(grep -cE 'def global_stop\(' "$f")
        HAS_STOP_PER_PAIR=$(grep -cE 'def stop_per_pair\(' "$f")
        if [[ "$HAS_SHORT_DESC" -gt 0 && "$HAS_GLOBAL_STOP" -gt 0 && "$HAS_STOP_PER_PAIR" -gt 0 ]]; then
            FOUND="$f: $CLASS_LINE"
            break
        fi
    fi
done

if [[ -n "$FOUND" ]]; then
    echo "PASS: new IProtection subclass found implementing short_desc/global_stop/stop_per_pair -- $FOUND"
    exit 0
else
    echo "FAIL: new file(s) found under $DIR (${NEW_FILES[*]}) but none define a class inheriting IProtection with short_desc/global_stop/stop_per_pair. Streak logic likely lives elsewhere (e.g. inline in freqtradebot.py)."
    exit 1
fi
