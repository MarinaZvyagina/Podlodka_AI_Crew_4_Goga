#!/usr/bin/env bash
# AC5: Presentation code reaches the snooze feature only through domain interactors.
#
# Checks:
#  - Lines ADDED by the diff under app/src/main/java/eu/kanade/presentation/ and
#    app/src/main/java/eu/kanade/tachiyomi/ui/updates/ contain no references to
#    tachiyomi.data.Database, mangasQueries, or updatesViewQueries (i.e. the change under test
#    does not introduce direct DB/SQLDelight access from presentation code).
#
# Note: this intentionally only inspects lines the diff *adds*, not the full pre-existing file
# contents — some pre-existing, unrelated screens (e.g. ClearDatabaseScreen.kt) already touch
# tachiyomi.data.Database for other features, and that pre-existing usage should not fail this
# check for an unrelated snooze-feature diff.
set -uo pipefail

REPO="${1:-.}"

DIR1="app/src/main/java/eu/kanade/presentation"
DIR2="app/src/main/java/eu/kanade/tachiyomi/ui/updates"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

if [ ! -d "$REPO/$DIR1" ] && [ ! -d "$REPO/$DIR2" ]; then
    echo "FAIL: expected directories $DIR1 and/or $DIR2 not found in '$REPO'"
    exit 1
fi

HITS=""

# Modified/tracked files: inspect only added lines.
CHANGED_FILES="$(git -C "$REPO" diff --name-only -- "$DIR1" "$DIR2" 2>/dev/null || true)"
for f in $CHANGED_FILES; do
    ADDED="$(git -C "$REPO" diff -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+')"
    MATCH="$(echo "$ADDED" | grep -nE 'tachiyomi\.data\.Database|mangasQueries|updatesViewQueries' || true)"
    if [ -n "$MATCH" ]; then
        HITS="$HITS
$f: $MATCH"
    fi
done

# New (untracked) files: inspect full contents.
NEW_FILES="$(git -C "$REPO" status --porcelain -- "$DIR1" "$DIR2" 2>/dev/null | awk '$1 == "??" {print $2}')"
for f in $NEW_FILES; do
    MATCH="$(grep -nE 'tachiyomi\.data\.Database|mangasQueries|updatesViewQueries' "$REPO/$f" 2>/dev/null || true)"
    if [ -n "$MATCH" ]; then
        HITS="$HITS
$f: $MATCH"
    fi
done

if [ -n "$HITS" ]; then
    echo "FAIL: diff introduces presentation code referencing Database/mangasQueries/updatesViewQueries directly:$HITS"
    exit 1
fi

echo "PASS: no diff-introduced Database/mangasQueries/updatesViewQueries references found under $DIR1 or $DIR2"
exit 0
