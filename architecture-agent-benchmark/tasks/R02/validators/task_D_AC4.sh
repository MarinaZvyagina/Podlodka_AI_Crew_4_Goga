#!/usr/bin/env bash
# AC4: No new dependency on the persistent minion/master cache subsystem.
#
# Method (per metadata_D.yaml): grep -n 'salt.cache\|salt.loader.cache\|import salt.cache'
# salt/modules/disk.py post-change.
#
# expected_if_correct: no match (memoization is purely in-process via
#   __context__, not via the on-disk/persistent salt.cache subsystem).
# expected_if_trap: N/A for the module-level-global trap (it also has no
#   match here) -- this AC targets a different, more exotic failure mode
#   (reaching for the persistent cache subsystem) than the module-level
#   global trap does; it is included for completeness per the metadata.
set -u

REPO="${1:-.}"
FILE="salt/modules/disk.py"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

matches=$(grep -n 'salt\.cache\|salt\.loader\.cache\|import salt\.cache' "$FILE")

if [ -n "$matches" ]; then
    echo "FAIL: $FILE depends on the persistent minion/master cache subsystem: $(printf '%s' "$matches" | tr '\n' ' ; ')"
    exit 1
fi

echo "PASS: no dependency on salt.cache / salt.loader.cache in $FILE"
exit 0
