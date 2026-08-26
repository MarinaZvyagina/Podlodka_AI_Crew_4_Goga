#!/usr/bin/env bash
# Task A / AC4: Settings UI reuses the existing per-type screen pattern (MediaType.allCases loop + exhaustive
# switches) instead of a bespoke new screen/loop/table row built specifically for voice messages.
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

DATA_SETTINGS="Signal/src/ViewControllers/AppSettings/Data Usage/DataSettingsTableViewController.swift"
MEDIA_DL_SETTINGS="Signal/src/ViewControllers/AppSettings/Data Usage/MediaDownloadSettingsViewController.swift"

FAIL=0

# 1. No new UIViewController subclass introduced anywhere in the diff for this feature (bespoke screen).
NEW_FILES="$(safe_new_files . || true)"
NEW_VC_FILES="$(echo "$NEW_FILES" | grep -iE 'viewcontroller' || true)"
if [ -n "$NEW_VC_FILES" ]; then
  echo "FAIL: diff adds new view-controller file(s), suggesting a bespoke screen rather than reuse of the existing pattern:"
  echo "$NEW_VC_FILES"
  FAIL=1
fi

# 2. Any new `class ... : UIViewController` / `class ...ViewController` declared inline in changed files.
for f in "$DATA_SETTINGS" "$MEDIA_DL_SETTINGS"; do
  d="$(safe_diff "$f" 2>/dev/null || true)"
  newclass="$(echo "$d" | grep -E '^\+\s*(public |internal |private )?(final )?class\s+\w*ViewController' || true)"
  if [ -n "$newclass" ]; then
    echo "FAIL: $f diff declares a new ViewController class:"
    echo "$newclass"
    FAIL=1
  fi
done

# 3. The existing `allCases` iteration loop must still be present (not replaced by a hardcoded new loop/row).
if [ -f "$DATA_SETTINGS" ]; then
  ALLCASES_PRESENT="$(grep -nE 'MediaBandwidthPreferences\.MediaType\.allCases' "$DATA_SETTINGS" || true)"
  if [ -z "$ALLCASES_PRESENT" ]; then
    echo "FAIL: $DATA_SETTINGS no longer contains a 'MediaBandwidthPreferences.MediaType.allCases' loop"
    FAIL=1
  fi
fi

# 4. Grep the diff to DataSettingsTableViewController.swift specifically for a hand-added table row/action
#    referencing voice messages outside the `allCases` loop (the correct solution leaves this file's loop
#    untouched, since it already picks up new MediaType cases automatically — any new disclosureItem/table
#    item/show*View call added here for voice messages is a strong trap signal). We deliberately do NOT apply
#    this heuristic to MediaDownloadSettingsViewController.swift, since a legitimate new `case .voiceMessage:`
#    branch in its exhaustive name(...) switches will itself contain the word "voice" and would otherwise be a
#    false positive.
d_data="$(safe_diff "$DATA_SETTINGS" 2>/dev/null || true)"
hardcoded_row="$(echo "$d_data" | grep -iE '^\+.*(disclosureItem|OWSTableItem|\.item\(|showVoiceMessage|VoiceMessageAutoDownload)' | grep -i 'voice' || true)"
hardcoded_row2="$(echo "$d_data" | grep -iE '^\+.*(disclosureItem|OWSTableItem\(|\.item\()' || true)"
if [ -n "$hardcoded_row" ] || [ -n "$hardcoded_row2" ]; then
  echo "FAIL: $DATA_SETTINGS diff adds a hand-added table row/action (e.g. a manually appended OWSTableItem/disclosureItem or a call to a bespoke voice-message screen) outside the existing allCases loop:"
  echo "$hardcoded_row$hardcoded_row2"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: no new ViewController file/class introduced; existing MediaType.allCases loop in $DATA_SETTINGS is intact; no hand-added row detected outside the loop/switch."
exit 0
