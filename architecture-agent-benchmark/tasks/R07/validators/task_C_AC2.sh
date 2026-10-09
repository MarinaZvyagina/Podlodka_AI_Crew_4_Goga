#!/usr/bin/env bash
# AC2: Chapter-read notification reuses the existing generic tracker pipeline; no new
# integration-specific network/API call is bolted onto the reader.
#
# Method: look at everything changed/added under app/src/main/java/eu/kanade/tachiyomi/ui/reader/.
# If nothing there changed at all, the new tracker is picked up automatically via
# TrackerManager.trackers/loggedInTrackers() — that's the expected, correct outcome.
# If something did change, flag it as a likely bespoke integration if it references any other
# newly-added file/class in the diff (e.g. a standalone sync manager) or adds raw network calls
# or unrelated new imports directly in reader code.
set -uo pipefail

REPO="${1:-.}"
READER_DIR="app/src/main/java/eu/kanade/tachiyomi/ui/reader"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

# All files changed (tracked, staged or unstaged) or newly added (untracked) relative to HEAD.
ALL_CHANGED="$( { git -C "$REPO" diff --name-only HEAD; git -C "$REPO" ls-files --others --exclude-standard; } | sort -u)"

READER_CHANGED="$(echo "$ALL_CHANGED" | grep "^$READER_DIR/" || true)"

if [ -z "$READER_CHANGED" ]; then
    echo "PASS: no files under $READER_DIR were added or modified — chapter-read notification is unchanged and relies on the existing generic tracker pipeline (TrackChapter / TrackerManager)"
    exit 0
fi

# Reader files did change; look for signs of a bespoke, integration-specific hook.
NEW_NON_TRACK_FILES="$(echo "$ALL_CHANGED" | grep -E '\.kt$' | grep -v "^$READER_DIR/" | grep -v '/data/track/' || true)"

SUSPECT=""
for f in $READER_CHANGED; do
    IS_UNTRACKED="$(git -C "$REPO" ls-files --others --exclude-standard -- "$f")"
    if [ -n "$IS_UNTRACKED" ]; then
        ADDED="$(cat "$REPO/$f" 2>/dev/null | sed 's/^/+/')"
    else
        ADDED="$(git -C "$REPO" diff -- "$f" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+')"
    fi

    [ -z "$ADDED" ] && continue

    for nf in $NEW_NON_TRACK_FILES; do
        CLASS="$(basename "$nf" .kt)"
        if echo "$ADDED" | grep -q "$CLASS"; then
            SUSPECT="$SUSPECT
  - $f references newly-added class '$CLASS' (from $nf) — looks like a bespoke integration wired directly into the reader"
        fi
    done

    NEW_IMPORTS="$(echo "$ADDED" | grep -E '^\+import ' | grep -viE 'eu\.kanade\.domain\.track\.interactor\.TrackChapter|eu\.kanade\.tachiyomi\.data\.track\.TrackerManager')"
    if [ -n "$NEW_IMPORTS" ]; then
        SUSPECT="$SUSPECT
  - $f gained new import(s) unrelated to the existing TrackChapter/TrackerManager plumbing:
$NEW_IMPORTS"
    fi

    if echo "$ADDED" | grep -qE '\.newCall\(|OkHttpClient|Retrofit|\.enqueue\(|HttpURLConnection'; then
        SUSPECT="$SUSPECT
  - $f contains a new direct network call"
    fi
done

if [ -n "$SUSPECT" ]; then
    echo "FAIL: reader code changed with signs of a bespoke, integration-specific hook instead of the generic tracker pipeline:$SUSPECT"
    exit 1
fi

echo "MANUAL REVIEW REQUIRED: files under $READER_DIR changed ($READER_CHANGED) but no obvious bespoke-integration marker (new class reference / new import / raw network call) was found — inspect manually to confirm this is not tracker-specific code"
exit 2
