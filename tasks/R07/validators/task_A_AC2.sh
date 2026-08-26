#!/usr/bin/env bash
# AC2: No new Gradle module dependency edges introduced.
#
# Checks that domain/build.gradle.kts, data/build.gradle.kts, and app/build.gradle.kts
# have no diff at all (the spec requires zero changes to dependency declarations for
# this task; the simplest and most reliable check is that these files are untouched).
set -uo pipefail

REPO="${1:-.}"

FILES=(
    "domain/build.gradle.kts"
    "data/build.gradle.kts"
    "app/build.gradle.kts"
)

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

CHANGED=""
for f in "${FILES[@]}"; do
    DIFF="$(git -C "$REPO" diff -- "$f")"
    if [ -n "$DIFF" ]; then
        CHANGED="$CHANGED $f"
    fi
done

if [ -n "$CHANGED" ]; then
    echo "FAIL: unexpected diff in gradle build file(s):$CHANGED — no build.gradle.kts changes are expected for this task"
    exit 1
fi

echo "PASS: no diff in domain/build.gradle.kts, data/build.gradle.kts, or app/build.gradle.kts"
exit 0
