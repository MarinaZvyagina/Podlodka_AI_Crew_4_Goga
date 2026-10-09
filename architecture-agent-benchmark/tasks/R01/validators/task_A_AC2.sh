#!/usr/bin/env bash
# AC2: The new check is actually wired into validate_config_consistency(),
# not just defined and orphaned.
set -uo pipefail
REPO="${1:-.}"
FILE="$REPO/freqtrade/configuration/config_validation.py"

if [[ ! -f "$FILE" ]]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

FUNC=$(grep -oE '_validate_[a-zA-Z0-9_]*capital[a-zA-Z0-9_]*' "$FILE" | sort -u | head -1)

if [[ -z "$FUNC" ]]; then
    echo "FAIL: no _validate_*capital* function name found in $FILE"
    exit 1
fi

DEF_COUNT=$(grep -c "^def ${FUNC}(" "$FILE")

# Extract the body of validate_config_consistency: from its def line to the
# line before the next top-level "def " (using sed line ranges to avoid awk
# regex/backslash-escaping portability issues across awk implementations).
START=$(grep -n "^def validate_config_consistency(" "$FILE" | head -1 | cut -d: -f1)
if [[ -z "$START" ]]; then
    echo "FAIL: validate_config_consistency() not found in $FILE"
    exit 1
fi
TOTAL=$(wc -l < "$FILE")
REL_END=$(tail -n +"$((START + 1))" "$FILE" | grep -n "^def " | head -1 | cut -d: -f1)
if [[ -n "$REL_END" ]]; then
    END=$((START + REL_END - 1))
else
    END=$TOTAL
fi
AGGREGATOR_BODY=$(sed -n "${START},${END}p" "$FILE")
CALLED_IN_AGGREGATOR=$(echo "$AGGREGATOR_BODY" | grep -c "${FUNC}(")

if [[ "$DEF_COUNT" -ge 1 && "$CALLED_IN_AGGREGATOR" -ge 1 ]]; then
    echo "PASS: $FUNC is defined and called from validate_config_consistency()"
    exit 0
else
    echo "FAIL: $FUNC defined=$DEF_COUNT times, called-in-aggregator=$CALLED_IN_AGGREGATOR times (need both >=1)"
    exit 1
fi
