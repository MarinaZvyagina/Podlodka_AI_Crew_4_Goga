#!/usr/bin/env bash
# R08 Task A (blocked-contacts sort) — AC3
# "UI layer (Fragment/Adapter) does not gain direct database access."
#
# Method: grep -n 'SignalDatabase|rawQuery|Cursor' in BlockedUsersFragment.java and
# BlockedUsersAdapter.java. No matches expected either before or after a correct change;
# this validator checks the *current* state of the working tree (post-change), which is
# what matters for the architecture check.
#
# Usage: task_A_AC3.sh [repo_dir]
set -uo pipefail

REPO_DIR="${1:-.}"
cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

FRAGMENT="app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersFragment.java"
ADAPTER="app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersAdapter.java"

MISSING=0
for f in "$FRAGMENT" "$ADAPTER"; do
  if [ ! -f "$f" ]; then
    echo "MANUAL REVIEW REQUIRED: expected file not found: $f (was it renamed/moved?)"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

MATCHES=$(grep -n 'SignalDatabase\|rawQuery\|Cursor' "$FRAGMENT" "$ADAPTER")

if [ -z "$MATCHES" ]; then
  echo "PASS: AC3 — no direct DB access (SignalDatabase/rawQuery/Cursor) found in Fragment or Adapter."
  exit 0
else
  echo "FAIL: AC3 — UI layer directly references the database, bypassing BlockedUsersRepository:"
  echo "$MATCHES"
  exit 1
fi
