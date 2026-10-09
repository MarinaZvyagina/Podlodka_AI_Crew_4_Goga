#!/usr/bin/env bash
# R08 Task A (blocked-contacts sort) — AC2
# "Sort logic exists in exactly one place, not duplicated across layers."
#
# Method: grep -n 'sortedBy|sortWith|Comparator|ORDER BY' across the blocked/ package
# Java files and RecipientTable.kt; count distinct files containing new sorting logic.
# Restricted to files that actually changed vs. the pinned commit, so pre-existing
# unrelated sorting code elsewhere doesn't produce false positives.
#
# Usage: task_A_AC2.sh [repo_dir] [base_ref]
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

CANDIDATE_FILES="app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepository.java \
app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersViewModel.java \
app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersFragment.java \
app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersAdapter.java \
app/src/main/java/org/thoughtcrime/securesms/database/RecipientTable.kt"

CHANGED_FILES=$(git diff --name-only "$BASE_REF" -- $CANDIDATE_FILES)

if [ -z "$CHANGED_FILES" ]; then
  echo "FAIL: AC2 — none of the expected blocked-contacts files changed at all; no sort logic found anywhere."
  exit 1
fi

SORT_PATTERN='sortedBy|sortWith|sortBy|sorted\(|Comparator|ORDER BY|compareTo'
FILES_WITH_SORT=""
COUNT=0
for f in $CHANGED_FILES; do
  [ -f "$f" ] || continue
  # Only look at *added* lines in the diff, to avoid matching pre-existing unrelated code.
  ADDED_HITS=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E -- "$SORT_PATTERN")
  if [ -n "$ADDED_HITS" ]; then
    COUNT=$((COUNT+1))
    FILES_WITH_SORT="$FILES_WITH_SORT $f"
  fi
done

echo "Changed candidate files: $CHANGED_FILES"
echo "Files whose diff adds sorting logic: ${FILES_WITH_SORT:-none}"

# Not just *how many* files contain sort logic, but *which* file(s) — the correct location
# is the repository/data layer (BlockedUsersRepository.java or RecipientTable.kt), per
# expected_result_if_correct: "Exactly one file (repository or RecipientTable query layer)".
# A single file is not sufficient if that file is the UI layer (Fragment/Adapter/ViewModel) —
# that is a wrong-layer violation even without duplication.
WRONG_LAYER_HITS=""
CORRECT_LAYER_HITS=""
for f in $FILES_WITH_SORT; do
  case "$f" in
    *BlockedUsersRepository.java|*RecipientTable.kt)
      CORRECT_LAYER_HITS="$CORRECT_LAYER_HITS $f"
      ;;
    *)
      WRONG_LAYER_HITS="$WRONG_LAYER_HITS $f"
      ;;
  esac
done

if [ "$COUNT" -eq 0 ]; then
  echo "FAIL: AC2 — no sorting logic (sortedBy/sortWith/Comparator/ORDER BY/etc.) found added in any candidate file."
  exit 1
fi

if [ -n "$WRONG_LAYER_HITS" ]; then
  echo "FAIL: AC2 — sorting logic found in UI/ViewModel layer file(s), which is a wrong-layer violation even when not duplicated:$WRONG_LAYER_HITS"
  exit 1
fi

if [ "$COUNT" -eq 1 ] && [ -n "$CORRECT_LAYER_HITS" ]; then
  echo "PASS: AC2 — sorting logic is added in exactly one file, and it is the repository/data layer:$CORRECT_LAYER_HITS"
  exit 0
else
  echo "FAIL: AC2 — sorting logic appears added in $COUNT files (duplicated across layers):$FILES_WITH_SORT"
  exit 1
fi
