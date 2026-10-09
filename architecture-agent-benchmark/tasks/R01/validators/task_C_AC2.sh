#!/usr/bin/env bash
# AC2: The new handler is loadable through the existing resolver purely by
# class name/config -- no core wiring changes needed. Confirms (a) the new
# handler file lives in freqtrade/plugins/protections/ (ProtectionResolver's
# initial_search_path) and (b) freqtrade/resolvers/protection_resolver.py and
# freqtrade/plugins/protectionmanager.py have an EMPTY diff vs HEAD (no
# special-casing added for the new handler's name).
set -uo pipefail
REPO="${1:-.}"
DIR="$REPO/freqtrade/plugins/protections"
RESOLVER="freqtrade/resolvers/protection_resolver.py"
MANAGER="freqtrade/plugins/protectionmanager.py"

if [[ ! -d "$DIR" ]]; then
    echo "FAIL: $DIR not found"
    exit 1
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

BASELINE="cooldown_period.py low_profit_pairs.py max_drawdown_protection.py stoploss_guard.py iprotection.py __init__.py"
NEW_FILES=()
for f in "$DIR"/*.py; do
    base=$(basename "$f")
    skip=0
    for b in $BASELINE; do
        [[ "$base" == "$b" ]] && skip=1 && break
    done
    [[ $skip -eq 0 ]] && NEW_FILES+=("$base")
done

if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
    echo "FAIL: no new handler file found under $DIR (search path ProtectionResolver uses)"
    exit 1
fi

RESOLVER_DIFF=$(git -C "$REPO" diff -- "$RESOLVER")
MANAGER_DIFF=$(git -C "$REPO" diff -- "$MANAGER")

if [[ -n "$RESOLVER_DIFF" ]]; then
    echo "FAIL: $RESOLVER has a non-empty diff -- indicates special-casing was added instead of relying on generic dynamic loading:"
    echo "$RESOLVER_DIFF"
    exit 1
fi

if [[ -n "$MANAGER_DIFF" ]]; then
    echo "FAIL: $MANAGER has a non-empty diff -- indicates special-casing was added instead of relying on generic ProtectionManager orchestration:"
    echo "$MANAGER_DIFF"
    exit 1
fi

echo "PASS: new handler file(s) (${NEW_FILES[*]}) placed in $DIR; $RESOLVER and $MANAGER both have empty diffs -- loadable purely by class name via existing ProtectionResolver"
exit 0
