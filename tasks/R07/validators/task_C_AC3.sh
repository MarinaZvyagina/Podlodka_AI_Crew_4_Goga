#!/usr/bin/env bash
# AC3: Credential storage reuses BaseTracker's existing preference plumbing
# (trackPreferences.setCredentials / trackUsername / trackPassword), not a new bespoke
# SharedPreferences/DataStore key scheme.
set -uo pipefail

REPO="${1:-.}"
TRACK_DIR="app/src/main/java/eu/kanade/tachiyomi/data/track"
TRACK_PREFS_FILE="app/src/main/java/eu/kanade/domain/track/service/TrackPreferences.kt"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

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
    echo "FAIL: no new tracker subpackage found under $TRACK_DIR to inspect for credential storage"
    exit 1
fi

FAIL_REASON=""

for name in $NEW_DIRS; do
    DIR_PATH="$REPO/$TRACK_DIR/$name"

    if ! grep -rq 'saveCredentials(' "$DIR_PATH" 2>/dev/null; then
        FAIL_REASON="$FAIL_REASON
  - $TRACK_DIR/$name never calls the inherited saveCredentials(...) from BaseTracker"
    fi

    BESPOKE="$(grep -rEn 'getSharedPreferences\(|SharedPreferences|DataStore<|preferencesDataStore\(|PreferenceManager\.getDefaultSharedPreferences' "$DIR_PATH" 2>/dev/null || true)"
    if [ -n "$BESPOKE" ]; then
        FAIL_REASON="$FAIL_REASON
  - bespoke preference storage API used directly in $TRACK_DIR/$name:
$BESPOKE"
    fi
done

# Look for any other new/changed preference-ish files that introduce bespoke credential keys.
ALL_CHANGED="$( { git -C "$REPO" diff --name-only HEAD; git -C "$REPO" ls-files --others --exclude-standard; } | sort -u)"
PREF_FILES="$(echo "$ALL_CHANGED" | grep -iE 'preference|datastore' | grep -v "^$TRACK_PREFS_FILE\$" || true)"
for f in $PREF_FILES; do
    CONTENT="$( { git -C "$REPO" diff -- "$f" 2>/dev/null; cat "$REPO/$f" 2>/dev/null; } )"
    if echo "$CONTENT" | grep -qiE 'password|username|apikey|api_key|token'; then
        FAIL_REASON="$FAIL_REASON
  - $f introduces a new credential-related preference outside TrackPreferences"
    fi
done

# TrackPreferences.kt itself: its trackUsername()/trackPassword()/setCredentials() helpers are
# already parameterized by tracker id, so a correctly-implemented new tracker needs no changes
# here. Flag it if new credential-shaped keys were added.
TP_DIFF="$(git -C "$REPO" diff -- "$TRACK_PREFS_FILE" 2>/dev/null || true)"
if [ -n "$TP_DIFF" ]; then
    ADDED="$(echo "$TP_DIFF" | grep -E '^\+' | grep -vE '^\+\+\+')"
    if echo "$ADDED" | grep -qiE 'password|username|apikey|api_key|token|credential'; then
        FAIL_REASON="$FAIL_REASON
  - $TRACK_PREFS_FILE gained new credential-related keys instead of reusing the existing per-tracker trackUsername()/trackPassword()/setCredentials() functions"
    fi
fi

if [ -n "$FAIL_REASON" ]; then
    echo "FAIL: credential storage does not cleanly reuse BaseTracker's plumbing:$FAIL_REASON"
    exit 1
fi

echo "PASS: new tracker subpackage(s) [$NEW_DIRS] rely on inherited saveCredentials()/BaseTracker preference plumbing; no bespoke SharedPreferences/DataStore/credential keys found"
exit 0
