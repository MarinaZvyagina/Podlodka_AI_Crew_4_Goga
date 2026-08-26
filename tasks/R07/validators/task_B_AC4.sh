#!/usr/bin/env bash
# AC4: No new dependency edge from domain to data.
#
# Checks:
#  1. domain/build.gradle.kts is unchanged (diff against HEAD, the pinned base commit, is empty).
#  2. No file under domain/src/main/java imports tachiyomi.data.* directly.
set -uo pipefail

REPO="${1:-.}"

BUILD_FILE="domain/build.gradle.kts"
DOMAIN_MAIN="domain/src/main/java"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

BUILD_DIFF="$(git -C "$REPO" diff -- "$BUILD_FILE")"
if [ -n "$BUILD_DIFF" ]; then
    echo "FAIL: $BUILD_FILE was modified — domain must not gain a new dependency (e.g. on projects.data):"
    echo "$BUILD_DIFF"
    exit 1
fi

IMPORT_HITS="$(grep -rln 'import tachiyomi\.data' "$REPO/$DOMAIN_MAIN" 2>/dev/null || true)"
if [ -n "$IMPORT_HITS" ]; then
    echo "FAIL: found direct imports of tachiyomi.data.* inside $DOMAIN_MAIN: $IMPORT_HITS"
    exit 1
fi

echo "PASS: $BUILD_FILE is unchanged and no tachiyomi.data.* imports were found under $DOMAIN_MAIN"
exit 0
