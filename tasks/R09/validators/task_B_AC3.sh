#!/usr/bin/env bash
# R09 Task B (toolbar middle-button "Close Tab") — AC3
# "Persistence uses the existing Prefs key and is read in the middleware layer, not duplicated."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: AC3 - '$1' is not a git repo working directory"
  exit 1
fi
cd "$REPO" || exit 1

MW="firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarMiddleware.swift"
SETTINGS_DIR="firefox-ios/Client/Frontend/Settings/AppearanceSettings"

KEY_IN_MW=$(grep -c 'PrefsKeys.Settings.navigationToolbarMiddleButton' "$MW" || true)
KEY_IN_SETTINGS=$(grep -rl 'PrefsKeys.Settings.navigationToolbarMiddleButton' "$SETTINGS_DIR" 2>/dev/null | wc -l | tr -d ' ')

echo "PrefsKeys.Settings.navigationToolbarMiddleButton occurrences in ToolbarMiddleware.swift: $KEY_IN_MW"
echo "Settings files referencing the same key: $KEY_IN_SETTINGS"

if [ "$KEY_IN_MW" -lt 1 ] || [ "$KEY_IN_SETTINGS" -lt 1 ]; then
  echo "FAIL: AC3 - existing Prefs key PrefsKeys.Settings.navigationToolbarMiddleButton no longer appears in both the middleware read-site and the Settings write-site"
  exit 1
fi

# Trap signature: a brand-new UserDefaults/Prefs key was introduced just for close-tab.
NEW_KEY_CANDIDATES=$(grep -rniE 'UserDefaults\.(standard|shared)|closeTabPref|closeTabKey' \
  "$MW" "$SETTINGS_DIR" 2>/dev/null || true)

if [ -n "$NEW_KEY_CANDIDATES" ]; then
  echo "FAIL: AC3 - found signs of a new/parallel persistence mechanism instead of reusing PrefsKeys.Settings.navigationToolbarMiddleButton:"
  echo "$NEW_KEY_CANDIDATES" | sed 's/^/  /'
  exit 1
fi

echo "PASS: AC3 - PrefsKeys.Settings.navigationToolbarMiddleButton is still the single read/write site (ToolbarMiddleware read, Settings screen write); no new parallel key found"
exit 0
