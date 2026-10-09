#!/usr/bin/env bash
# AC1: Change set confined to the diskusage beacon and its test.
# expected_if_correct: Only salt/beacons/diskusage.py and
#   tests/pytests/unit/beacons/test_diskusage.py changed (optionally a
#   changelog/doc entry).
# expected_if_trap: A new file appears under salt/beacons/ (e.g.
#   lowdiskusage.py), or changes leak into salt/beacons/__init__.py or
#   salt/minion.py.
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

# Diff pinned base commit against the current working tree (covers both
# committed and uncommitted changes).
changed_files=$(git diff --name-only "$BASE" 2>/dev/null)
# Also pick up new untracked files that git diff (without staging) would miss.
untracked_files=$(git status --porcelain 2>/dev/null | awk '$1 == "??" {print $2}')

all_changed=$(printf '%s\n%s\n' "$changed_files" "$untracked_files" | sed '/^$/d' | sort -u)

if [ -z "$all_changed" ]; then
    echo "FAIL: no changes detected relative to base commit $BASE"
    exit 1
fi

allowed_regex='^(salt/beacons/diskusage\.py|tests/pytests/unit/beacons/test_diskusage\.py|CHANGELOG\.md|doc/.*|changelog/.*)$'

bad_files=$(printf '%s\n' "$all_changed" | grep -Ev "$allowed_regex")

new_beacon_files=$(printf '%s\n' "$all_changed" | grep -E '^salt/beacons/' | grep -v '^salt/beacons/diskusage\.py$')

if [ -n "$new_beacon_files" ]; then
    echo "FAIL: unexpected files/changes under salt/beacons/ besides diskusage.py: $(printf '%s' "$new_beacon_files" | tr '\n' ' ')"
    exit 1
fi

if printf '%s\n' "$all_changed" | grep -qE '^salt/beacons/__init__\.py$|^salt/minion\.py$'; then
    echo "FAIL: changes leaked into salt/beacons/__init__.py or salt/minion.py"
    exit 1
fi

if [ -n "$bad_files" ]; then
    echo "FAIL: changes outside allowed scope: $(printf '%s' "$bad_files" | tr '\n' ' ')"
    exit 1
fi

echo "PASS: change set confined to diskusage beacon/test (files: $(printf '%s' "$all_changed" | tr '\n' ' '))"
exit 0
