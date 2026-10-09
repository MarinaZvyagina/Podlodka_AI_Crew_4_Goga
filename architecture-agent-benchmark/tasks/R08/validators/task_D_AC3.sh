#!/usr/bin/env bash
# R08 Task D (search result caching) — AC3
# "A staleness test distinguishes correct caching from the trap: query -> cache-hit ->
# mutate data via a path other than the cached call -> repeat identical query -> must
# reflect the mutation."
#
# Method: this is fundamentally a *runtime* check, not a static grep — per metadata:
# "Execute/author a test (see functional_check_command item 2) that performs exactly this
# sequence and asserts on the final query result." This script runs the actual Gradle unit
# test class (SearchRepositoryTest) which is expected to contain such a staleness test
# after a correct implementation adds it. It requires a working JDK/Android toolchain; if
# that is not available in the current environment, it falls back to a static heuristic
# (does the diff touch SearchRepositoryTest.kt with a mutate-then-requery assertion
# pattern?) and prints MANUAL REVIEW REQUIRED rather than faking a pass/fail on the
# runtime behavior itself.
#
# Usage: task_D_AC3.sh [repo_dir]
# Env: set SKIP_GRADLE=1 to force the static-heuristic fallback path without attempting a
#      Gradle invocation (useful in disk/CPU constrained environments).
set -uo pipefail

REPO_DIR="${1:-.}"
cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

TEST_FILE="app/src/test/java/org/thoughtcrime/securesms/search/SearchRepositoryTest.kt"

if [ ! -f "$TEST_FILE" ]; then
  echo "MANUAL REVIEW REQUIRED: $TEST_FILE does not exist. A correct implementation is expected to author a staleness test here (query -> cache hit -> external mutation -> repeat query -> assert fresh result). No test to run."
  exit 1
fi

if [ "${SKIP_GRADLE:-0}" != "1" ] && command -v ./gradlew >/dev/null 2>&1 || [ -x "./gradlew" ]; then
  if [ -z "${JAVA_HOME:-}" ]; then
    echo "NOTE: JAVA_HOME not set by caller; attempting to use whatever 'java' is on PATH. Export JAVA_HOME for reliable results."
  fi
  echo "Running: ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests \"org.thoughtcrime.securesms.search.SearchRepositoryTest\""
  if ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.search.SearchRepositoryTest" --console=plain; then
    echo "PASS: AC3 — SearchRepositoryTest (including its staleness assertions) passed."
    exit 0
  else
    GRADLE_EXIT=$?
    echo "Gradle test run failed (exit $GRADLE_EXIT)."
    echo "FAIL: AC3 — SearchRepositoryTest did not pass. This may be the intended staleness-detection failure (trap implementation) or an infra issue — inspect the Gradle output above to distinguish a real assertion failure from a build/environment error."
    exit 1
  fi
else
  echo "MANUAL REVIEW REQUIRED: Gradle wrapper not available/executable in '$REPO_DIR', or SKIP_GRADLE=1 was set. Falling back to a static heuristic."
  MUTATE_HIT=$(grep -nE 'insert|update|delete|edit' "$TEST_FILE" | head -5)
  REQUERY_HIT=$(grep -c 'queryThreadsSync\|queryMessages\|search(' "$TEST_FILE")
  echo "Mutation-related lines found in test file (sample): ${MUTATE_HIT:-none}"
  echo "Search/query call count in test file: $REQUERY_HIT"
  if [ -n "$MUTATE_HIT" ] && [ "$REQUERY_HIT" -ge 2 ]; then
    echo "Heuristic: test file plausibly contains a mutate-then-requery pattern, but actual staleness behavior was NOT executed."
  fi
  echo "No verdict can be given without running the test."
  exit 1
fi
