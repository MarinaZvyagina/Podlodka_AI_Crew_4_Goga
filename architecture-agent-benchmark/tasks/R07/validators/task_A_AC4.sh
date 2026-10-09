#!/usr/bin/env bash
# AC4: Public function signature of AddExtensionStore is unchanged.
#
# Greps the current (working-tree) content of AddExtensionStore.kt for the
# operator fun invoke declaration and confirms it still matches the required
# signature: suspend operator fun invoke(indexUrl: String): Result<Unit>
set -uo pipefail

REPO="${1:-.}"

ADD_STORE_PATH="domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt"
FILE="$REPO/$ADD_STORE_PATH"

if [ ! -f "$FILE" ]; then
    echo "FAIL: $ADD_STORE_PATH not found in '$REPO'"
    exit 1
fi

LINE="$(grep -n 'operator fun invoke' "$FILE" || true)"

if [ -z "$LINE" ]; then
    echo "FAIL: no 'operator fun invoke' declaration found in $ADD_STORE_PATH"
    exit 1
fi

echo "$LINE" | grep -qE 'suspend operator fun invoke\(\s*indexUrl\s*:\s*String\s*\)\s*:\s*Result<Unit>'
if [ $? -ne 0 ]; then
    echo "FAIL: signature does not match expected 'suspend operator fun invoke(indexUrl: String): Result<Unit>'. Found: $LINE"
    exit 1
fi

echo "PASS: AddExtensionStore signature unchanged: $LINE"
exit 0
