#!/usr/bin/env bash
# R09 Task B (toolbar middle-button "Close Tab") — AC2
# "Tap handling dispatches through Redux (Action -> Middleware -> Store), reusing or extending
#  the existing action vocabulary, rather than the view layer calling tab-closing code directly."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
MW="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarMiddleware.swift"
GBA="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/Actions/GeneralBrowserAction.swift"
TOOLBARKIT_DIR="$REPO/BrowserKit/Sources/ToolbarKit"

BAD=0

if [ ! -f "$MW" ] || [ ! -f "$GBA" ]; then
  echo "FAIL: AC2 - expected files not found"
  exit 1
fi

MW_MATCH=$(grep -n 'didCloseTabFromToolbar\|closeTab' "$MW" || true)
GBA_MATCH=$(grep -n 'didCloseTabFromToolbar\|closeTab' "$GBA" || true)

echo "ToolbarMiddleware.swift matches:"
echo "$MW_MATCH" | sed 's/^/  /'
echo "GeneralBrowserAction.swift matches:"
echo "$GBA_MATCH" | sed 's/^/  /'

if [ -z "$MW_MATCH" ]; then
  echo "  -> no reference to a close-tab action in ToolbarMiddleware.swift"
  BAD=1
fi

# The dispatch must actually happen via store.dispatch near the close-tab reference, not just be
# mentioned in a comment. Look for 'store.dispatch' within 6 lines after the closeTab/
# didCloseTabFromToolbar match in ToolbarMiddleware.swift.
DISPATCH_NEAR=$(grep -n 'didCloseTabFromToolbar\|closeTab' "$MW" | cut -d: -f1 | while read -r ln; do
  sed -n "${ln},$((ln+6))p" "$MW" | grep -c 'store\.dispatch'
done | grep -c '^[1-9]' || true)

if [ "$DISPATCH_NEAR" -lt 1 ]; then
  echo "  -> found a close-tab reference in ToolbarMiddleware.swift but no nearby store.dispatch(...) call"
  BAD=1
fi

# Trap signature: ToolbarKit (BrowserKit) view/model directly wired to a TabManager-shaped closure.
if [ -d "$TOOLBARKIT_DIR" ]; then
  TK_MATCH=$(grep -rln 'TabManager' "$TOOLBARKIT_DIR" || true)
  if [ -n "$TK_MATCH" ]; then
    echo "  -> BrowserKit/Sources/ToolbarKit references TabManager directly (trap signature):"
    echo "$TK_MATCH" | sed 's/^/    /'
    BAD=1
  fi
fi

if [ "$BAD" -eq 1 ]; then
  echo "FAIL: AC2 - tap handling does not clearly dispatch a Redux action from ToolbarMiddleware for the close-tab case"
  exit 1
else
  echo "PASS: AC2 - ToolbarMiddleware dispatches a close-tab-related GeneralBrowserAction via store.dispatch(...); no BrowserKit/ToolbarKit reference to TabManager found"
  exit 0
fi
