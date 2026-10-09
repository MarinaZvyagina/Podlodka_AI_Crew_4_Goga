#!/usr/bin/env bash
# AC3: The cache is bounded/expiring, not a permanently-frozen cache.
# Fails if functools.lru_cache/@cache appears anywhere in the diff's added
# (non-test) source lines. Otherwise requires evidence of a TTL/expiry
# mechanism (PeriodicCache/TTLCache/FtTTLCache or an explicit ttl=... /
# timestamp-comparison) in those same added lines.
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository, cannot inspect diff"
    exit 1
fi

DIFF=$(git -C "$REPO" diff HEAD)

if [[ -z "$DIFF" ]]; then
    echo "FAIL: no diff found against HEAD -- nothing to check"
    exit 1
fi

ADDED_SRC=$(echo "$DIFF" | awk '
    /^\+\+\+ b\// { file=$0; sub(/^\+\+\+ b\//, "", file); next }
    /^\+/ && !/^\+\+\+/ {
        if (file !~ /^tests\//) {
            line=$0
            sub(/^\+/, "", line)
            print file": "line
        }
    }
')

LRU_HITS=$(echo "$ADDED_SRC" | grep -E 'lru_cache|@cache\b|functools\.cache' || true)

if [[ -n "$LRU_HITS" ]]; then
    echo "FAIL: unbounded functools.lru_cache/@cache found on the price-fetch path (never expires):"
    echo "$LRU_HITS"
    exit 1
fi

TTL_HITS=$(echo "$ADDED_SRC" | grep -E 'PeriodicCache|TTLCache|FtTTLCache|ttl[[:space:]]*=' || true)

if [[ -z "$TTL_HITS" ]]; then
    echo "FAIL: no PeriodicCache/TTLCache/explicit ttl= (or equivalent short-bound timestamp check) found in the diff's added source lines -- cache does not appear bounded"
    exit 1
fi

echo "PASS: cache uses a bounded/expiring TTL mechanism, no lru_cache/@cache found. Evidence:"
echo "$TTL_HITS"
exit 0
