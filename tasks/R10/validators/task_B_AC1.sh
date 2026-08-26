#!/usr/bin/env bash
# Task B / AC1: No new reverse dependency edge — SignalServiceKit must not start importing SignalUI or the
# Signal app target.
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

FAIL=0

CHANGED_SSK_FILES="$(safe_changed_files SignalServiceKit/ || true)"
for f in $CHANGED_SSK_FILES; do
  d="$(safe_diff "$f" 2>/dev/null || true)"
  bad="$(echo "$d" | grep -E '^\+\s*import\s+(SignalUI|Signal)\s*$' || true)"
  if [ -n "$bad" ]; then
    echo "FAIL: $f (under SignalServiceKit/) adds a forbidden import:"
    echo "$bad"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: no new 'import SignalUI' or 'import Signal' found in any changed/added file under SignalServiceKit/."
exit 0
