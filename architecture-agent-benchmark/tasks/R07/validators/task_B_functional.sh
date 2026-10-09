#!/usr/bin/env bash
# Functional validator for R07-TB: "Let users temporarily hide a series from the Updates feed"
#
# What this checks:
#   Injects a black-box JUnit5 test (fixtures/task_B_test.kt) against the real public entry
#   point mandated by this task's required_existing_abstractions:
#   tachiyomi.domain.updates.interactor.GetUpdates backed by a fake implementation of
#   tachiyomi.domain.updates.repository.UpdatesRepository (an interface, not an internal helper
#   of any specific candidate). Asserts:
#     - a manga snoozed until a future time is excluded from GetUpdates.await()/subscribe()
#     - a manga whose snooze has passed is included again
#     - a manga that was never snoozed is unaffected
#     - snoozing one manga does not affect another manga's visibility
#
# Command run:
#   ./gradlew :domain:testDebugUnitTest --tests tachiyomi.domain.updates.interactor.GetUpdatesSnoozeTest
#
# Exit: 0 + "PASS: ..." on success, 1 + "FAIL: ..." otherwise.
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_B_test.kt"

TEST_DEST_REL="domain/src/test/java/tachiyomi/domain/updates/interactor/GetUpdatesSnoozeTest.kt"
TEST_CLASS="tachiyomi.domain.updates.interactor.GetUpdatesSnoozeTest"
GRADLE_TASK=":domain:testDebugUnitTest"

# --- toolchain setup ---
if [ -z "${JAVA_HOME:-}" ] || [ ! -d "${JAVA_HOME:-/nonexistent}" ]; then
    for candidate in \
        /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
        "$(brew --prefix openjdk@21 2>/dev/null)/libexec/openjdk.jdk/Contents/Home" \
        /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home; do
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            JAVA_HOME="$candidate"
            break
        fi
    done
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

if [ ! -f "$REPO/local.properties" ]; then
    echo "sdk.dir=$ANDROID_SDK_ROOT" > "$REPO/local.properties"
fi

if [ ! -f "$FIXTURE" ]; then
    echo "FAIL: fixture not found at $FIXTURE"
    exit 1
fi

TEST_DEST="$REPO/$TEST_DEST_REL"

BACKUP=""
if [ -f "$TEST_DEST" ]; then
    BACKUP="$(mktemp)"
    cp "$TEST_DEST" "$BACKUP"
fi
mkdir -p "$(dirname "$TEST_DEST")"
cp "$FIXTURE" "$TEST_DEST"

cleanup() {
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" "$TEST_DEST"
        rm -f "$BACKUP"
    else
        rm -f "$TEST_DEST"
    fi
}
trap cleanup EXIT

pushd "$REPO" >/dev/null

OUT="$(./gradlew "$GRADLE_TASK" --tests "$TEST_CLASS" --offline 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ] && echo "$OUT" | grep -qiE "could not resolve|no cached version|Could not GET|SocketException|UnknownHostException"; then
    OUT="$(./gradlew "$GRADLE_TASK" --tests "$TEST_CLASS" 2>&1)"
    STATUS=$?
fi

popd >/dev/null

if [ $STATUS -eq 0 ] && echo "$OUT" | grep -q "BUILD SUCCESSFUL"; then
    echo "PASS: $TEST_CLASS passed via '$GRADLE_TASK --tests $TEST_CLASS' — snoozed manga are excluded from updates, un-snoozed/expired ones are included, and snoozing one manga doesn't affect another."
    exit 0
else
    echo "FAIL: $TEST_CLASS did not pass via '$GRADLE_TASK --tests $TEST_CLASS'."
    echo "--- gradle output (tail) ---"
    echo "$OUT" | tail -80
    exit 1
fi
