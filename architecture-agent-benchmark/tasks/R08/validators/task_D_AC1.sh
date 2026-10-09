#!/usr/bin/env bash
# R08 Task D (search result caching) — AC1
# "The cache lives in/behind the data-access layer (SearchRepository or a class it owns),
# not in the UI-facing Fragment/ViewModel."
#
# Method: grep -Rn 'cache|Cache' across the diff; identify which file(s) declare the new
# cache field/map and where lookups happen.
#
# Usage: task_D_AC1.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-441ba42c3f3175476a1f54eba8e72d8d6d304db7}"

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
  echo "FAIL: AC1 — no files changed; caching was not implemented."
  exit 1
fi

UI_LAYER_FILES="app/src/main/java/org/thoughtcrime/securesms/conversationlist/ConversationListFragment.java app/src/main/java/org/thoughtcrime/securesms/contacts/paged/ContactSearchViewModel.kt"
DATA_LAYER_PREFIX="app/src/main/java/org/thoughtcrime/securesms/search/"

CACHE_IN_UI=""
CACHE_IN_DATA_LAYER=""
for f in $CHANGED_FILES; do
  [ -f "$f" ] || continue
  HIT=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E 'cache|Cache')
  [ -z "$HIT" ] && continue
  case "$f" in
    app/src/main/java/org/thoughtcrime/securesms/conversationlist/ConversationListFragment.java|app/src/main/java/org/thoughtcrime/securesms/contacts/paged/ContactSearchViewModel.kt)
      CACHE_IN_UI="$CACHE_IN_UI $f"
      ;;
    ${DATA_LAYER_PREFIX}*)
      CACHE_IN_DATA_LAYER="$CACHE_IN_DATA_LAYER $f"
      ;;
  esac
done

echo "Cache-related additions in UI layer (Fragment/ViewModel): ${CACHE_IN_UI:-none}"
echo "Cache-related additions in data layer (search/ package): ${CACHE_IN_DATA_LAYER:-none}"

if [ -n "$CACHE_IN_UI" ]; then
  echo "FAIL: AC1 — cache field/logic added directly in the UI/presentation layer (ConversationListFragment or ContactSearchViewModel), bypassing SearchRepository."
  exit 1
fi

if [ -n "$CACHE_IN_DATA_LAYER" ]; then
  echo "PASS: AC1 — cache field/logic found only within the search/ data-access layer (SearchRepository or a class it owns)."
  exit 0
fi

echo "FAIL: AC1 — no cache-related code found in either layer; caching does not appear to be implemented."
exit 1
