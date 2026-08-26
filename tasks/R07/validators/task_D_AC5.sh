#!/usr/bin/env bash
# AC5: Cache invalidation logic is not duplicated ad hoc in multiple UI entry points.
#
# Structural approximation: scan every file touched by the diff for "staleness/expiry/clear"
# logic (time-comparison against a stored timestamp, an isExpired()-style check, or a
# cache.clear()/map.clear() call). Collect the distinct set of files containing such logic.
#   - 0 files with this logic -> MANUAL REVIEW REQUIRED (can't tell how expiry/refresh works at all).
#   - exactly 1 file, and it lives under data/ -> PASS (single source of truth, in the data layer).
#   - exactly 1 file, but it lives under app/.../ui/ or app/.../presentation/ (a
#     ViewModel/Composable/Screen) -> FAIL (ad hoc, UI-local invalidation, not a shared data-layer
#     concern).
#   - more than 1 file contains staleness/expiry/clear logic -> FAIL (duplicated invalidation
#     logic across multiple entry points).
set -uo pipefail

REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

CHANGED_FILES="$(git -C "$REPO" diff --name-only)"
UNTRACKED_FILES="$(git -C "$REPO" status --porcelain | grep -E '^\?\?' | awk '{print $2}')"
ALL_FILES="$(printf '%s\n%s\n' "$CHANGED_FILES" "$UNTRACKED_FILES" | sed '/^$/d' | sort -u)"

if [ -z "$ALL_FILES" ]; then
    echo "FAIL: no changes found in working tree '$REPO'"
    exit 1
fi

STALENESS_PATTERN='isExpired|isStale|currentTimeMillis|nowProvider|System\.now|Clock\.System|\.clear\(\)|invalidate\(|ttlMillis|TTL_MILLIS|expiresAt|cachedAt|expiryTime'

MATCHING_FILES=()

for f in $ALL_FILES; do
    case "$f" in
        *.kt) ;;
        *) continue ;;
    esac

    # Tests only exercise/call invalidation logic, they don't implement it — don't count them as
    # a separate implementation site.
    case "$f" in
        */test/*|*Test.kt) continue ;;
    esac

    if git -C "$REPO" status --porcelain -- "$f" | grep -q '^??'; then
        CONTENT="$(cat "$REPO/$f" 2>/dev/null)"
    else
        CONTENT="$(git -C "$REPO" diff -- "$f" | grep -E '^\+' | grep -Ev '^\+\+\+')"
    fi

    if echo "$CONTENT" | grep -qE "$STALENESS_PATTERN"; then
        MATCHING_FILES+=("$f")
    fi
done

COUNT="${#MATCHING_FILES[@]}"

if [ "$COUNT" -eq 0 ]; then
    echo "MANUAL REVIEW REQUIRED: no staleness/expiry/clear-style logic detected anywhere in the diff — cannot confirm a single source of truth for invalidation"
    exit 1
fi

if [ "$COUNT" -gt 1 ]; then
    echo "FAIL: staleness/expiry/clear logic found duplicated across ${COUNT} files: ${MATCHING_FILES[*]} — expected a single data-layer source of truth"
    exit 1
fi

ONLY_FILE="${MATCHING_FILES[0]}"
case "$ONLY_FILE" in
    data/*)
        echo "PASS: staleness/expiry/invalidation logic found in exactly one place, in the data layer: $ONLY_FILE"
        exit 0
        ;;
    app/src/main/java/eu/kanade/tachiyomi/ui/*|app/src/main/java/eu/kanade/presentation/*|*ViewModel.kt|*Screen.kt)
        echo "FAIL: staleness/expiry/clear logic found only in a UI-layer file ($ONLY_FILE) — ad hoc invalidation local to one screen/ViewModel, not a shared data-layer concern"
        exit 1
        ;;
    *)
        echo "MANUAL REVIEW REQUIRED: staleness/expiry logic found in a single file ($ONLY_FILE) that is neither clearly data/ nor clearly a UI-layer file"
        exit 1
        ;;
esac
