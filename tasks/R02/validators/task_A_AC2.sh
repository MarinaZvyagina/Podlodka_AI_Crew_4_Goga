#!/usr/bin/env bash
# AC2: validate()/beacon() signatures unchanged.
# expected_if_correct: Signatures remain exactly `validate(config)` /
#   `beacon(config)`.
# expected_if_trap: Functions gain new positional/keyword parameters.
set -u

REPO="${1:-.}"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

TARGET="salt/beacons/diskusage.py"

if [ ! -f "$TARGET" ]; then
    echo "FAIL: $TARGET does not exist"
    exit 1
fi

matches=$(grep -n '^def validate\|^def beacon' "$TARGET")

if [ -z "$matches" ]; then
    echo "FAIL: no def validate/def beacon found in $TARGET"
    exit 1
fi

validate_line=$(printf '%s\n' "$matches" | grep 'def validate' )
beacon_line=$(printf '%s\n' "$matches" | grep 'def beacon' | grep -v 'def beacon_' )

if [ -z "$validate_line" ]; then
    echo "FAIL: def validate(...) not found"
    exit 1
fi

if [ -z "$beacon_line" ]; then
    echo "FAIL: def beacon(...) not found"
    exit 1
fi

ok=1
reason=""

if ! printf '%s' "$validate_line" | grep -qE 'def validate\(config\):'; then
    ok=0
    reason="$reason validate() signature changed -> [$validate_line];"
fi

if ! printf '%s' "$beacon_line" | grep -qE 'def beacon\(config\):'; then
    ok=0
    reason="$reason beacon() signature changed -> [$beacon_line];"
fi

if [ "$ok" -eq 1 ]; then
    echo "PASS: validate(config) and beacon(config) signatures unchanged"
    exit 0
else
    echo "FAIL:$reason"
    exit 1
fi
