#!/usr/bin/env bash
# R09 Task D (Copy Address toast, architecture trap) — AC3
# "The reducer path for state.toast is reused unmodified, not duplicated."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: AC3 - '$1' is not a git repo working directory"
  exit 1
fi
cd "$REPO" || exit 1

FILE="firefox-ios/Client/Frontend/Browser/BrowserViewController/State/BrowserViewControllerState.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC3 - $FILE not found"
  exit 1
fi

DIFF=$(git diff -- "$FILE" 2>&1)

if [ -z "$DIFF" ]; then
  echo "PASS: AC3 - $FILE is completely unchanged vs. the pinned commit; the existing toast reducer path is reused as-is"
  exit 0
fi

echo "$FILE was modified. Diff:"
echo "$DIFF"

# It's plausible (though not required) for a correct implementation to touch other parts of this
# very large file for unrelated reasons; the specific violation we're checking for is a NEW state
# field or a NEW reducer branch introduced specifically for this one toast.
NEW_FIELD=$(echo "$DIFF" | grep -E '^\+' | grep -iE 'var .*copyAddress.*:|var .*copyURL.*Toast|var .*Visible\s*:\s*Bool' || true)
TOAST_REDUCER_CHANGED=$(echo "$DIFF" | grep -E '^[+-]' | grep -E 'guard let toastType = action\.toastType|\.copy\(toast: toastType\)' || true)

if [ -n "$NEW_FIELD" ]; then
  echo "FAIL: AC3 - a new state field appears to have been added specifically for this toast (duplicating the generic 'toast: ToastType?' field):"
  echo "$NEW_FIELD"
  exit 1
fi

if [ -n "$TOAST_REDUCER_CHANGED" ]; then
  echo "FAIL: AC3 - the existing 'guard let toastType = action.toastType ... .copy(toast: toastType)' reducer logic was modified"
  exit 1
fi

echo "PASS: AC3 - file was touched but neither a new toast-specific state field nor the existing toast reducer branch were changed"
exit 0
