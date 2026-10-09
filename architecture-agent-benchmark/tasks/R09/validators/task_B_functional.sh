#!/usr/bin/env bash
# R09 Task B (toolbar middle-button "Close Tab") — FUNCTIONAL validator
#
# Ticket: add a third "Close Tab" choice for the navigation toolbar's customizable middle button,
# selectable in Settings > Appearance, persisted like the existing two choices, closing the active
# tab when tapped, and measured like the other two choices.
#
# ENVIRONMENT LIMITATION (confirmed by direct reproduction, not assumed): this task's correct
# solution lives entirely in firefox-ios/Client, the main "Fennec" app target. A full
# `xcodebuild build/test -scheme Fennec` was attempted here and gets real distance (resolves the
# ~98-target/~20-package dependency graph, begins real compilation) before failing on:
#   bash: <repo>/firefox-ios/bin/nimbus-fml.sh: No such file or directory
# ("Nimbus Feature Manifest Generator Script" build phase). That tool is fetched by bootstrap.sh
# from an external URL; fetching/executing a remote script as part of a validator was denied by this
# environment's own tooling-execution policy, and is out of scope for a benchmark validator that
# must run unattended against arbitrary candidate repos, so this is a hard, reproducible environment
# limitation, not a defect in any candidate diff. This matches ../CONTROL_RESULTS.md's own finding
# for this task.
#
# Given that, this script performs the best REAL, AUTOMATED check available without a full app
# build: `swiftc -parse` (real Swift compiler, real syntax parsing against the iOS Simulator SDK) on
# every Swift file changed relative to the pinned commit (de940072da700c2af7d74348b5775674d106d503)
# under the known feature area, plus a fixed list of files this feature is documented to touch. This
# is a genuine, non-fabricated PASS/FAIL gate: a candidate diff with broken Swift syntax will FAIL
# here for real. It cannot, however, verify runtime behaviour (does tapping the button actually
# close the tab? does the picker show 3 options at runtime? does telemetry actually fire?) — for
# that this script extracts and prints the exact evidence a human (or an agent with repo access)
# needs to make that call quickly, and reports MANUAL REVIEW REQUIRED rather than fabricating a PASS.
#
# Usage: task_B_functional.sh [path-to-repo-root]  (default: .)
# Exit codes: 0 = PASS (should not normally happen — see above), 1 = FAIL (syntax broken /
#             feature evidently absent), 2 = MANUAL REVIEW REQUIRED (syntax OK, runtime behaviour
#             requires human judgement).

set -uo pipefail

PINNED_COMMIT="de940072da700c2af7d74348b5775674d106d503"

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  echo "FAIL: could not resolve repo path '$1'"
  exit 1
fi

NAV_STATE="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Redux/NavigationBarState.swift"
TOOLBAR_MW="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarMiddleware.swift"
TOOLBAR_TELEMETRY="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/ToolbarTelemetry.swift"
TOOLBAR_ACTION_CONFIG="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarActionConfiguration.swift"
NAV_TOOLBAR_MODEL="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Models/NavigationToolbarContainerModel.swift"
SETTINGS_PICKER="$REPO/firefox-ios/Client/Frontend/Settings/AppearanceSettings/NavigationBarMiddleButtonSelectionView.swift"
GENERAL_ACTION="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/Actions/GeneralBrowserAction.swift"

for f in "$NAV_STATE" "$TOOLBAR_MW"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: expected file not found: $f"
    exit 1
  fi
done

echo "=== Step 1: real swiftc -parse syntax check on the feature's known files + any other changed Swift files ==="
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
if [ -z "$SDK" ]; then
  echo "FAIL: could not resolve iOS Simulator SDK path via xcrun"
  exit 1
fi

KNOWN_FILES=(
  "$NAV_STATE" "$TOOLBAR_MW" "$TOOLBAR_TELEMETRY" "$TOOLBAR_ACTION_CONFIG"
  "$NAV_TOOLBAR_MODEL" "$SETTINGS_PICKER" "$GENERAL_ACTION"
)

# Best-effort: also pick up any other Swift files changed relative to the pinned commit (tracked
# modifications + untracked new files), in case the candidate's solution touches files beyond the
# documented set. Silently skipped if this isn't a git repo or the pinned commit isn't an ancestor
# (e.g. a shallow clone) — the KNOWN_FILES list above still gets checked regardless.
DIFF_FILES=""
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
   git -C "$REPO" cat-file -e "$PINNED_COMMIT" 2>/dev/null; then
  DIFF_FILES=$(git -C "$REPO" diff --name-only --diff-filter=ACMR "$PINNED_COMMIT" -- '*.swift' 2>/dev/null | grep '^firefox-ios/' || true)
  UNTRACKED=$(git -C "$REPO" ls-files --others --exclude-standard -- '*.swift' 2>/dev/null | grep '^firefox-ios/' || true)
  DIFF_FILES=$(printf '%s\n%s\n' "$DIFF_FILES" "$UNTRACKED" | sed '/^$/d' | sort -u)
