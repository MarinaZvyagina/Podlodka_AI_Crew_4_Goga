#!/usr/bin/env bash
# Task B / AC3: Filter orchestration lives in FullTextSearcher.swift (SignalUI), not duplicated ad hoc inside
# ConversationSearchController / the view/controller layer.
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

FTS_FILE="SignalUI/Search/FullTextSearcher.swift"
CONV_SEARCH_FILE="Signal/ConversationView/ConversationSearch.swift"

DIFF_FTS="$(safe_diff "$FTS_FILE")"
DIFF_CONV="$(safe_diff "$CONV_SEARCH_FILE")"

if [ -z "$DIFF_FTS" ]; then
  echo "FAIL: no changes to $FTS_FILE — filter orchestration was not added to the SignalUI search layer"
  exit 1
fi

FAIL=0

BYPASS_DB_READ="$(echo "$DIFF_CONV" | grep -E '^\+.*(databaseStorageRef\.read|databaseStorageRef\.write|SSKEnvironment\.shared\.databaseStorageRef)' || true)"
BYPASS_ATTACHMENT_QUERY="$(echo "$DIFF_CONV" | grep -E '^\+.*(hasBodyAttachments|attachmentStore\.fetchReferences|TSAttachment)' || true)"

if [ -n "$BYPASS_DB_READ" ]; then
  echo "FAIL: $CONV_SEARCH_FILE diff adds direct database reads (databaseStorageRef), suggesting query logic was duplicated in the UI layer instead of delegating to FullTextSearcher:"
  echo "$BYPASS_DB_READ"
  FAIL=1
fi

if [ -n "$BYPASS_ATTACHMENT_QUERY" ]; then
  echo "FAIL: $CONV_SEARCH_FILE diff directly references attachment-lookup APIs, suggesting the filter was implemented ad hoc in the UI layer rather than delegated to FullTextSearcher:"
  echo "$BYPASS_ATTACHMENT_QUERY"
  FAIL=1
fi

STILL_CALLS_SEARCHER="$(grep -nE '(searchWithinConversation|dbSearcher\.)' "$CONV_SEARCH_FILE" 2>/dev/null || true)"
if [ -z "$STILL_CALLS_SEARCHER" ]; then
  echo "FAIL: $CONV_SEARCH_FILE no longer calls searchWithinConversation / dbSearcher at all"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: FullTextSearcher.swift changed (orchestration lives in SignalUI); ConversationSearchController still delegates via searchWithinConversation/dbSearcher and does not read the database or attachment store directly."
exit 0
