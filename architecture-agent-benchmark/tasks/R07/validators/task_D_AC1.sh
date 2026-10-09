#!/usr/bin/env bash
# AC1: Cache storage lives in the data layer (SourceRepositoryImpl / SourcePagingSource / a
# dedicated cache class), not in the ViewModel.
#
# Checks:
#  1. BrowseSourceViewModel.kt must NOT gain a new field that looks like a cache/map used to
#     memoize search/listing results (e.g. `mutableMapOf<...>` / `HashMap<...>` / a `...Cache`
#     typed field) in its added lines.
#  2. Some new cache-related code (new file or new class/logic) must appear under
#     data/src/main/java/tachiyomi/data/source/ (or be added to SourceRepositoryImpl.kt /
#     SourcePagingSource.kt in that directory).
set -uo pipefail

REPO="${1:-.}"

VM_PATH="app/src/main/java/eu/kanade/tachiyomi/ui/browse/source/browse/BrowseSourceViewModel.kt"
DATA_SOURCE_DIR="data/src/main/java/tachiyomi/data/source"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

# --- Check 1: no new cache/map field added to BrowseSourceViewModel.kt ---
VM_ADDED="$(git -C "$REPO" diff -- "$VM_PATH" | grep -E '^\+' | grep -Ev '^\+\+\+')"

if echo "$VM_ADDED" | grep -qiE \
    'mutableMapOf|hashMapOf|HashMap<|ConcurrentHashMap|MutableMap<|LinkedHashMap|(private|val|var)[^=]*Cache[^a-zA-Z][^=]*='; then
    echo "FAIL: $VM_PATH gained a new Map/Cache-typed field or map-literal — caching appears to live in the ViewModel"
    exit 1
fi

if echo "$VM_ADDED" | grep -qiE '\bsearchCache\b|\bcacheMap\b|\bresultsCache\b'; then
    echo "FAIL: $VM_PATH references a cache-like identifier in its added lines — caching appears entangled with the ViewModel"
    exit 1
fi

# --- Check 2: new cache-related code appears under data/src/main/java/tachiyomi/data/source/ ---
CHANGED_DATA_SOURCE_FILES="$(git -C "$REPO" diff --name-only -- "$DATA_SOURCE_DIR" 2>/dev/null)"
NEW_DATA_SOURCE_FILES="$(git -C "$REPO" status --porcelain -- "$DATA_SOURCE_DIR" 2>/dev/null | grep -E '^\?\?' | awk '{print $2}')"

if [ -z "$CHANGED_DATA_SOURCE_FILES" ] && [ -z "$NEW_DATA_SOURCE_FILES" ]; then
    echo "FAIL: no changes and no new files under $DATA_SOURCE_DIR — no evidence of a data-layer cache"
    exit 1
fi

# Look for cache-ish vocabulary among either the diff hunks of changed files or the content of
# brand-new files under the data/source directory.
CACHE_EVIDENCE=""

if [ -n "$CHANGED_DATA_SOURCE_FILES" ]; then
    DIFF_ADDED="$(git -C "$REPO" diff -- "$DATA_SOURCE_DIR" | grep -E '^\+' | grep -Ev '^\+\+\+')"
    if echo "$DIFF_ADDED" | grep -qiE 'cache|ttl|expir|stale'; then
        CACHE_EVIDENCE="diff to $CHANGED_DATA_SOURCE_FILES"
    fi
fi

if [ -z "$CACHE_EVIDENCE" ] && [ -n "$NEW_DATA_SOURCE_FILES" ]; then
    for f in $NEW_DATA_SOURCE_FILES; do
        if [ -f "$REPO/$f" ] && grep -qiE 'cache|ttl|expir|stale' "$REPO/$f"; then
            CACHE_EVIDENCE="new file $f"
            break
        fi
    done
fi

if [ -z "$CACHE_EVIDENCE" ]; then
    echo "FAIL: changes under $DATA_SOURCE_DIR were found, but no cache/ttl/expiry-related content was detected"
    exit 1
fi

echo "PASS: no cache/map field added to $VM_PATH; cache-related code found under $DATA_SOURCE_DIR ($CACHE_EVIDENCE)"
exit 0