fi

ALL_FILES=$(
  { for f in "${KNOWN_FILES[@]}"; do [ -f "$f" ] && echo "$f"; done
    if [ -n "$DIFF_FILES" ]; then
      while IFS= read -r rel; do [ -n "$rel" ] && [ -f "$REPO/$rel" ] && echo "$REPO/$rel"; done <<< "$DIFF_FILES"
    fi
  } | sort -u
)

PARSE_FAILED=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  OUT=$(swiftc -parse -sdk "$SDK" -target arm64-apple-ios17.0-simulator "$f" 2>&1)
  if [ -n "$OUT" ]; then
    echo "-- swiftc -parse errors in $f:"
    echo "$OUT" | sed 's/^/     /'
    PARSE_FAILED=1
  else
    echo "-- OK: $f"
  fi
done <<< "$ALL_FILES"

if [ "$PARSE_FAILED" -eq 1 ]; then
  echo
  echo "FAIL: Task B functional check — one or more Swift files relevant to this feature have real syntax errors (swiftc -parse). A submission that doesn't parse cannot possibly satisfy the ticket's functional requirements."
  exit 1
fi

echo
echo "=== Step 2: does a third middle-button option exist at all? (automated — not manual review) ==="

ENUM_BLOCK=$(grep -n 'enum NavigationBarMiddleButtonType' -A 20 "$NAV_STATE")
echo "$ENUM_BLOCK" | sed 's/^/     /'
ENUM_BLOCK_STRIPPED=$(echo "$ENUM_BLOCK" | sed -E 's/^[0-9]+[:-]//')
THIRD_CASE=$(echo "$ENUM_BLOCK_STRIPPED" | grep -E '^\s*case [a-zA-Z]+\s*$' | grep -vE 'case (home|newTab)\s*$' | head -1 | sed -E 's/^[[:space:]]*case[[:space:]]+//' | xargs)

if [ -z "$THIRD_CASE" ]; then
  echo
  echo "FAIL: Task B functional check — NavigationBarMiddleButtonType still only has 'home' and 'newTab'; no third case was added anywhere. The ticket's core functional requirement (\"a third choice: Close Tab\") is not implemented at all — this is not a matter of manual judgement."
  exit 1
fi
echo "-> found a third case: '$THIRD_CASE'"

echo
echo "=== Step 3: evidence extraction for manual review (remaining functional requirements from metadata_B.yaml) ==="

echo
echo "-- Persistence: PrefsKeys.Settings.navigationToolbarMiddleButton read/write sites:"
grep -rn 'PrefsKeys.Settings.navigationToolbarMiddleButton' "$REPO/firefox-ios/Client" 2>/dev/null | sed 's/^/     /'

echo
echo "-- Settings picker: does the new option appear where Home/New Tab are already surfaced?"
if [ -f "$SETTINGS_PICKER" ]; then
  grep -n 'NavigationBarMiddleButtonType\.' "$SETTINGS_PICKER" | sed 's/^/     /'
fi

echo
echo "-- Tab-closing call site(s) for the new middle-button option (look for removeTab/closeTab near the new case):"
grep -n 'removeTab\|didCloseTabFromToolbar' "$TOOLBAR_MW" 2>/dev/null | sed 's/^/     /'
if [ -f "$NAV_TOOLBAR_MODEL" ]; then
  grep -n 'removeTab\|closeTab' "$NAV_TOOLBAR_MODEL" | sed 's/^/     /'
fi

echo
echo "-- Telemetry: new *ButtonTapped-style method on ToolbarTelemetry + its call site:"
grep -n 'func .*ButtonTapped' "$TOOLBAR_TELEMETRY" 2>/dev/null | sed 's/^/     /'
grep -n 'toolbarTelemetry\.' "$TOOLBAR_MW" 2>/dev/null | grep -i 'close' | sed 's/^/     /'

echo
echo "MANUAL REVIEW REQUIRED: Task B's correct solution lives in the Client app target, which cannot"
echo "be built/tested in this environment (missing bin/nimbus-fml.sh — see header comment for the"
echo "confirmed root cause). swiftc -parse (Step 1) found no syntax errors in the feature's files, so"
echo "the candidate diff at least compiles at the syntax level. Whether tapping the middle button when"
echo "configured as Close Tab actually closes the active tab, whether the Settings picker shows all"
echo "three options at runtime, whether the choice survives a relaunch, and whether telemetry actually"
echo "fires must be confirmed by a human (or an agent with a working Xcode/Fennec + bootstrap.sh"
echo "environment, via \`fxios test\`) reading the evidence above. Note: per this task's own design"
echo "(see ../controls/task_B_negative.diff and ../CONTROL_RESULTS.md), a diff that closes the tab via"
echo "a direct TabManager call instead of dispatching through Redux would look FUNCTIONALLY identical"
echo "to a manual tester — that architectural distinction is deliberately NOT this script's job; see"
echo "task_B_AC1.sh..task_B_AC5.sh for the automated architecture checks that do catch it."
exit 2
