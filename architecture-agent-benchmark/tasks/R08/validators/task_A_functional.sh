#!/usr/bin/env bash
# R08 Task A (blocked-contacts alphabetical sort) — FUNCTIONAL validator
#
# Black-box, implementation-agnostic functional check. Injects a standalone Robolectric
# test (fixtures/task_A_test.kt) that drives BlockedUsersRepository.getBlocked() — the
# task's guaranteed "sole data-access point for this screen" — and asserts the returned
# list is sorted alphabetically by display name, case-insensitively, regardless of
# insertion order. Does not assume which allowed layer (BlockedUsersRepository itself, or
# the underlying RecipientTable.getBlocked() query it calls) implements the sort.
#
# By design this test does NOT pass a candidate that only sorts in the UI layer
# (Fragment/Adapter) — see notes_for_positive_negative_control / CONTROL_RESULTS.md, which
# documents that this is the intended, stricter behavior for this task's functional_check.
#
# Usage: task_A_functional.sh [repo_dir]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-.}"
FIXTURE="$SCRIPT_DIR/fixtures/task_A_test.kt"
TARGET_REL="app/src/test/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepositoryTest.kt"

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

echo "Running: ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests \"org.thoughtcrime.securesms.blocked.BlockedUsersRepositoryTest\""
if ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.blocked.BlockedUsersRepositoryTest" --console=plain; then
  echo "PASS: R08-TA functional — BlockedUsersRepository.getBlocked() returns blocked recipients sorted alphabetically (case-insensitive), regardless of insertion order."
  exit 0
else
  GRADLE_EXIT=$?
  echo "FAIL: R08-TA functional — BlockedUsersRepositoryTest did not pass (gradle exit $GRADLE_EXIT). Either the data-access layer (BlockedUsersRepository/RecipientTable) does not sort the blocked list, or the build failed; inspect Gradle output above."
  exit 1
fi
