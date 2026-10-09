#!/usr/bin/env bash
# Task A / AC2: Download-eligibility logic for voice messages lives in AutoDownloadPolicy.swift (SignalServiceKit),
# not duplicated/special-cased in UI code.
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
safe_changed_files() {
  git diff --name-only -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null
}

POLICY_FILE="SignalServiceKit/Messages/Attachments/V2/Downloads/AutoDownloadPolicy.swift"
UI_FILES=(
  "Signal/src/ViewControllers/AppSettings/Data Usage/DataSettingsTableViewController.swift"
  "Signal/src/ViewControllers/AppSettings/Data Usage/MediaDownloadSettingsViewController.swift"
)

DIFF_POLICY="$(safe_diff "$POLICY_FILE")"

if [ -z "$DIFF_POLICY" ]; then
  echo "FAIL: no changes to $POLICY_FILE — eligibility logic was not added there at all"
  exit 1
fi

VOICE_BRANCH="$(echo "$DIFF_POLICY" | grep -E '^\+.*renderingFlag' | grep -E '\.voiceMessage' || true)"
NEW_PREF_ROUTE="$(echo "$DIFF_POLICY" | grep -E '^\+.*\.preference\(mediaType:' || true)"

if [ -z "$VOICE_BRANCH" ]; then
  echo "FAIL: AutoDownloadPolicy.swift diff has no new branch checking 'renderingFlag == .voiceMessage'"
  exit 1
fi

if [ -z "$NEW_PREF_ROUTE" ]; then
  echo "FAIL: AutoDownloadPolicy.swift diff does not route to a new '.preference(mediaType: ...)' case"
  exit 1
fi

FAIL=0
for f in "${UI_FILES[@]}"; do
  d="$(safe_diff "$f" 2>/dev/null || true)"
  bad="$(echo "$d" | grep -E '^\+.*(renderingFlag|estimatedEncryptedSize|alwaysLimit|isSupportedAudioMimeType)' || true)"
  if [ -n "$bad" ]; then
    echo "FAIL: $f diff appears to duplicate eligibility logic (ad hoc size/renderingFlag/mime check):"
    echo "$bad"
    FAIL=1
  fi
done

OTHER_CHANGED_FILES="$(safe_changed_files . | grep -v "^SignalServiceKit/" | grep -v -F "DataSettingsTableViewController.swift" | grep -v -F "MediaDownloadSettingsViewController.swift" || true)"
for f in $OTHER_CHANGED_FILES; do
  d="$(safe_diff "$f" 2>/dev/null || true)"
  bad="$(echo "$d" | grep -E '^\+.*renderingFlag.*voiceMessage' || true)"
  if [ -n "$bad" ]; then
    echo "FAIL: non-SignalServiceKit file $f duplicates voice-message eligibility decision:"
    echo "$bad"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: eligibility logic (renderingFlag == .voiceMessage -> new preference case) added in AutoDownloadPolicy.swift; no duplication found in UI files."
exit 0
