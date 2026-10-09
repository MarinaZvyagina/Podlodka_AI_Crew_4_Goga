#!/usr/bin/env bash
# R09 Task B (toolbar middle-button "Close Tab") — AC1
# "New middle-button option is modeled as a case of the existing NavigationBarMiddleButtonType
#  enum, not a parallel ad hoc mechanism."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
FILE="$REPO/firefox-ios/Client/Frontend/Browser/Toolbars/Redux/NavigationBarState.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC1 - $FILE not found"
  exit 1
fi

BLOCK_NUMBERED=$(grep -n 'enum NavigationBarMiddleButtonType' -A 20 "$FILE")
echo "$BLOCK_NUMBERED"

if [ -z "$BLOCK_NUMBERED" ]; then
  echo "FAIL: AC1 - could not find 'enum NavigationBarMiddleButtonType' in $FILE"
  exit 1
fi

# Strip the "NN:" / "NN-" line-number prefix that `grep -n` adds so the case-matching regexes
# below (which assume lines start with optional whitespace) actually match.
BLOCK=$(echo "$BLOCK_NUMBERED" | sed -E 's/^[0-9]+[:-]//')

HAS_HOME=$(echo "$BLOCK" | grep -cE '^\s*case home\s*$')
HAS_NEWTAB=$(echo "$BLOCK" | grep -cE '^\s*case newTab\s*$')
HAS_THIRD=$(echo "$BLOCK" | grep -E '^\s*case [a-zA-Z]+\s*$' | grep -vE 'case (home|newTab)\s*$' | head -1)

if [ "$HAS_HOME" -ge 1 ] && [ "$HAS_NEWTAB" -ge 1 ] && [ -n "$HAS_THIRD" ]; then
  THIRD_CASE=$(echo "$HAS_THIRD" | sed -E 's/^[[:space:]]*case[[:space:]]+//' | xargs)
  LABEL_OK=$(grep -A 10 'var label: String' "$FILE" | grep -c "case \.$THIRD_CASE" || true)
  ICON_OK=$(grep -A 10 'var imageName: String' "$FILE" | grep -c "case \.$THIRD_CASE" || true)
  if [ "$LABEL_OK" -ge 1 ] && [ "$ICON_OK" -ge 1 ]; then
    echo "PASS: AC1 - NavigationBarMiddleButtonType has 'home', 'newTab', and a new third case '$THIRD_CASE' with both label and imageName handled"
    exit 0
  else
    echo "FAIL: AC1 - new case '$THIRD_CASE' found, but label/imageName computed properties do not both handle it (label_ok=$LABEL_OK, icon_ok=$ICON_OK)"
    exit 1
  fi
else
  echo "FAIL: AC1 - NavigationBarMiddleButtonType does not have three cases (home, newTab, + a new one). A separate mechanism may have been used instead of extending the enum."
  exit 1
fi
