#!/usr/bin/env bash
# R08 Task D (search result caching) — AC4
# "No new Gradle module or third-party caching dependency was introduced for what is an
# in-process, in-memory concern."
#
# Method: git diff --name-only against the pinned commit; check for any modified
# build.gradle.kts across the repo.
#
# Usage: task_D_AC4.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-80dfcfb4bd96efa5f2c1ed16f4407fea33affacd}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout."
  exit 1
fi

CHANGED_BUILD_FILES=$(git diff --name-only "$BASE_REF" -- | grep -E '(^|/)build\.gradle\.kts$')

if [ -z "$CHANGED_BUILD_FILES" ]; then
  echo "PASS: AC4 — no build.gradle.kts files appear in the diff against $BASE_REF."
  exit 0
else
  echo "FAIL: AC4 — build.gradle.kts file(s) modified, suggesting a new (likely unnecessary) dependency was added for what should be a plain in-memory cache:"
  echo "$CHANGED_BUILD_FILES"
  exit 1
fi
