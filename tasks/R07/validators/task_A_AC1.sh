#!/usr/bin/env bash
# AC1: Validation happens in the domain interactor, not the data layer.
#
# Checks:
#  1. AddExtensionStore.kt gained new logic (diff is non-empty for that file) and
#     the interactor now contains something that looks like validation (a
#     Result.failure / IllegalArgumentException / require / scheme check) before
#     repository.insert(...) is called.
#  2. ExtensionStoreRepositoryImpl.kt and ExtensionStoreService.kt (data layer)
#     must NOT gain any new URL-scheme / validation logic.
set -uo pipefail

REPO="${1:-.}"

ADD_STORE_PATH="domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt"
REPO_IMPL_PATH="data/src/main/java/mihon/data/extension/repository/ExtensionStoreRepositoryImpl.kt"
SERVICE_PATH="data/src/main/java/mihon/data/extension/service/ExtensionStoreService.kt"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

ADD_STORE_DIFF="$(git -C "$REPO" diff -- "$ADD_STORE_PATH")"
ADD_STORE_CONTENT="$(cat "$REPO/$ADD_STORE_PATH" 2>/dev/null)"

if [ -z "$ADD_STORE_DIFF" ]; then
    echo "FAIL: no diff found in $ADD_STORE_PATH — expected new validation logic in the domain interactor"
    exit 1
fi

# Look for validation-ish markers added to AddExtensionStore.kt
ADDED_LINES="$(git -C "$REPO" diff -- "$ADD_STORE_PATH" | grep -E '^\+' | grep -vE '^\+\+\+')"
if ! echo "$ADDED_LINES" | grep -qiE 'Result\.failure|IllegalArgumentException|require\(|startsWith\("http|toHttpUrlOrNull|URI\(|URL\(|scheme'; then
    echo "FAIL: $ADD_STORE_PATH changed, but no recognizable validation logic (Result.failure/IllegalArgumentException/require/scheme check/URI parsing) was found in the added lines"
    exit 1
fi

# Confirm repository.insert(...) call still present in the file (i.e. valid path still delegates)
if ! echo "$ADD_STORE_CONTENT" | grep -q 'repository.insert('; then
    echo "FAIL: $ADD_STORE_PATH no longer calls repository.insert(...) at all — expected valid URLs to still be delegated"
    exit 1
fi

# Now confirm the data layer did NOT gain new validation logic.
FAIL_REASON=""
for f in "$REPO_IMPL_PATH" "$SERVICE_PATH"; do
    ADDED="$(git -C "$REPO" diff -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+')"
    if [ -n "$ADDED" ] && echo "$ADDED" | grep -qiE 'IllegalArgumentException|require\(|startsWith\("http|toHttpUrlOrNull|URI\(|URL\(|not a valid|invalid.*url|scheme'; then
        FAIL_REASON="$FAIL_REASON\n  - $f gained new validation-like logic"
    fi
done

if [ -n "$FAIL_REASON" ]; then
    echo -e "FAIL: validation logic (also) found in data layer:$FAIL_REASON"
    exit 1
fi

echo "PASS: validation-like logic added to $ADD_STORE_PATH (domain interactor); repository.insert(...) still called for the valid path; no validation logic detected in data-layer files"
exit 0
