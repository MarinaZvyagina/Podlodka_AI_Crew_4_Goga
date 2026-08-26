#!/usr/bin/env bash
# Task D / AC3: No platform-type branching introduced in shared code.
#
# Method: grep -n "getType()\s*===\|instanceof ExpressAdapter\|instanceof
# FastifyAdapter" for newly ADDED lines (diff '+' lines) in packages/core and
# packages/common. Expected: no matches. We also scan any other changed
# application-level file for good measure (a violation there would still be
# an architectural problem even though the spec's method text scopes this to
# core/common).
#
# Usage: task_D_AC3.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

PATTERN='getType\(\)[[:space:]]*===|instanceof[[:space:]]+ExpressAdapter|instanceof[[:space:]]+FastifyAdapter'

FOUND=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac

  if [ -f "$f" ] && git diff --no-color HEAD -- "$f" >/tmp/task_D_AC3_diff.$$ 2>/dev/null && [ -s /tmp/task_D_AC3_diff.$$ ]; then
    ADDED=$(grep -E '^\+[^+]' /tmp/task_D_AC3_diff.$$ | sed 's/^\+//' | grep -nE "$PATTERN" || true)
  else
    ADDED=""
  fi
  rm -f /tmp/task_D_AC3_diff.$$

  # For brand-new (untracked) files, every line is "added".
  if [ -f "$f" ] && git status --porcelain -- "$f" | grep -q '^??'; then
    ADDED=$(grep -nE "$PATTERN" "$f" || true)
  fi

  if [ -n "$ADDED" ]; then
    FOUND="${FOUND}${f}:"$'\n'"${ADDED}"$'\n'
  fi
done <<< "$CHANGED"

if [ -n "$FOUND" ]; then
  echo "FAIL: platform-type branching found in changed code:"
  echo "$FOUND" | sed 's/^/  /'
  exit 1
fi

echo "PASS: no getType() === / instanceof ExpressAdapter / instanceof FastifyAdapter branching found in changed lines"
exit 0
