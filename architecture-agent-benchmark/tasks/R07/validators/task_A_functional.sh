#!/usr/bin/env bash
# Functional validator for R07-TA: "Reject invalid custom extension repository URLs early"
#
# What this checks:
#   Injects a black-box JUnit5 test (fixtures/task_A_test.kt) against the real public entry
#   point mihon.domain.extension.interactor.AddExtensionStore.invoke(indexUrl: String):
#   Result<Unit>, using a plain mockk() ExtensionStoreRepository (no internal helpers of any
#   specific candidate implementation are referenced). Asserts:
#     - "", "not a url", "javascript:alert(1)", "ftp://example.com/repo" all yield
#       Result.isFailure without ever reaching repository.insert(...)
#     - a valid "https://example.com/repo.json" yields Result.isSuccess and reaches
#       repository.insert(...) exactly once
#
# Command run:
#   ./gradlew :domain:testDebugUnitTest --tests mihon.domain.extension.interactor.AddExtensionStoreTest
#
# Exit: 0 + "PASS: ..." on success, 1 + "FAIL: ..." otherwise.
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_A_test.kt"

TEST_DEST_REL="domain/src/test/java/mihon/domain/extension/interactor/AddExtensionStoreTest.kt"
TEST_CLASS="mihon.domain.extension.interactor.AddExtensionStoreTest"
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

# --- inject fixture, remembering any pre-existing file so it can be restored afterward ---
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

# --- run scoped gradle test ---
pushd "$REPO" >/dev/null

OUT="$(./gradlew "$GRADLE_TASK" --tests "$TEST_CLASS" --offline 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ] && echo "$OUT" | grep -qiE "could not resolve|no cached version|Could not GET|SocketException|UnknownHostException"; then
    # Offline cache miss (e.g. fresh checkout) - retry with network access.
    OUT="$(./gradlew "$GRADLE_TASK" --tests "$TEST_CLASS" 2>&1)"
    STATUS=$?
fi

popd >/dev/null

if [ $STATUS -eq 0 ] && echo "$OUT" | grep -q "BUILD SUCCESSFUL"; then
    echo "PASS: $TEST_CLASS passed via '$GRADLE_TASK --tests $TEST_CLASS' — invalid repository URLs are rejected before repository.insert(), valid ones still reach it."
    exit 0
else
    echo "FAIL: $TEST_CLASS did not pass via '$GRADLE_TASK --tests $TEST_CLASS'."
    echo "--- gradle output (tail) ---"
    echo "$OUT" | tail -80
    exit 1
fi
