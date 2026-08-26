#!/usr/bin/env bash
# AC2: GetRemoteManga / SourceRepository's public contract is unchanged; caching is transparent
# to callers.
#
# Checks that GetRemoteManga.kt's `operator fun invoke(...)` signature and SourceRepository.kt's
# `search`/`getPopular`/`getLatest` method signatures are byte-for-byte unchanged versus the base
# commit (HEAD), i.e. no new parameters (forceRefresh/useCache/etc.) were added to any of them.
set -uo pipefail

REPO="${1:-.}"

GRM_PATH="domain/src/main/java/tachiyomi/domain/source/interactor/GetRemoteManga.kt"
REPO_IFACE_PATH="domain/src/main/java/tachiyomi/domain/source/repository/SourceRepository.kt"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

FAIL_REASON=""

# GetRemoteManga: the `operator fun invoke(...)` line must be unchanged.
GRM_SIG_DIFF="$(git -C "$REPO" diff -- "$GRM_PATH" | grep -E '^[+-]' | grep -v '^[+-][+-][+-]' | grep 'operator fun invoke')"
if [ -n "$GRM_SIG_DIFF" ]; then
    FAIL_REASON="$FAIL_REASON\n  - $GRM_PATH: 'operator fun invoke(...)' signature changed:\n$GRM_SIG_DIFF"
fi

# SourceRepository interface: search/getPopular/getLatest signatures must be unchanged.
for method in 'fun search(' 'fun getPopular(' 'fun getLatest('; do
    SIG_DIFF="$(git -C "$REPO" diff -- "$REPO_IFACE_PATH" | grep -E '^[+-]' | grep -v '^[+-][+-][+-]' | grep -F "$method")"
    if [ -n "$SIG_DIFF" ]; then
        FAIL_REASON="$FAIL_REASON\n  - $REPO_IFACE_PATH: '$method...)' signature changed:\n$SIG_DIFF"
    fi
done

# Also flag common trap parameter names anywhere in the diff of these two files, in case a
# signature was reflowed across multiple lines rather than changed on a single grep-able line.
COMBINED_ADDED="$(git -C "$REPO" diff -- "$GRM_PATH" "$REPO_IFACE_PATH" | grep -E '^\+' | grep -Ev '^\+\+\+')"
if echo "$COMBINED_ADDED" | grep -qiE 'forceRefresh|useCache|skipCache|bypassCache|noCache|refresh:\s*Boolean'; then
    FAIL_REASON="$FAIL_REASON\n  - a cache-control-looking parameter (forceRefresh/useCache/skipCache/bypassCache/noCache) was added to $GRM_PATH or $REPO_IFACE_PATH"
fi

if [ -n "$FAIL_REASON" ]; then
    echo -e "FAIL: public API of GetRemoteManga/SourceRepository changed:$FAIL_REASON"
    exit 1
fi

echo "PASS: GetRemoteManga.invoke(...) and SourceRepository.search/getPopular/getLatest signatures are unchanged"
exit 0
