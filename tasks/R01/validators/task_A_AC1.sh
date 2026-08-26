#!/usr/bin/env bash
# AC1: New validation function follows the existing single-responsibility,
# conf-dict-in/None-out pattern used by every other _validate_* function in
# freqtrade/configuration/config_validation.py.
set -uo pipefail
REPO="${1:-.}"
FILE="$REPO/freqtrade/configuration/config_validation.py"

if [[ ! -f "$FILE" ]]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

# Find a new top-level function named like _validate_available_capital with
# signature (conf: dict[str, Any]) -> None, matching the neighboring
# _validate_unlimited_amount / _validate_trailing_stoploss pattern.
MATCH=$(grep -nE '^def _validate_[a-zA-Z0-9_]*capital[a-zA-Z0-9_]*\(conf: dict\[str, Any\]\) -> None:' "$FILE")

if [[ -z "$MATCH" ]]; then
    echo "FAIL: no top-level _validate_*capital*(conf: dict[str, Any]) -> None function found in $FILE"
    exit 1
fi

echo "PASS: matching validation function found: $MATCH"
exit 0
