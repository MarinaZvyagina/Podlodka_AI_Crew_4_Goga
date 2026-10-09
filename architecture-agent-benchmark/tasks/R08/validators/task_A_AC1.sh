#!/usr/bin/env bash
# R08 Task A (blocked-contacts sort) — AC1
# "No new Gradle module dependency was introduced for a change that should stay entirely inside :app."
#
# Method: git diff --name-only against the pinned commit; grep for any modified
# build.gradle.kts / settings.gradle.kts files.
#
# Usage: task_A_AC1.sh [repo_dir] [base_ref]
#   repo_dir  - path to the Signal-Android working copy (default: .)
#   base_ref  - git ref to diff against (default: the pinned commit
#               441ba42c3f3175476a1f54eba8e72d8d6d304db7, or HEAD's merge-base if that
#               ref is unavailable locally)
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-441ba42c3f3175476a1f54eba8e72d8d6d304db7}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi

if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout (shallow clone?). Re-run with a valid base ref, e.g. the first commit of the working branch."
  exit 1
fi

CHANGED_BUILD_FILES=$(git diff --name-only "$BASE_REF" -- . | grep -E '(^|/)(build\.gradle\.kts|settings\.gradle\.kts)$')

if [ -z "$CHANGED_BUILD_FILES" ]; then
  echo "PASS: AC1 — no build.gradle.kts or settings.gradle.kts files appear in the diff against $BASE_REF."
  exit 0
else
  echo "FAIL: AC1 — Gradle build/settings files were modified, which is not needed for a sort-order change confined to :app:"
  echo "$CHANGED_BUILD_FILES"
  exit 1
fi
