#!/usr/bin/env bash
# AC1: Snooze state persisted via schema migration, not ad hoc local storage.
#
# Checks:
#  1. A new migration file data/src/main/sqldelight/tachiyomi/migrations/15.sqm exists in the
#     working tree, did NOT exist at HEAD (the pinned base commit), and looks like it adds a
#     column to the mangas table.
#  2. data/src/main/sqldelight/tachiyomi/data/mangas.sq gained a new INTEGER column related to
#     snoozing (a diff, not just file existence, so we know it was actually changed).
set -uo pipefail

REPO="${1:-.}"

MIGRATION="data/src/main/sqldelight/tachiyomi/migrations/15.sqm"
MANGAS_SQ="data/src/main/sqldelight/tachiyomi/data/mangas.sq"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

# 1. Migration file must be new (absent at HEAD) and non-trivial in the working tree.
if git -C "$REPO" show "HEAD:$MIGRATION" >/dev/null 2>&1; then
    echo "FAIL: $MIGRATION already existed at HEAD — expected a brand new migration file (migrations were numbered 1-14 at the pinned base commit)"
    exit 1
fi

if [ ! -s "$REPO/$MIGRATION" ]; then
    echo "FAIL: $MIGRATION does not exist (or is empty) in the working tree"
    exit 1
fi

if ! grep -qiE 'ALTER[[:space:]]+TABLE[[:space:]]+mangas[[:space:]]+ADD[[:space:]]+COLUMN' "$REPO/$MIGRATION"; then
    echo "FAIL: $MIGRATION does not look like it adds a column to the mangas table"
    exit 1
fi

# 2. mangas.sq must show an added column, and it should look snooze-related.
MANGAS_DIFF_ADDED="$(git -C "$REPO" diff -- "$MANGAS_SQ" | grep -E '^\+' | grep -vE '^\+\+\+')"

if [ -z "$MANGAS_DIFF_ADDED" ]; then
    echo "FAIL: no diff found in $MANGAS_SQ — expected a new column to be added to the mangas table"
    exit 1
fi

if ! echo "$MANGAS_DIFF_ADDED" | grep -qiE '^\+[[:space:]]*[a-z_]*snooz[a-z_]*[[:space:]]+INTEGER'; then
    echo "FAIL: $MANGAS_SQ was changed, but no new INTEGER column with a snooze-related name was found in the added lines"
    exit 1
fi

echo "PASS: new migration $MIGRATION (absent at HEAD) alters the mangas table, and $MANGAS_SQ gained a new snooze-related INTEGER column"
exit 0
