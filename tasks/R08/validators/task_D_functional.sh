#!/usr/bin/env bash
# R08 Task D (search result caching -- architecture_trap) — FUNCTIONAL validator
#
# Injects a standalone, mock-based Robolectric test (does not touch/replace the pre-existing
# SearchRepositoryTest.kt) that drives SearchRepository.queryThreadsSync() directly and checks:
#   1. Repeating an identical query hits the cache (underlying table query invoked once, not twice).
#   2. Different queries are cached independently.
#   3. A data-change notification via DatabaseObserver (whichever registration hook the candidate
#      used) causes a repeated identical query to reflect the mutation rather than stale data --
#      the "Dangerous Success" staleness signature this task specifically targets.
#
# Because this test is scoped to SearchRepository's own public API (the class
# required_existing_abstractions fixes as the sole data-access layer for search), a candidate that
# implements caching anywhere else (e.g. the documented ContactSearchViewModel TTL-cache trap) will
# correctly show NO caching behavior here at all -- this functional check is expected to FAIL
# against that trap, not just on the staleness assertion. See fixtures/task_D_test.kt and
# FUNCTIONAL_VALIDATORS.md for the full rationale.
#
# Usage: task_D_functional.sh [repo_dir]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-.}"
FIXTURE="$SCRIPT_DIR/fixtures/task_D_test.kt"
TARGET_REL="app/src/test/java/org/thoughtcrime/securesms/search/SearchRepositoryCachingFunctionalTest.kt"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }
REPO_DIR="$(pwd)"

if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

if [ ! -x "./gradlew" ]; then
  echo "MANUAL REVIEW REQUIRED: ./gradlew not found/executable in '$REPO_DIR'."
  exit 1
fi

TARGET="$REPO_DIR/$TARGET_REL"
BACKUP=""
CLEANUP_DONE=0

cleanup() {
  [ "$CLEANUP_DONE" -eq 1 ] && return
  CLEANUP_DONE=1
  if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
    mv -f "$BACKUP" "$TARGET"
    echo "Cleanup: restored pre-existing $TARGET_REL"
  elif [ -f "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Cleanup: removed injected $TARGET_REL"
  fi
}
trap cleanup EXIT

mkdir -p "$(dirname "$TARGET")"
if [ -f "$TARGET" ]; then
  BACKUP="${TARGET}.functional-validator.bak"
  cp -f "$TARGET" "$BACKUP"
  echo "Note: candidate already had a file at $TARGET_REL; backing it up and overwriting with the canonical fixture for this check."
fi
cp -f "$FIXTURE" "$TARGET"
echo "Injected fixture -> $TARGET_REL"

echo "Running: ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests \"org.thoughtcrime.securesms.search.SearchRepositoryCachingFunctionalTest\""
if ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.search.SearchRepositoryCachingFunctionalTest" --console=plain; then
  echo "PASS: R08-TD functional — SearchRepository caches repeated identical queries, caches distinct queries independently, and correctly reflects data changes announced via DatabaseObserver (no stale results)."
  exit 0
else
  GRADLE_EXIT=$?
  echo "FAIL: R08-TD functional — test did not pass (gradle exit $GRADLE_EXIT). This can mean: (a) SearchRepository has no caching at all (e.g. the documented trap of caching in ContactSearchViewModel/UI layer instead), (b) caching exists but invalidation isn't wired to DatabaseObserver (stale-result / 'Dangerous Success' signature), or (c) a build/compile error — inspect Gradle output above to distinguish these."
  exit 1
fi
