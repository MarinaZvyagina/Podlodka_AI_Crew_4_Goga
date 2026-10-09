#!/usr/bin/env bash
# Task A / AC1: New preference reuses MediaBandwidthPreferences.MediaType enum / MediaBandwidthPreferenceStore
# rather than introducing a new storage mechanism (UserDefaults key, new KV-store collection, new table/migration).
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree"
  exit 1
fi

# --- helpers: include untracked new files in "diff" output without touching the git index ---
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
# --- end helpers ---

PREF_FILE="SignalServiceKit/Messages/Attachments/V2/Downloads/Preferences/MediaBandwidthPreferenceStore.swift"

DIFF_ALL="$(safe_diff .)"
DIFF_PREF="$(safe_diff "$PREF_FILE")"

if [ -z "$DIFF_ALL" ]; then
  echo "FAIL: no working-tree changes found (nothing to check)"
  exit 1
fi

# 1. A new `case` was added inside MediaBandwidthPreferenceStore.swift (expected: inside enum MediaType).
NEW_CASE_LINES="$(echo "$DIFF_PREF" | grep -E '^\+\s*case\s+[A-Za-z_][A-Za-z0-9_]*' || true)"
NEW_CASE_COUNT="$(echo "$NEW_CASE_LINES" | grep -c . || true)"

if [ -z "$DIFF_PREF" ] || [ "$NEW_CASE_COUNT" -eq 0 ]; then
  echo "FAIL: no new 'case' added to $PREF_FILE (MediaType enum not extended)"
  exit 1
fi

# 2. No new parallel persistence mechanism introduced anywhere in the diff:
#    new UserDefaults usage, a newly-added NewKeyValueStore(collection:) call (a *new* store instance),
#    or a new DB migration / table.
NEW_USERDEFAULTS="$(echo "$DIFF_ALL" | grep -E '^\+.*UserDefaults\(' || true)"
NEW_KVSTORE_CALLS="$(echo "$DIFF_ALL" | grep -E '^\+.*NewKeyValueStore\(collection:' || true)"
NEW_MIGRATION_FILES="$(safe_new_files . | grep -iE 'migration' || true)"

if [ -n "$NEW_USERDEFAULTS" ]; then
  echo "FAIL: diff introduces new UserDefaults(...) usage:"
  echo "$NEW_USERDEFAULTS"
  exit 1
fi

if [ -n "$NEW_MIGRATION_FILES" ]; then
  echo "FAIL: diff adds new migration-looking files (possible new table):"
  echo "$NEW_MIGRATION_FILES"
  exit 1
fi

if [ -n "$NEW_KVSTORE_CALLS" ]; then
  echo "FAIL: diff adds a new NewKeyValueStore(collection: ...) call, suggesting a parallel storage mechanism:"
  echo "$NEW_KVSTORE_CALLS"
  exit 1
fi

echo "PASS: exactly one (or more) new MediaType case(s) added in $PREF_FILE; no new UserDefaults/KV-store/migration introduced."
echo "New case line(s):"
echo "$NEW_CASE_LINES"
exit 0
