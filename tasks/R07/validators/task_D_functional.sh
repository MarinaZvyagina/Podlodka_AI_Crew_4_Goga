#!/usr/bin/env bash
# Functional validator for R07-TD: "Cache repeated source searches"
#
# What this checks:
#   Injects a black-box JUnit5 test (fixtures/task_D_test.kt) that exercises caching through
#   tachiyomi.data.source.SourceSearchPagingSource / SourcePopularPagingSource (the paging
#   sources tachiyomi.data.source.SourceRepositoryImpl constructs for
#   tachiyomi.domain.source.repository.SourceRepository.search()/getPopular()/getLatest(), the
#   required entry point per this task's architectural_constraints), using a mocked
#   eu.kanade.tachiyomi.source.Source with a call counter. Asserts:
#     - repeating an identical search/listing shortly after reuses the cached result (no 2nd
#       network call)
#     - a different query is not served from another entry's cache
#     - an entry past its TTL is fetched again
#     - an explicit invalidate() forces a fresh fetch
#     - paginating through a cached search still returns the correct page each time
#
#   Genericity note: this fixture targets the specific caching shape used by this benchmark's
#   reference/positive-control implementation (a dedicated tachiyomi.data.source.SourceSearchCache
#   class threaded into the paging sources' constructors - the name/shape explicitly identified
#   in this task's CONTROL_RESULTS.md verdict). A fully implementation-agnostic version (tolerant
#   of e.g. the cache being inlined directly inside SourceRepositoryImpl with a different
#   constructor shape) would require runtime reflection-based dependency construction; see
#   FUNCTIONAL_VALIDATORS.md for the reasoning and its limits.
#
#   The `data` module has no test sources/dependencies at the pinned base commit, so this script
#   also temporarily adds the same test dependencies (libs.bundles.test, kotlinx-coroutines-test,
#   junit-platform-launcher) to data/build.gradle.kts if they are not already present, and
#   restores the original file afterward.
#
# Command run:
#   ./gradlew :data:testDebugUnitTest --tests tachiyomi.data.source.SourceSearchCacheTest
#
# Exit: 0 + "PASS: ..." on success, 1 + "FAIL: ..." otherwise.
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_D_test.kt"

TEST_DEST_REL="data/src/test/java/tachiyomi/data/source/SourceSearchCacheTest.kt"
TEST_CLASS="tachiyomi.data.source.SourceSearchCacheTest"
GRADLE_TASK=":data:testDebugUnitTest"
DATA_BUILD_GRADLE_REL="data/build.gradle.kts"

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
BUILD_GRADLE="$REPO/$DATA_BUILD_GRADLE_REL"

# --- inject test file, remembering any pre-existing file so it can be restored afterward ---
TEST_BACKUP=""
if [ -f "$TEST_DEST" ]; then
    TEST_BACKUP="$(mktemp)"
    cp "$TEST_DEST" "$TEST_BACKUP"
fi
mkdir -p "$(dirname "$TEST_DEST")"
cp "$FIXTURE" "$TEST_DEST"

# --- ensure data module has test deps (base commit has none); patch only if missing ---
GRADLE_BACKUP=""
if [ -f "$BUILD_GRADLE" ] && ! grep -q "testImplementation(libs.bundles.test)" "$BUILD_GRADLE"; then
    GRADLE_BACKUP="$(mktemp)"
    cp "$BUILD_GRADLE" "$GRADLE_BACKUP"
    cat >> "$BUILD_GRADLE" <<'EOF'

dependencies {
    testImplementation(libs.bundles.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testRuntimeOnly(libs.junit.platform.launcher)
}
EOF
fi

cleanup() {
    if [ -n "$TEST_BACKUP" ]; then
        cp "$TEST_BACKUP" "$TEST_DEST"
        rm -f "$TEST_BACKUP"
    else
        rm -f "$TEST_DEST"
    fi
    if [ -n "$GRADLE_BACKUP" ]; then
        cp "$GRADLE_BACKUP" "$BUILD_GRADLE"
        rm -f "$GRADLE_BACKUP"
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
    echo "PASS: $TEST_CLASS passed via '$GRADLE_TASK --tests $TEST_CLASS' — repeated identical searches/listings are served from cache, different queries/expired/invalidated entries still hit the network, and pagination through a cached search returns the right pages."
    exit 0
else
    echo "FAIL: $TEST_CLASS did not pass via '$GRADLE_TASK --tests $TEST_CLASS'."
    echo "--- gradle output (tail) ---"
    echo "$OUT" | tail -80
    exit 1
fi
