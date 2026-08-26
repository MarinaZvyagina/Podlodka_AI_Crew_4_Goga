#!/usr/bin/env bash
# AC1: No freestanding, revision-unaware cache added at the gRPC handler
# layer (server/etcdserver/api/v3rpc/).
#
# Method: restrict the grep to files that actually changed vs the pinned
# baseline commit (to avoid false positives from pre-existing, unrelated
# matches elsewhere in the package), then look for cache-shaped constructs:
# sync.Map, an lru package, TTL/expiry constants, time.After, or an
# "Expires" field/identifier.
set -u

REPO="${1:-.}"
BASELINE="23a4e406a2e70a807486b4c40a9e24da493886bf"
PKG="server/etcdserver/api/v3rpc"

if ! git -C "$REPO" rev-parse "$BASELINE" >/dev/null 2>&1; then
  echo "MANUAL REVIEW REQUIRED: baseline commit $BASELINE not found in $REPO"
  exit 2
fi

# Include both tracked modifications vs baseline and new untracked files
# (git diff --name-only alone misses files that were added but never
# `git add`-ed).
TRACKED_CHANGED=$(git -C "$REPO" diff --stat "$BASELINE" --name-only -- "$PKG" 2>/dev/null)
UNTRACKED_NEW=$(git -C "$REPO" ls-files --others --exclude-standard -- "$PKG" 2>/dev/null)
CHANGED_FILES=$(printf '%s\n%s\n' "$TRACKED_CHANGED" "$UNTRACKED_NEW" | sed '/^$/d' | sort -u)

if [ -z "$CHANGED_FILES" ]; then
  echo "PASS: no files changed under $PKG/ vs baseline; no freestanding cache introduced there"
  exit 0
fi

HITS=""
for f in $CHANGED_FILES; do
  full="$REPO/$f"
  [ -f "$full" ] || continue
  m=$(grep -nE 'sync\.Map|lru\.|TTL|time\.After|Expires' "$full" 2>/dev/null)
  if [ -n "$m" ]; then
    HITS="${HITS}--- $f ---\n${m}\n"
  fi
done

if [ -n "$HITS" ]; then
  echo "FAIL: cache-like construct (sync.Map/lru/TTL/time.After/Expires) found in changed file(s) under $PKG/:"
  printf '%b\n' "$HITS"
  exit 1
fi

echo "PASS: files changed under $PKG/ ($CHANGED_FILES) contain no sync.Map/lru/TTL/time.After/Expires cache constructs"
exit 0
