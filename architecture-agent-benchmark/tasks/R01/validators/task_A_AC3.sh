#!/usr/bin/env bash
# AC3: No modules outside the configuration layer (or tests/) were touched.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to $REPO"; exit 1; }

CHANGED=$(git diff --stat HEAD 2>/dev/null | sed '$d' | awk '{print $1}')
if [[ -z "$CHANGED" ]]; then
    CHANGED=$(git diff --name-only HEAD 2>/dev/null)
fi

if [[ -z "$CHANGED" ]]; then
    echo "FAIL: no diff detected against HEAD (nothing to validate)"
    exit 1
fi

BAD=""
for f in $CHANGED; do
    case "$f" in
        freqtrade/configuration/*|tests/*) ;;
        *) BAD="$BAD $f" ;;
    esac
done

if [[ -n "$BAD" ]]; then
    echo "FAIL: changed paths outside freqtrade/configuration/ and tests/:$BAD"
    exit 1
fi

echo "PASS: all changed paths confined to freqtrade/configuration/ (and/or tests/): $CHANGED"
exit 0
