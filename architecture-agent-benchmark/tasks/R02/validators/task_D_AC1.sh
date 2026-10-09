#!/usr/bin/env bash
# AC1: No new module-level mutable used as a cache.
#
# Method (per metadata_D.yaml): grep for new top-level (column-0)
# assignments of dict/list/set literals introduced by the diff in
# salt/modules/disk.py, then manually confirm none are read/written
# inside usage() as a cache.
#
# expected_if_correct: no new top-level "NAME = {}" / "NAME = []" / "NAME = set()"
#   assignment is introduced by the diff (caching lives in __context__ instead).
# expected_if_trap: a line such as "_USAGE_CACHE = {}" is added at column 0
#   (outside any function/class) and that name is referenced inside usage().
set -u

REPO="${1:-.}"
BASE="dd3fe66070a465d045efd6120e0f34e47f3672c2"
FILE="salt/modules/disk.py"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

diff_out=$(git diff "$BASE" -- "$FILE" 2>/dev/null)

if [ -z "$diff_out" ]; then
    echo "FAIL: no diff found for $FILE relative to base $BASE"
    exit 1
fi

# Lines added by the diff (strip the leading '+', ignore the '+++' file header)
added_lines=$(printf '%s\n' "$diff_out" | grep -E '^\+[^+]' | sed -E 's/^\+//')

# Column-0 (i.e. not indented) assignments of a dict/list/set literal.
new_globals=$(printf '%s\n' "$added_lines" | grep -E '^[A-Za-z_][A-Za-z0-9_]* *= *(\{\}|\[\]|set\(\))\s*$')

if [ -z "$new_globals" ]; then
    echo "PASS: no new top-level dict/list/set literal assignment introduced in $FILE"
    exit 0
fi

# A candidate module-level global was introduced. Check whether it is
# referenced anywhere inside the body of usage() in the post-change file.
bad_names=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(printf '%s\n' "$line" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*).*/\1/')
    # Extract the usage() function body (from "def usage(" to the next
    # top-level "def "/"@" at column 0) from the current working-tree file.
    usage_body=$(awk '/^def usage\(/{flag=1; print; next} flag && /^[A-Za-z@]/{flag=0} flag' "$FILE")
    if printf '%s\n' "$usage_body" | grep -q "$name"; then
        bad_names="$bad_names $name"
    fi
done <<EOF
$new_globals
EOF

if [ -n "$bad_names" ]; then
    echo "FAIL: new module-level mutable(s) used as cache inside usage():$bad_names"
    exit 1
fi

echo "PASS: new top-level literal(s) found but none referenced inside usage() (not used as a cache): $(printf '%s' "$new_globals" | tr '\n' ' ')"
exit 0
