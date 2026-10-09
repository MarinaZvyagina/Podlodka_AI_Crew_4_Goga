#!/usr/bin/env bash
# R08 Task A (blocked-contacts sort) — AC4
# "ViewModel continues to go through BlockedUsersRepository rather than reaching around
# it into the database directly."
#
# Method: grep -n 'SignalDatabase' BlockedUsersViewModel.java — expect no matches.
#
# Usage: task_A_AC4.sh [repo_dir]
set -uo pipefail

REPO_DIR="${1:-.}"
cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

VM="app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersViewModel.java"

if [ ! -f "$VM" ]; then
  echo "MANUAL REVIEW REQUIRED: expected file not found: $VM (was it renamed/moved?)"
  exit 1
fi

MATCHES=$(grep -n 'SignalDatabase' "$VM")

if [ -z "$MATCHES" ]; then
  echo "PASS: AC4 — BlockedUsersViewModel does not reference SignalDatabase directly."
  exit 0
else
  echo "FAIL: AC4 — ViewModel bypasses BlockedUsersRepository and reaches the database directly:"
  echo "$MATCHES"
  exit 1
fi
