#!/usr/bin/env bash
# Task B / AC4: No new standalone search index/table introduced; feature reuses existing FTS + attachment schema.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree"
  exit 1
fi

safe_diff() {
  git diff -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    printf '+++ b/%s (untracked new file)\n' "$f"
    sed 's/^/+/' "$f"
  done
}
safe_new_files() {
  git diff --diff-filter=A --name-only -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null
}

FAIL=0

NEW_FILES="$(safe_new_files . || true)"
NEW_MIGRATION_FILES="$(echo "$NEW_FILES" | grep -iE 'migration' || true)"
if [ -n "$NEW_MIGRATION_FILES" ]; then
  echo "FAIL: diff adds new migration-looking file(s):"
  echo "$NEW_MIGRATION_FILES"
  FAIL=1
fi

DIFF_ALL="$(safe_diff .)"

if [ -z "$DIFF_ALL" ]; then
  echo "FAIL: no working-tree changes found (nothing to check)"
  exit 1
fi

NEW_TABLE_SQL="$(echo "$DIFF_ALL" | grep -iE '^\+.*(CREATE TABLE|CREATE VIRTUAL TABLE|db\.create\(table:)' || true)"
if [ -n "$NEW_TABLE_SQL" ]; then
  echo "FAIL: diff adds new table/schema-creation SQL:"
  echo "$NEW_TABLE_SQL"
  FAIL=1
fi

NEW_DENORMALIZED_CACHE="$(echo "$DIFF_ALL" | grep -iE '^\+.*(messagesWithAttachments|attachmentIndexCache|denormalized)' || true)"
if [ -n "$NEW_DENORMALIZED_CACHE" ]; then
  echo "FAIL: diff appears to introduce a denormalized cache/index dedicated to this filter:"
  echo "$NEW_DENORMALIZED_CACHE"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: no new migration file, schema-creation SQL, or denormalized attachment-presence cache detected in the diff."
echo "MANUAL REVIEW SUGGESTED: confirm filtering is computed at query time by intersecting FullTextSearchIndexer results (or a thread scan) with live attachment-presence checks, not a precomputed/stored index."
exit 0
