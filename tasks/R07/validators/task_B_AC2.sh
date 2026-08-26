#!/usr/bin/env bash
# AC2: Updates-feed snooze exclusion happens at the query layer, not as a presentation-side filter.
#
# Checks:
#  1. data/src/main/sqldelight/tachiyomi/view/updatesView.sq gained a snooze-related change
#     (new column in the view and/or a WHERE-clause condition).
#  2. domain/src/main/java/tachiyomi/domain/updates/repository/UpdatesRepository.kt gained a
#     new parameter (e.g. a currentTime/snooze threshold) threaded through its query methods.
#  3. The app module's updates UI/ViewModel code did NOT gain a client-side `.filter {`/
#     `.filterNot {` that operates on a snooze field — that would mean filtering was bolted on
#     in the presentation layer instead of the SQL query layer.
set -uo pipefail

REPO="${1:-.}"

UPDATES_VIEW="data/src/main/sqldelight/tachiyomi/view/updatesView.sq"
UPDATES_REPO="domain/src/main/java/tachiyomi/domain/updates/repository/UpdatesRepository.kt"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

VIEW_DIFF_ADDED="$(git -C "$REPO" diff -- "$UPDATES_VIEW" | grep -E '^\+' | grep -vE '^\+\+\+')"
REPO_DIFF_ADDED="$(git -C "$REPO" diff -- "$UPDATES_REPO" | grep -E '^\+' | grep -vE '^\+\+\+')"

if [ -z "$VIEW_DIFF_ADDED" ] || ! echo "$VIEW_DIFF_ADDED" | grep -qiE 'snooz'; then
    echo "FAIL: $UPDATES_VIEW has no snooze-related change — expected the view/queries to gain a WHERE-clause condition (or column) referencing the new snooze field"
    exit 1
fi

if [ -z "$REPO_DIFF_ADDED" ] || ! echo "$REPO_DIFF_ADDED" | grep -qiE 'snooz|currentTime'; then
    echo "FAIL: $UPDATES_REPO has no new parameter threading a snooze/current-time value through to the query layer"
    exit 1
fi

# Guard: presentation-side post-filtering on a snooze field is the documented trap.
TRAP_HITS=""
UPDATES_UI_FILES="$(git -C "$REPO" diff --name-only -- \
    app/src/main/java/eu/kanade/presentation/updates \
    app/src/main/java/eu/kanade/tachiyomi/ui/updates 2>/dev/null || true)"

for f in $UPDATES_UI_FILES; do
    ADDED="$(git -C "$REPO" diff -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+')"
    if echo "$ADDED" | grep -qiE '\.filter(Not)?[[:space:]]*\{' && echo "$ADDED" | grep -qiE 'snooz'; then
        TRAP_HITS="$TRAP_HITS $f"
    fi
done

if [ -n "$TRAP_HITS" ]; then
    echo "FAIL: found presentation-layer .filter{}/.filterNot{} logic referencing snoozing in:$TRAP_HITS — exclusion must happen in the SQL query layer (updatesView.sq / UpdatesRepository), not the ViewModel/Composable"
    exit 1
fi

echo "PASS: updatesView.sq and UpdatesRepository.kt gained a snooze-related query-layer change, and no presentation-side snooze filtering was found in the updates UI/ViewModel"
exit 0
