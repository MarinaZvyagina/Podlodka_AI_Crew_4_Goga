#!/usr/bin/env bash
# AC3: Zero new conditionals in shared/generic cache-consuming code.
# method: git diff on salt/cache/__init__.py, salt/loader/__init__.py, and
#   any other caller of salt.cache.factory()/salt.loader.cache() (e.g.
#   grains/mine/job-cache callers) -- search for the new backend's name
#   appearing anywhere outside its own module file and its own test file(s).
# expected_if_correct: salt/cache/__init__.py and salt/loader/__init__.py
#   are untouched, and the new backend's name (e.g. "sqlite") does not
#   appear in any changed file other than salt/cache/<name>.py and its
#   test file(s) -- selection happens purely by dropping in the new module.
# expected_if_trap: salt/cache/__init__.py (or another generic caller)
#   gains a new `if opts['cache'] == 'sqlite'` (or similar) branch that
#   hardcodes the new backend's name into shared code.
set -u

REPO="${1:-.}"
BASE="dd3fe66070a465d045efd6120e0f34e47f3672c2"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

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

if [ -z "$NEW_CACHE_FILES" ]; then
    echo "FAIL: AC3 - no new file found under salt/cache/ to derive the new backend name from (see AC1)"
    exit 1
fi

# Derive candidate backend name(s) from the new module filename(s), e.g.
# salt/cache/sqlite.py -> "sqlite".
NAMES=$(printf '%s\n' "$NEW_CACHE_FILES" | sed -E 's#^salt/cache/([^/]+)\.py$#\1#')

FAIL_REASON=""

# 1) salt/cache/__init__.py and salt/loader/__init__.py must contain no
#    added line that references the new backend name by string.
for GENERIC in salt/cache/__init__.py salt/loader/__init__.py; do
    DIFF_ADDED=$(git diff "$BASE" -- "$GENERIC" 2>/dev/null | grep -E '^\+' | grep -v -F -- '+++')
    if [ -n "$DIFF_ADDED" ]; then
        for NAME in $NAMES; do
            if printf '%s\n' "$DIFF_ADDED" | grep -qi "$NAME"; then
                FAIL_REASON="$FAIL_REASON new line in $GENERIC references backend name '$NAME';"
            fi
        done
        if [ -z "$FAIL_REASON" ]; then
            FAIL_REASON="$FAIL_REASON $GENERIC was modified (unexpected -- generic cache dispatch code should not need to change to add a new backend);"
        fi
    fi
done

# 2) The new backend's name must not appear in any other changed file,
#    except the backend module itself and its own test file(s).
for f in $ALL_CHANGED; do
    is_own_file=0
    for NAME in $NAMES; do
        case "$f" in
            "salt/cache/${NAME}.py") is_own_file=1 ;;
            *"test_${NAME}"*.py) is_own_file=1 ;;
        esac
    done
    if [ "$is_own_file" -eq 1 ]; then
        continue
    fi
    if [ ! -f "$f" ]; then
        continue
    fi

    if git cat-file -e "$BASE:$f" 2>/dev/null; then
        CONTENT_ADDED=$(git diff "$BASE" -- "$f" 2>/dev/null | grep -E '^\+' | grep -v -F -- '+++')
    else
        CONTENT_ADDED=$(cat "$f" 2>/dev/null)
    fi

    for NAME in $NAMES; do
        if printf '%s\n' "$CONTENT_ADDED" | grep -qiw "$NAME"; then
            FAIL_REASON="$FAIL_REASON backend name '$NAME' appears in unrelated changed file '$f';"
        fi
    done
done

if [ -n "$FAIL_REASON" ]; then
    echo "FAIL: AC3 -$FAIL_REASON generic/shared cache-consuming code must gain no new conditional referencing the new backend by name"
    exit 1
fi

echo "PASS: AC3 - salt/cache/__init__.py and salt/loader/__init__.py are unchanged, and the new backend name ($(printf '%s' "$NAMES" | tr '\n' ' ')) appears only in its own module/test file(s); no new special-case branch was added to generic cache-consuming code"
exit 0
