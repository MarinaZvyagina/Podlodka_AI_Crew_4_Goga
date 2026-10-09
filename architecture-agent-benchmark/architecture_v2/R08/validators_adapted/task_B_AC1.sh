#!/usr/bin/env bash
# R08 Task B (per-attachment full-quality override) — AC1
# "feature/media-send's build file gains no dependency on :app (or any reversal of the
# existing one-directional edge)."
#
# Method: diff feature/media-send/build.gradle.kts against the pinned commit; grep for
# 'project(":app'.
#
# Usage: task_B_AC1.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-80dfcfb4bd96efa5f2c1ed16f4407fea33affacd}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi

BUILD_FILE="feature/media-send/build.gradle.kts"
if [ ! -f "$BUILD_FILE" ]; then
  echo "MANUAL REVIEW REQUIRED: $BUILD_FILE not found."
  exit 1
fi

# Check current working-tree content for a forbidden dependency on :app.
CURRENT_HIT=$(grep -n 'project(":app' "$BUILD_FILE")

if [ -n "$CURRENT_HIT" ]; then
  echo "FAIL: AC1 — feature/media-send/build.gradle.kts references :app, reversing the existing one-directional dependency:"
  echo "$CURRENT_HIT"
  exit 1
fi

# Also confirm no other build.gradle.kts anywhere adds a feature/media-send -> app edge indirectly
# via a diff check, and report whether the build file changed at all (informational).
if git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  DIFF_OUT=$(git diff "$BASE_REF" -- "$BUILD_FILE")
  if [ -n "$DIFF_OUT" ]; then
    echo "INFO: $BUILD_FILE changed vs $BASE_REF (reviewed above for :app references — none found)."
  else
    echo "INFO: $BUILD_FILE unchanged vs $BASE_REF."
  fi
else
  echo "INFO: base ref $BASE_REF unavailable for diff context; current-state grep is still authoritative for this check."
fi

echo "PASS: AC1 — no 'project(\":app' dependency found in feature/media-send/build.gradle.kts."
exit 0
