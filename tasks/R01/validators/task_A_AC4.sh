#!/usr/bin/env bash
# AC4: The exception/warning style used by the new function matches the
# file's existing convention. The spec (functional_requirements) explicitly
# allows either (a) a hard failure raising ConfigurationError (the same
# exception type every other rule in this file raises), or (b) an unmissable
# logger.warning (freqtrade's own established style for non-fatal
# consistency issues in this file, e.g. _validate_ask_orderbook). A new,
# custom exception class, a bare `raise Exception(...)`, or a print()-only
# implementation with no exception/warning at all are all traps.
set -uo pipefail
REPO="${1:-.}"
FILE="$REPO/freqtrade/configuration/config_validation.py"

if [[ ! -f "$FILE" ]]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

FUNC=$(grep -oE '_validate_[a-zA-Z0-9_]*capital[a-zA-Z0-9_]*' "$FILE" | sort -u | head -1)
if [[ -z "$FUNC" ]]; then
    echo "FAIL: no _validate_*capital* function found in $FILE (cannot check its raise style)"
    exit 1
fi

START=$(grep -n "^def ${FUNC}(" "$FILE" | head -1 | cut -d: -f1)
TOTAL=$(wc -l < "$FILE")
REL_END=$(tail -n +"$((START + 1))" "$FILE" | grep -n "^def " | head -1 | cut -d: -f1)
if [[ -n "$REL_END" ]]; then
    END=$((START + REL_END - 1))
else
    END=$TOTAL
fi
BODY=$(sed -n "${START},${END}p" "$FILE")

HAS_RAISE=$(echo "$BODY" | grep -cE '^\s*raise ')
HAS_CORRECT_RAISE=$(echo "$BODY" | grep -cE 'raise ConfigurationError\(')
HAS_PRINT=$(echo "$BODY" | grep -cE '^\s*print\(')
HAS_WARNING=$(echo "$BODY" | grep -cE 'logger\.warning\(')

if [[ "$HAS_RAISE" -gt 0 ]]; then
    if [[ "$HAS_CORRECT_RAISE" -gt 0 ]]; then
        echo "PASS: $FUNC raises ConfigurationError, matching file convention"
        exit 0
    else
        echo "FAIL: $FUNC raises something other than ConfigurationError. Body:"
        echo "$BODY"
        exit 1
    fi
elif [[ "$HAS_WARNING" -gt 0 ]]; then
    echo "PASS: $FUNC emits a logger.warning (no exception raised), an accepted alternative per the spec's functional_requirements"
    exit 0
elif [[ "$HAS_PRINT" -gt 0 ]]; then
    echo "FAIL: $FUNC only print()s, with no exception/warning at all. Body:"
    echo "$BODY"
    exit 1
else
    echo "FAIL: $FUNC neither raises ConfigurationError nor logs a warning. Body:"
    echo "$BODY"
    exit 1
fi
