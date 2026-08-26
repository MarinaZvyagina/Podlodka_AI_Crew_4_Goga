#!/usr/bin/env bash
# R08 Task B (per-attachment full-quality override in media-send batch) — FUNCTIONAL validator
#
# Injects a reflection-based Robolectric test that:
#   - discovers whichever new method the candidate added to the fixed
#     feature/media-send PreUploadRepository interface (name-agnostic: it is whatever
#     method isn't one of the six that already existed at the pinned commit),
#   - invokes it (with synthesized args matched by parameter type) on the fixed app-side
#     singleton MediaSendV3PreUploadRepository against a real Robolectric-backed SQLite
#     SignalDatabase,
#   - asserts the persisted TransformProperties.skipTransform flag is set on the marked
#     attachment only, and survives a fresh DB re-read (JVM proxy for process-death survival;
#     no emulator/instrumentation available in this environment, matching metadata_B.yaml's
#     own functional_check_command note).
#
# See fixtures/task_B_test.kt for full rationale and implementation-agnosticism notes.
#
# Usage: task_B_functional.sh [repo_dir]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-.}"
FIXTURE="$SCRIPT_DIR/fixtures/task_B_test.kt"
TARGET_REL="app/src/test/java/org/thoughtcrime/securesms/mediasend/v3/MediaSendV3PreUploadRepositoryFullQualityTest.kt"

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

echo "Running: ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests \"org.thoughtcrime.securesms.mediasend.v3.MediaSendV3PreUploadRepositoryFullQualityTest\""
if ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.mediasend.v3.MediaSendV3PreUploadRepositoryFullQualityTest" --console=plain; then
  echo "PASS: R08-TB functional — the per-attachment full-quality override is routed through PreUploadRepository/MediaSendV3PreUploadRepository, persists transformProperties.skipTransform on the marked attachment only, and survives a fresh DB re-read."
  exit 0
else
  GRADLE_EXIT=$?
  echo "FAIL: R08-TB functional — test did not pass (gradle exit $GRADLE_EXIT). This can mean: (a) no new capability was added to PreUploadRepository at all (e.g. a bespoke in-memory/UI-only mechanism, the documented trap shape), (b) the override isn't persisted via TransformProperties.skipTransform, or (c) a build/compile error — inspect Gradle output above to distinguish these."
  exit 1
fi
