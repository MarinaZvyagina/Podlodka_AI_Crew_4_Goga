#!/usr/bin/env bash
# AC2: New caching code depends on MVCC revision/watch machinery for
# invalidation (rather than only a wall-clock timestamp).
#
# Method: find new/changed Go (non-test) files that look like they
# implement the cache (filename or content mentions "cache"), then check
# each candidate for a dependency on mvcc revision/watch concepts. A
# candidate file living inside server/storage/mvcc itself uses those types
# without an import statement (same package), so it is checked for direct
# usage of RangeResult/Rev()/currentRev/compactMainRev/Watchable/WatchStream
# identifiers instead of an import line. A candidate file outside that
# package must both import go.etcd.io/etcd/server/v3/storage/mvcc and
# reference one of those same identifiers.
set -u

REPO="${1:-.}"
BASELINE="23a4e406a2e70a807486b4c40a9e24da493886bf"

if ! git -C "$REPO" rev-parse "$BASELINE" >/dev/null 2>&1; then
  echo "MANUAL REVIEW REQUIRED: baseline commit $BASELINE not found in $REPO"
  exit 2
fi

# Include both tracked modifications vs baseline and new untracked .go
# files (git diff --name-only alone misses files that were added but
# never `git add`-ed).
TRACKED_CHANGED=$(git -C "$REPO" diff --stat "$BASELINE" --name-only -- '*.go' 2>/dev/null)
UNTRACKED_NEW=$(git -C "$REPO" ls-files --others --exclude-standard -- '*.go' 2>/dev/null)
CHANGED_GO=$(printf '%s\n%s\n' "$TRACKED_CHANGED" "$UNTRACKED_NEW" | sed '/^$/d' | sort -u | grep -v '_test\.go$')

if [ -z "$CHANGED_GO" ]; then
  echo "MANUAL REVIEW REQUIRED: no changed non-test .go files vs baseline; cannot locate cache implementation to check"
  exit 2
fi

CANDIDATES=""
for f in $CHANGED_GO; do
  full="$REPO/$f"
  [ -f "$full" ] || continue
  base=$(basename "$f")
  if echo "$base" | grep -qi 'cache'; then
    CANDIDATES="$CANDIDATES $f"
    continue
  fi
  if grep -qi 'cache' "$full" 2>/dev/null; then
    CANDIDATES="$CANDIDATES $f"
  fi
done

CANDIDATES=$(echo "$CANDIDATES" | xargs -n1 2>/dev/null | sort -u)

if [ -z "$CANDIDATES" ]; then
  echo "MANUAL REVIEW REQUIRED: no changed file appears to implement a cache (no 'cache'-related filename/content found); cannot verify mvcc dependency"
  exit 2
fi

MVCC_SIGNAL_RE='RangeResult|\.Rev\(\)|currentRev|compactMainRev|Watchable|WatchStream|NewWatchStream'

FAIL_FILES=""
PASS_FILES=""
for f in $CANDIDATES; do
  full="$REPO/$f"
  case "$f" in
    server/storage/mvcc/*)
      if grep -qE "$MVCC_SIGNAL_RE" "$full" 2>/dev/null; then
        PASS_FILES="$PASS_FILES $f"
      else
        FAIL_FILES="$FAIL_FILES $f(same-package-but-no-revision/watch-signal)"
      fi
      ;;
    *)
      if grep -q 'go.etcd.io/etcd/server/v3/storage/mvcc' "$full" 2>/dev/null && grep -qE "$MVCC_SIGNAL_RE" "$full" 2>/dev/null; then
        PASS_FILES="$PASS_FILES $f"
      else
        FAIL_FILES="$FAIL_FILES $f"
      fi
      ;;
  esac
done

if [ -n "$FAIL_FILES" ]; then
  echo "FAIL: cache-related file(s) with no demonstrable mvcc revision/watch dependency:$FAIL_FILES"
  [ -n "$PASS_FILES" ] && echo "(other cache-related files that do reference mvcc revision/watch machinery:$PASS_FILES)"
  exit 1
fi

echo "PASS: cache-related file(s) reference mvcc revision/watch machinery:$PASS_FILES"
exit 0
