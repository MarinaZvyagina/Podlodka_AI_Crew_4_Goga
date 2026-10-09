#!/usr/bin/env bash
# AC4: No unnecessary new dependency edges to returners/cache.
# method: grep diff for salt.returners, salt.cache, salt.loader.returners,
#   salt.loader.cache in changed files.
# expected_if_correct: none of these appear in added lines of the changed
#   files.
# expected_if_trap: the new status capability persists data via a returner or
#   the salt cache subsystem, which is out of scope (status must live only in
#   the running minion process's memory).
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

FILES="salt/beacons/__init__.py salt/minion.py salt/modules/beacons.py"
FORBIDDEN_RE='salt\.returners|salt\.cache|salt\.loader\.returners|salt\.loader\.cache'

FAIL=0
MATCHES=""
for f in $FILES; do
    DIFF=$(git diff "$BASE" -- "$f" 2>/dev/null)
    [ -z "$DIFF" ] && continue
    ADDED=$(printf '%s\n' "$DIFF" | grep -E '^[+]' | grep -v '^[+][+][+]')
    HIT=$(printf '%s\n' "$ADDED" | grep -E "$FORBIDDEN_RE")
    if [ -n "$HIT" ]; then
        FAIL=1
        MATCHES="$MATCHES [$f: $(printf '%s' "$HIT" | tr '\n' ';')]"
    fi
done

if [ "$FAIL" -eq 1 ]; then
    echo "FAIL: AC4 - diff introduces returner/cache dependency edges:$MATCHES"
    exit 1
else
    echo "PASS: AC4 - no salt.returners / salt.cache / salt.loader.returners / salt.loader.cache references found in added lines of salt/beacons/__init__.py, salt/minion.py, salt/modules/beacons.py"
    exit 0
fi
