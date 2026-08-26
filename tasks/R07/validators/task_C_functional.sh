#!/usr/bin/env bash
# Functional validator for R07-TC: "Sync reading progress with a self-hosted library server"
#
# What this checks:
#   Per this task's own functional_check_command, full end-to-end verification (log into the
#   new integration, mark a chapter read, observe a network call from the new tracker's
#   update()/setRemoteLastChapterRead() path) is explicitly a *manual* step in this benchmark
#   (repo has no network-mocking test harness for trackers). The automatable portion is:
#     (a) the app module compiles with the new tracker wired in, and
#     (b) the new integration is genuinely reachable the same way every existing tracker is -
#         through eu.kanade.tachiyomi.data.track.TrackerManager - since that's what lets the
#         app's *existing*, generic, already-tested chapter-read-sync call sites
#         (BaseTracker.setRemoteLastChapterRead/update(), invoked over
#         TrackerManager.trackers/loggedInTrackers()) pick the new tracker up automatically
#         with no reader/chapter-list code changes.
#
#   This is checked with a black-box, reflection-only JUnit5 test (fixtures/task_C_test.kt) that
#   only inspects eu.kanade.tachiyomi.data.track.TrackerManager's compiled shape (its public,
#   zero-arg property getters) - never a specific new tracker class/package by name, and never
#   instantiating TrackerManager/any tracker (one baseline tracker's init{} block requires a
#   fully initialized Android app graph not available under a plain JVM unit test) - asserting a
#   new tracker property beyond the baseline 11 exists, extends BaseTracker, and that the
#   `trackers` registry itself is still a plain list.
#
# Command run:
#   ./gradlew :app:testDebugUnitTest --tests eu.kanade.tachiyomi.data.track.TrackerRegistrationTest
#
# Exit: 0 + "PASS: ..." on success, 1 + "FAIL: ..." otherwise.
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_C_test.kt"

TEST_DEST_REL="app/src/test/java/eu/kanade/tachiyomi/data/track/TrackerRegistrationTest.kt"
TEST_CLASS="eu.kanade.tachiyomi.data.track.TrackerRegistrationTest"
GRADLE_TASK=":app:testDebugUnitTest"

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
    echo "PASS: $TEST_CLASS passed via '$GRADLE_TASK --tests $TEST_CLASS' — a new tracker beyond the baseline 11 is registered in TrackerManager and reachable through its generic get()/getAll()/trackers API."
    echo "NOTE: full network-level verification (login + chapter-read -> outbound request from the new tracker's update() path) is documented as a manual step in this task's functional_check_command and is not automated here (no OkHttp-interceptor/mock-server harness exists for trackers in this repo)."
    exit 0
else
    echo "FAIL: $TEST_CLASS did not pass via '$GRADLE_TASK --tests $TEST_CLASS'."
    echo "--- gradle output (tail) ---"
    echo "$OUT" | tail -80
    exit 1
fi
