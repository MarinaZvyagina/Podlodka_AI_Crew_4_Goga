#!/usr/bin/env bash
# AC3: Cache is positioned to benefit more than one consumer of source search (not hardwired to
# one screen), e.g. it would transparently also help
# mihon.feature.migration.list.search.SmartSourceSearchEngine.kt, which calls
# source.getSearchManga(...) directly, independent of BrowseSourceViewModel.
#
# Structural, automatable approximation of "reachability": find every file touched by the diff
# whose *added* lines contain cache-ish vocabulary (cache/ttl/expire/stale/invalidate), then:
#   - if such files exist ONLY within BrowseSourceViewModel.kt (or another
#     browse-screen/Composable-scoped file under app/.../ui/browse/... or
#     app/.../presentation/...) -> FAIL (cache is trapped behind one screen's code path).
#   - if at least one such file lives under data/ (ideally data/src/main/java/tachiyomi/data/source/)
#     -> PASS (positioned at/below SourceRepositoryImpl, reachable by any consumer of source
#     search/listing, including SmartSourceSearchEngine if it were wired to use it).
#   - otherwise -> MANUAL REVIEW REQUIRED.
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

CACHE_FILES_DATA=()
CACHE_FILES_VM_SCOPED=()
CACHE_FILES_OTHER=()

for f in $ALL_FILES; do
    case "$f" in
        *.kt) ;;
        *) continue ;;
    esac

    if [ -f "$REPO/$f" ] && git -C "$REPO" status --porcelain -- "$f" | grep -q '^??'; then
        # Brand-new file: inspect its whole content.
        CONTENT="$(cat "$REPO/$f")"
    else
        # Existing file: inspect only the added lines so unrelated pre-existing text doesn't count.
        CONTENT="$(git -C "$REPO" diff -- "$f" | grep -E '^\+' | grep -Ev '^\+\+\+')"
    fi

    if ! echo "$CONTENT" | grep -qiE 'cache|ttl|expir|stale|invalidate'; then
        continue
    fi

    case "$f" in
        app/src/main/java/eu/kanade/tachiyomi/ui/browse/source/browse/BrowseSourceViewModel.kt)
            CACHE_FILES_VM_SCOPED+=("$f")
            ;;
        data/src/main/java/tachiyomi/data/source/*|data/src/main/java/*)
            CACHE_FILES_DATA+=("$f")
            ;;
        *)
            CACHE_FILES_OTHER+=("$f")
            ;;
    esac
done

if [ "${#CACHE_FILES_DATA[@]}" -gt 0 ]; then
    echo "PASS: cache-related code found under data/ (${CACHE_FILES_DATA[*]}) — reachable by any consumer of SourceRepository/GetRemoteManga, not just BrowseSourceViewModel"
    exit 0
fi

if [ "${#CACHE_FILES_VM_SCOPED[@]}" -gt 0 ] && [ "${#CACHE_FILES_OTHER[@]}" -eq 0 ]; then
    echo "FAIL: cache-related code found only in BrowseSourceViewModel.kt (${CACHE_FILES_VM_SCOPED[*]}) — trapped behind one screen's code path, unreachable by other consumers such as SmartSourceSearchEngine.kt"
    exit 1
fi

if [ "${#CACHE_FILES_VM_SCOPED[@]}" -gt 0 ]; then
    echo "FAIL: cache-related code found in BrowseSourceViewModel.kt and only non-data-layer files (${CACHE_FILES_OTHER[*]}) — no evidence it is reachable below SourceRepositoryImpl"
    exit 1
fi

echo "MANUAL REVIEW REQUIRED: could not automatically classify where cache logic lives (files touched: $ALL_FILES)"
exit 1
