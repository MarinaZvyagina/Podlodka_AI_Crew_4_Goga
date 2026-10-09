#!/usr/bin/env bash
# AC1: New integration implemented as a Tracker, registered in TrackerManager.
#
# Checks:
#  1. Exactly one new subpackage exists under
#     app/src/main/java/eu/kanade/tachiyomi/data/track/<newname>/ (i.e. not one of the
#     pre-existing tracker packages shipped in the pinned base commit).
#  2. That package contains a class declared as
#     `class X(id: Long) : BaseTracker(...)`.
#  3. TrackerManager.kt's diff shows the new class instantiated as a `val x = X(...)`
#     and added as a new entry inside the `trackers = listOf(...)` block, together with
#     a new `const val NAME = <id>L` constant in the companion object.
set -uo pipefail

REPO="${1:-.}"
TRACK_DIR="app/src/main/java/eu/kanade/tachiyomi/data/track"
MANAGER_FILE="$TRACK_DIR/TrackerManager.kt"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

if [ ! -d "$REPO/$TRACK_DIR" ]; then
    echo "FAIL: $TRACK_DIR not found in $REPO"
    exit 1
fi

# Tracker subpackages that already exist in the pinned base commit.
BASELINE_DIRS="anilist bangumi hikka kavita kitsu komga mangabaka mangaupdates model myanimelist shikimori suwayomi"

NEW_DIRS=""
for d in "$REPO/$TRACK_DIR"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if ! echo " $BASELINE_DIRS " | grep -q " $name "; then
        NEW_DIRS="$NEW_DIRS $name"
    fi
done
NEW_DIRS="$(echo "$NEW_DIRS" | xargs)"

if [ -z "$NEW_DIRS" ]; then
    echo "FAIL: no new subpackage found under $TRACK_DIR — expected a new tracker package (e.g. data/track/<newname>/) implementing the self-hosted-server integration"
    exit 1
fi

if [ "$(echo "$NEW_DIRS" | wc -w | xargs)" != "1" ]; then
    echo "FAIL: expected exactly one new tracker subpackage under $TRACK_DIR, found: $NEW_DIRS"
    exit 1
fi

NEW_DIR_NAME="$NEW_DIRS"
NEW_DIR_PATH="$TRACK_DIR/$NEW_DIR_NAME"

# Find a class declaring `class X(id: Long) : BaseTracker(...)` inside the new package.
CLASS_FILE="$(grep -rEl 'class[[:space:]]+[A-Za-z0-9_]+\(id: Long\)[[:space:]]*:[[:space:]]*BaseTracker\(' "$REPO/$NEW_DIR_PATH" 2>/dev/null | head -1)"

if [ -z "$CLASS_FILE" ]; then
    echo "FAIL: no class in $NEW_DIR_PATH declares 'class X(id: Long) : BaseTracker(...)' — new integration does not extend the required Tracker/BaseTracker abstraction"
    exit 1
fi

CLASS_NAME="$(grep -oE 'class[[:space:]]+[A-Za-z0-9_]+\(id: Long\)[[:space:]]*:[[:space:]]*BaseTracker\(' "$CLASS_FILE" | head -1 | sed -E 's/class[[:space:]]+([A-Za-z0-9_]+).*/\1/')"

if [ -z "$CLASS_NAME" ]; then
    echo "FAIL: could not determine the new tracker class name in $CLASS_FILE"
    exit 1
fi

if [ ! -f "$REPO/$MANAGER_FILE" ]; then
    echo "FAIL: $MANAGER_FILE not found"
    exit 1
fi

MANAGER_DIFF="$(git -C "$REPO" diff -- "$MANAGER_FILE")"
if [ -z "$MANAGER_DIFF" ]; then
    echo "FAIL: $MANAGER_FILE has no diff — new tracker class '$CLASS_NAME' was found but never registered in TrackerManager"
    exit 1
fi

ADDED_MANAGER_LINES="$(echo "$MANAGER_DIFF" | grep -E '^\+' | grep -vE '^\+\+\+')"

if ! echo "$ADDED_MANAGER_LINES" | grep -q "$CLASS_NAME("; then
    echo "FAIL: TrackerManager.kt diff does not instantiate the new tracker class '$CLASS_NAME(...)'"
    exit 1
fi

MANAGER_CONTENT="$(cat "$REPO/$MANAGER_FILE")"
INSTANCE_NAME="$(echo "$MANAGER_CONTENT" | grep -oE 'val[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*'"$CLASS_NAME"'\(' | head -1 | sed -E 's/val[[:space:]]+([a-zA-Z0-9_]+).*/\1/')"

if [ -z "$INSTANCE_NAME" ]; then
    echo "FAIL: no 'val x = $CLASS_NAME(...)' instance declaration found in TrackerManager.kt"
    exit 1
fi

TRACKERS_BLOCK="$(echo "$MANAGER_CONTENT" | sed -n '/val trackers = listOf(/,/^    )/p')"
if ! echo "$TRACKERS_BLOCK" | grep -qE "^[[:space:]]*$INSTANCE_NAME,?[[:space:]]*\$"; then
    echo "FAIL: 'trackers = listOf(...)' in TrackerManager.kt does not include the new instance '$INSTANCE_NAME'"
    exit 1
fi

NEW_CONST_LINES="$(echo "$MANAGER_DIFF" | grep -E '^\+' | grep -E 'const val [A-Z0-9_]+ = [0-9]+L')"
if [ -z "$NEW_CONST_LINES" ]; then
    echo "FAIL: no new 'const val NAME = <id>L' constant added to TrackerManager's companion object for the new tracker's id"
    exit 1
fi

echo "PASS: new tracker class '$CLASS_NAME' extends BaseTracker in $NEW_DIR_PATH; registered as '$INSTANCE_NAME' inside TrackerManager.trackers with a new id constant ($(echo "$NEW_CONST_LINES" | xargs))"
exit 0
