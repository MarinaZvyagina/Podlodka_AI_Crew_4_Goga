#!/usr/bin/env bash
# task_A_AC4 (R04-TA): "Public component API remains backward compatible."
# Method: diff packages/excalidraw/types.ts for the AppState/ExcalidrawProps
# name-related fields. If the file wasn't touched at all, it's trivially
# backward compatible. If it was touched, do a best-effort automated check for
# the `name` field's optionality/type and flag anything suspicious; otherwise
# ask for manual review since detecting "no new required prop anywhere" in
# general is not reliably automatable via grep.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

TYPES=packages/excalidraw/types.ts
if [ ! -f "$TYPES" ]; then
  echo "MANUAL REVIEW REQUIRED: $TYPES not found in repo"
  exit 1
fi

DIFF=$(git diff HEAD -- "$TYPES" 2>/dev/null)

if [ -z "$DIFF" ]; then
  echo "PASS: $TYPES was not modified at all; AppState/ExcalidrawProps name-related fields unchanged"
  exit 0
fi

# types.ts was touched -- look specifically at changed lines mentioning `name`
NAME_LINES=$(echo "$DIFF" | grep -E '^[+-].*\bname\b' || true)

if [ -z "$NAME_LINES" ]; then
  echo "MANUAL REVIEW REQUIRED: $TYPES changed but no line touching a 'name' field was found automatically -- review the diff manually to confirm AppState/ExcalidrawProps fields are unaffected:"
  echo "$DIFF"
  exit 1
fi

# Heuristic: flag if a previously optional (`name?:`) field lost its `?`, or if a
# removed `name` line was string-typed but the corresponding added line is not.
REMOVED_OPTIONAL=$(echo "$NAME_LINES" | grep -E '^-.*name\?:' || true)
ADDED_OPTIONAL=$(echo "$NAME_LINES" | grep -E '^\+.*name\?:' || true)
REMOVED_REQUIRED_STRING=$(echo "$NAME_LINES" | grep -E '^-.*name: *string' || true)
ADDED_REQUIRED_STRING=$(echo "$NAME_LINES" | grep -E '^\+.*name: *string' || true)

SUSPICIOUS=0
if [ -n "$REMOVED_OPTIONAL" ] && [ -z "$ADDED_OPTIONAL" ]; then
  SUSPICIOUS=1
fi
if [ -n "$REMOVED_REQUIRED_STRING" ] && [ -z "$ADDED_REQUIRED_STRING" ]; then
  SUSPICIOUS=1
fi

# Any brand-new required (non-optional, no `?`) prop line being added is a smell.
NEW_REQUIRED_PROP=$(echo "$NAME_LINES" | grep -E '^\+' | grep -vE '\?:' || true)

if [ "$SUSPICIOUS" -eq 1 ] || [ -n "$NEW_REQUIRED_PROP" ]; then
  echo "FAIL: types.ts changes to 'name' fields look backward-incompatible (optionality/type narrowed or a new required prop added):"
  echo "$NAME_LINES"
  exit 1
fi

echo "MANUAL REVIEW REQUIRED: $TYPES was modified and touches 'name' fields, but automated heuristics found nothing clearly breaking -- confirm by hand that AppState['name']/ExcalidrawProps name-related fields remain optional/string with no new required props:"
echo "$NAME_LINES"
exit 1
