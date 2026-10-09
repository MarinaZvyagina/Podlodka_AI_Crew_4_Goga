#!/usr/bin/env bash
# R09 Task B (toolbar middle-button "Close Tab") — AC5
# "Telemetry for the new button reuses ToolbarTelemetry rather than being recorded ad hoc."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
TELEMETRY="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/ToolbarTelemetry.swift"
MW="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarMiddleware.swift"

if [ ! -f "$TELEMETRY" ] || [ ! -f "$MW" ]; then
  echo "FAIL: AC5 - expected files not found"
  exit 1
fi

METHODS=$(grep -n 'func .*ButtonTapped' "$TELEMETRY")
echo "ToolbarTelemetry tap-recording methods:"
echo "$METHODS" | sed 's/^/  /'

# Baseline methods that already exist at the pinned commit.
BASELINE_COUNT=$(echo "$METHODS" | grep -cE 'func (clearSearchButtonTapped|shareButtonTapped|refreshButtonTapped|readerModeButtonTapped|siteInfoButtonTapped|backButtonTapped|forwardButtonTapped|homeButtonTapped|oneTapNewTabButtonTapped|searchButtonTapped|tabTrayButtonTapped|menuButtonTapped|googleLensButtonTapped)\(')
TOTAL_COUNT=$(echo "$METHODS" | grep -c 'func .*ButtonTapped' || true)

NEW_METHOD=$(echo "$METHODS" | grep -vE 'func (clearSearchButtonTapped|shareButtonTapped|refreshButtonTapped|readerModeButtonTapped|siteInfoButtonTapped|backButtonTapped|forwardButtonTapped|homeButtonTapped|oneTapNewTabButtonTapped|searchButtonTapped|tabTrayButtonTapped|menuButtonTapped|googleLensButtonTapped)\(' || true)

if [ -z "$NEW_METHOD" ]; then
  echo "FAIL: AC5 - no new *ButtonTapped method found in ToolbarTelemetry.swift beyond the pre-existing baseline ($BASELINE_COUNT methods, $TOTAL_COUNT total)"
  exit 1
fi

echo "New telemetry method candidate(s):"
echo "$NEW_METHOD" | sed 's/^/  /'

# Extract the new method's name and confirm it's called from ToolbarMiddleware.swift.
NEW_METHOD_NAME=$(echo "$NEW_METHOD" | head -1 | sed -E 's/.*func ([a-zA-Z0-9_]+)\(.*/\1/')
CALL_SITE=$(grep -n "$NEW_METHOD_NAME(" "$MW" || true)

if [ -z "$CALL_SITE" ]; then
  echo "FAIL: AC5 - new telemetry method '$NEW_METHOD_NAME' is not called from ToolbarMiddleware.swift"
  exit 1
fi

echo "Call site in ToolbarMiddleware.swift:"
echo "$CALL_SITE" | sed 's/^/  /'

# Trap signature: GleanMetrics.Toolbar.* called directly outside ToolbarTelemetry.swift.
STRAY_GLEAN=$(grep -rn 'GleanMetrics\.Toolbar' "$REPO/firefox-ios/Client/Frontend/Browser/Toolbars" 2>/dev/null \
  | grep -v "ToolbarTelemetry.swift" || true)

if [ -n "$STRAY_GLEAN" ]; then
  echo "FAIL: AC5 - GleanMetrics.Toolbar is referenced outside ToolbarTelemetry.swift (ad hoc telemetry):"
  echo "$STRAY_GLEAN" | sed 's/^/  /'
  exit 1
fi

echo "PASS: AC5 - a new ToolbarTelemetry method ('$NEW_METHOD_NAME') was added and is called from ToolbarMiddleware's tap-handling code; no stray GleanMetrics.Toolbar calls found elsewhere"
exit 0
