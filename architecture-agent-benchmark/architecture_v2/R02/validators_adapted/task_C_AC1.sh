#!/usr/bin/env bash
# AC1: New backend implemented as a same-shaped module inside salt/cache/,
#   not a bolted-on parallel utility.
# method: git diff --name-only (plus untracked files, since a brand new
#   backend module is by definition untracked until staged); check a new
#   file exists at salt/cache/<name>.py that did not exist at BASE, and
#   confirm no new files were added under salt/utils/ that implement a
#   store/fetch-style caching API (a sign of a bolted-on parallel utility).
# expected_if_correct: exactly one (or more) new file(s) under salt/cache/
#   (e.g. salt/cache/sqlite.py), and no new salt/utils/*.py file defining
#   both a store-like and a fetch-like method.
# expected_if_trap: the new storage logic lives in a new salt/utils/*.py
#   file (e.g. salt/utils/sqlite_cache.py) with its own store/get/delete
#   API, instead of (or in addition to) a salt/cache/*.py module.
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

# Combine tracked changes (relative to BASE) with untracked new files, since
# a genuinely new module is untracked until the agent stages/commits it.
changed_files() {
    { git diff "$BASE" --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

ALL_CHANGED=$(changed_files)

BASELINE_CACHE_FILES=$(git ls-tree -r --name-only "$BASE" -- salt/cache/ 2>/dev/null)

NEW_CACHE_FILES=$(printf '%s\n' "$ALL_CHANGED" | grep -E '^salt/cache/[^/]+\.py$' | while read -r f; do
    if ! printf '%s\n' "$BASELINE_CACHE_FILES" | grep -qx "$f"; then
        echo "$f"
    fi
done)

# Look for new salt/utils/*.py files that implement a store/fetch-style API
# of their own -- a sign of a parallel, bolted-on caching utility.
SUSPECT_UTILS=""
for f in $(printf '%s\n' "$ALL_CHANGED" | grep -E '^salt/utils/[^/]+\.py$'); do
    if git cat-file -e "$BASE:$f" 2>/dev/null; then
        # File already existed at BASE; only flag it if store/fetch-style
        # methods were newly *added* to it.
        DIFF_ADDED=$(git diff "$BASE" -- "$f" 2>/dev/null | grep -E '^\+' | grep -v -F -- '+++')
    else
        DIFF_ADDED=$(cat "$f" 2>/dev/null | sed 's/^/+/')
    fi
    if printf '%s\n' "$DIFF_ADDED" | grep -Eq 'def (store|fetch|get)\b' \
        && printf '%s\n' "$DIFF_ADDED" | grep -Eq 'class .*Cache'; then
        SUSPECT_UTILS="$SUSPECT_UTILS $f"
    fi
done

FAIL_REASON=""
if [ -z "$NEW_CACHE_FILES" ]; then
    FAIL_REASON="$FAIL_REASON no new file found under salt/cache/ (expected a new salt/cache/<name>.py backend module), so nothing new is selectable via the existing driver-discovery convention;"
fi
if [ -n "$SUSPECT_UTILS" ]; then
    FAIL_REASON="$FAIL_REASON new/modified file(s) under salt/utils/ implement their own cache-like class with store/fetch/get methods (parallel utility instead of a salt/cache/ backend):$SUSPECT_UTILS;"
fi

if [ -n "$FAIL_REASON" ]; then
    echo "FAIL: AC1 -$FAIL_REASON"
    exit 1
fi

echo "PASS: AC1 - new backend module(s) found under salt/cache/ ($(printf '%s' "$NEW_CACHE_FILES" | tr '\n' ' ')); no parallel store/fetch-style caching utility detected under salt/utils/"
exit 0
