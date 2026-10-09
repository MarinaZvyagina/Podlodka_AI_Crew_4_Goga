#!/usr/bin/env bash
# AC3: Presentation layer (ExtensionStoresViewModel and its Screen/Composable) is untouched.
#
# Checks git diff --name-only for any changed files under
# app/src/main/java/eu/kanade/presentation/more/settings/screen/browse/ that relate
# to ExtensionStores (ViewModel, Screen, or other Composable files).
set -uo pipefail

REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

CHANGED_FILES="$(git -C "$REPO" diff --name-only)"

MATCHES="$(echo "$CHANGED_FILES" | grep -E 'app/src/main/java/eu/kanade/presentation/more/settings/screen/browse/ExtensionStore' || true)"

if [ -n "$MATCHES" ]; then
    echo "FAIL: presentation-layer ExtensionStores file(s) were modified:"
    echo "$MATCHES"
    exit 1
fi

echo "PASS: no changes to ExtensionStoresViewModel.kt or ExtensionStoresScreen*.kt / related Composables"
exit 0
