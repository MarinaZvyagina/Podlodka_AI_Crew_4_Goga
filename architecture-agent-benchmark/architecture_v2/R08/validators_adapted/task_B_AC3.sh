#!/usr/bin/env bash
# R08 Task B (per-attachment full-quality override) — AC3
# "Per-attachment quality choice reuses the existing TransformProperties.skipTransform
# field rather than new bespoke persistence."
#
# Method: grep -n 'skipTransform|TransformProperties' across the diff; separately check
# for any new file under app/src/main/java/org/thoughtcrime/securesms/database/helpers/
# migration/ (a new DB migration would indicate a new column was added instead of reusing
# the existing field).
#
# Usage: task_B_AC3.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-80dfcfb4bd96efa5f2c1ed16f4407fea33affacd}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout."
  exit 1
fi

CHANGED_FILES=$(git diff --name-only "$BASE_REF" --)

if [ -z "$CHANGED_FILES" ]; then
  echo "FAIL: AC3 — no files changed at all; the feature was not implemented."
  exit 1
fi

SKIP_TRANSFORM_HITS=""
for f in $CHANGED_FILES; do
  [ -f "$f" ] || continue
  HIT=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E 'skipTransform|TransformProperties')
  if [ -n "$HIT" ]; then
    SKIP_TRANSFORM_HITS="$SKIP_TRANSFORM_HITS\n--- $f ---\n$HIT"
  fi
done

NEW_MIGRATION=$(git diff --name-only --diff-filter=A "$BASE_REF" -- app/src/main/java/org/thoughtcrime/securesms/database/helpers/migration/)

echo "Files touching skipTransform/TransformProperties in added lines:"
echo -e "${SKIP_TRANSFORM_HITS:-  none}"
echo ""
echo "New DB migration files: ${NEW_MIGRATION:-none}"

if [ -n "$NEW_MIGRATION" ]; then
  echo "FAIL: AC3 — a new DB migration was added, suggesting a new column/table was introduced instead of reusing TransformProperties.skipTransform."
  exit 1
fi

if [ -z "$SKIP_TRANSFORM_HITS" ]; then
  echo "FAIL: AC3 — no added code references skipTransform/TransformProperties; the per-attachment choice is not wired through the existing flag."
  exit 1
fi

echo "PASS: AC3 — diff sets/reads TransformProperties.skipTransform and introduces no new DB migration."
exit 0
