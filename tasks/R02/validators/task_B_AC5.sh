#!/usr/bin/env bash
# AC5: Feature genuinely spans the three real boundaries, not concentrated in
#   one file.
# method: git diff --stat; confirm salt/beacons/__init__.py, salt/minion.py,
#   and salt/modules/beacons.py all show non-trivial changes.
# expected_if_correct: all three files show at least a handful of changed
#   lines each.
# expected_if_trap: the change is concentrated entirely in
#   salt/modules/beacons.py, with salt/beacons/__init__.py and/or
#   salt/minion.py untouched.
set -u

REPO="${1:-.}"
BASE="dd3fe66070a465d045efd6120e0f34e47f3672c2"
# The architecturally correct change to salt/minion.py is intentionally a
# single new dict entry (one line) in the existing dispatch table, per
# required_existing_abstractions -- so the bar for "non-trivial" is simply
# "at least one real changed line", not a large diff. The point of this
# check is to catch the trap where minion.py is untouched entirely (0
# lines), not to demand a large diff.
MIN_CHANGED_LINES=1

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

changed_line_count() {
    local file="$1"
    local diff
    diff=$(git diff "$BASE" -- "$file" 2>/dev/null)
    if [ -z "$diff" ]; then
        echo 0
        return
    fi
    local added removed
    added=$(printf '%s\n' "$diff" | grep -cE '^[+][^+]')
    removed=$(printf '%s\n' "$diff" | grep -cE '^-[^-]')
    echo $((added + removed))
}

B_INIT=$(changed_line_count "salt/beacons/__init__.py")
MINION=$(changed_line_count "salt/minion.py")
MOD_BEACONS=$(changed_line_count "salt/modules/beacons.py")

echo "INFO: changed-line counts -- salt/beacons/__init__.py=$B_INIT salt/minion.py=$MINION salt/modules/beacons.py=$MOD_BEACONS"

if [ "$B_INIT" -ge "$MIN_CHANGED_LINES" ] && [ "$MINION" -ge "$MIN_CHANGED_LINES" ] && [ "$MOD_BEACONS" -ge "$MIN_CHANGED_LINES" ]; then
    echo "PASS: AC5 - non-trivial changes (>= $MIN_CHANGED_LINES lines each) found in all three files: salt/beacons/__init__.py, salt/minion.py, salt/modules/beacons.py"
    exit 0
else
    echo "FAIL: AC5 - feature is not spread across all three required files (need >= $MIN_CHANGED_LINES changed lines each); got beacons/__init__.py=$B_INIT minion.py=$MINION modules/beacons.py=$MOD_BEACONS"
    exit 1
fi
