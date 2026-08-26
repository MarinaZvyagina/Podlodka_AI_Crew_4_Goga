#!/usr/bin/env bash
# AC4: No new dependency edges from domain/data modules for this feature; trackers remain an
# app-module-only concept and tachiyomi.domain.track.model.Track stays integration-agnostic.
set -uo pipefail

REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

FAIL_REASON=""

for f in domain/build.gradle.kts data/build.gradle.kts; do
    DIFF="$(git -C "$REPO" diff -- "$f")"
    if [ -n "$DIFF" ]; then
        FAIL_REASON="$FAIL_REASON
  - $f changed (new dependency edge?):
$DIFF"
    fi
done

ALL_CHANGED="$( { git -C "$REPO" diff --name-only HEAD; git -C "$REPO" ls-files --others --exclude-standard; } | sort -u)"

DOMAIN_TRACK_NEW="$(echo "$ALL_CHANGED" | grep -E '^domain/src/main/java/tachiyomi/domain/track/' || true)"
DATA_TRACK_NEW="$(echo "$ALL_CHANGED" | grep -E '^data/src/main/java/.*track' || true)"

# The domain Track model is allowed to change, but should not gain it should not reference the
# new integration by name/id in a way that couples it to a specific tracker implementation.
DOMAIN_TRACK_MODEL="domain/src/main/java/tachiyomi/domain/track/model/Track.kt"
MODEL_DIFF="$(git -C "$REPO" diff -- "$DOMAIN_TRACK_MODEL" 2>/dev/null || true)"

if [ -n "$DOMAIN_TRACK_NEW" ]; then
    FAIL_REASON="$FAIL_REASON
  - new/changed files under domain/src/main/java/tachiyomi/domain/track/:
$DOMAIN_TRACK_NEW"
fi
if [ -n "$DATA_TRACK_NEW" ]; then
    FAIL_REASON="$FAIL_REASON
  - new/changed files under the data module's track package:
$DATA_TRACK_NEW"
fi

if [ -n "$FAIL_REASON" ]; then
    echo "FAIL: domain/data modules gained new dependencies or integration-specific logic for this feature:$FAIL_REASON"
    exit 1
fi

if [ -n "$MODEL_DIFF" ]; then
    echo "PASS (with note): domain/build.gradle.kts and data/build.gradle.kts are unchanged and no new files were added under domain/data track packages; $DOMAIN_TRACK_MODEL was however modified — verify manually that the change is integration-agnostic (does not hardcode the new tracker's name/id):"
    echo "$MODEL_DIFF" | head -60
    exit 0
fi

echo "PASS: domain/build.gradle.kts and data/build.gradle.kts unchanged; no new/changed files under domain or data track packages; tachiyomi.domain.track.model.Track untouched"
exit 0
