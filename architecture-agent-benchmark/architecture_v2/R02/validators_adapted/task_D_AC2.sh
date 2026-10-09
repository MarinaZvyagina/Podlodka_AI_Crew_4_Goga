#!/usr/bin/env bash
# AC2: Caching is implemented via __context__.
#
# Method (per metadata_D.yaml): grep '__context__' salt/modules/disk.py
# post-change and review surrounding lines for a get-or-compute pattern
# keyed on args/flags, inside usage().
#
# expected_if_correct: usage() reads/writes __context__ (e.g.
#   __context__.setdefault("disk.usage", {})[...] = ...) to memoize its result.
# expected_if_trap: no __context__ usage is added at all (the trap caches in
#   a bare module-level global instead).
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"
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

# Extract the usage() function body (from "def usage(" to the next
# top-level "def "/"@" at column 0) from the current working-tree file.
usage_body=$(awk '/^def usage\(/{flag=1; print; next} flag && /^[A-Za-z@]/{flag=0} flag' "$FILE")

if [ -z "$usage_body" ]; then
    echo "FAIL: could not locate usage() function body in $FILE"
    exit 1
fi

if ! printf '%s\n' "$usage_body" | grep -q '__context__'; then
    echo "FAIL: usage() does not reference __context__ at all"
    exit 1
fi

# Confirm it looks like a get-or-compute cache pattern: both a membership /
# get-style read and an assignment/write into __context__.
has_read=$(printf '%s\n' "$usage_body" | grep -E '__context__(\.get\(|\.setdefault\(|\[.*\]| *in )')
has_write=$(printf '%s\n' "$usage_body" | grep -E '__context__(\.setdefault\(|\[.*\] *=)')

if [ -z "$has_read" ] || [ -z "$has_write" ]; then
    echo "FAIL: __context__ is referenced but does not look like a get-or-compute cache pattern in usage()"
    exit 1
fi

echo "PASS: usage() implements a get-or-compute cache pattern keyed via __context__"
exit 0
