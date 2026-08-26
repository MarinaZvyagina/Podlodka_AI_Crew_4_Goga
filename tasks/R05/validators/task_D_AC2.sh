#!/usr/bin/env bash
# AC2: The new component has a bounded-size / eviction mechanism analogous to
# metricnamestats.Tracker's maxSizeBytes, not an unbounded map.
#
# Method (per metadata_D.yaml): manual code review heuristic - inspect the new
# tracking type's Add/Register method for bound-checking logic. We grep newly
# added lib/storage/<newpkg>/*.go files for maxSize/maxItems/eviction-related
# identifiers, and separately flag FAIL if the diff shows a bare
# map[string]uint64 field added directly to Storage with no accompanying
# size-bound code (the negative-control trap shape).
set -u

REPO="${1:-.}"
BASE_COMMIT="f65ae841ace8f686ddc0dc17fe936d0bf38e568c"

if [ ! -d "$REPO/lib/storage" ]; then
  echo "FAIL: $REPO/lib/storage directory not found"
  exit 1
fi

KNOWN_DIRS_RE='^(metricnamestats|metricsmetadata)$'

NEW_PKG_DIRS=""
for d in "$REPO"/lib/storage/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if echo "$name" | grep -Eq "$KNOWN_DIRS_RE"; then
    continue
  fi
  if ls "$d"*.go >/dev/null 2>&1; then
    NEW_PKG_DIRS="$NEW_PKG_DIRS $name"
  fi
done
NEW_PKG_DIRS="$(echo "$NEW_PKG_DIRS" | xargs)"

# Broad heuristic: any identifier/comment referencing a max*/bound-style
# limit, or eviction/capacity/overflow handling. Deliberately broad (matches
# e.g. maxSizeBytes, maxTrackedNames, MaxTrackedDroppedSeriesNames,
# effectiveMax, DefaultMaxTrackedNames, ...) since exact naming is
# implementation-defined; this is a heuristic pre-filter, not a full
# semantic check.
BOUND_RE='[Mm]ax[A-Za-z]*|[Bb]ound[A-Za-z]*|eviction|evict|LRU|lru|cacheIsFull|sizeLimit|capacity|Capacity|overflow|Overflow'

if [ -n "$NEW_PKG_DIRS" ]; then
  FOUND_BOUND=""
  FOUND_ANY_GO=""
  for name in $NEW_PKG_DIRS; do
    dir="$REPO/lib/storage/$name"
    for f in "$dir"/*.go; do
      [ -f "$f" ] || continue
      case "$f" in *_test.go) continue ;; esac
      FOUND_ANY_GO="yes"
      if grep -EqI "$BOUND_RE" "$f"; then
        FOUND_BOUND="$FOUND_BOUND $f"
      fi
    done
  done
  FOUND_BOUND="$(echo "$FOUND_BOUND" | xargs)"

  if [ -z "$FOUND_ANY_GO" ]; then
    echo "MANUAL REVIEW REQUIRED: new package dir(s) [$NEW_PKG_DIRS] found under lib/storage/ but contain no non-test .go files to inspect"
    exit 2
  fi

  if [ -n "$FOUND_BOUND" ]; then
    echo "PASS: bound/eviction-related identifiers found in new subpackage file(s): $FOUND_BOUND"
    exit 0
  else
    echo "FAIL: new subpackage(s) [$NEW_PKG_DIRS] found under lib/storage/ but no bound/eviction-related identifiers (maxSize/maxItems/evict/capacity/...) detected in their .go files"
    exit 1
  fi
fi

# No new subpackage found. Check whether a raw unbounded map was bolted directly onto
# Storage (the trap shape) - if so, definitively FAIL. Otherwise this is likely the
# baseline (no feature at all): inconclusive for AC2 since there is nothing to bound.
STORAGE_GO="$REPO/lib/storage/storage.go"
if [ ! -f "$STORAGE_GO" ]; then
  echo "FAIL: $STORAGE_GO not found"
  exit 1
fi

if git -C "$REPO" cat-file -e "$BASE_COMMIT" 2>/dev/null; then
  DIFF_OUT="$(git -C "$REPO" diff "$BASE_COMMIT" -- lib/storage/storage.go lib/storage/index_db.go lib/storage/partition.go 2>/dev/null)"
else
  DIFF_OUT="$(git -C "$REPO" diff -- lib/storage/storage.go lib/storage/index_db.go lib/storage/partition.go 2>/dev/null)"
fi

RAW_MAP_ADDED="$(echo "$DIFF_OUT" | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -E 'map\[string\](uint64|int)' | grep -iE 'drop|serieslimit|series-limit|series_limit')"

if [ -n "$RAW_MAP_ADDED" ]; then
  # Only consider actual added Go code (skip comment-only lines and skip mere
  # mentions of the pre-existing -storage.maxHourlySeries / -storage.maxDailySeries
  # flag names, which are not evidence of new bound/eviction logic).
  ADDED_CODE_LINES="$(echo "$DIFF_OUT" | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -Ev '^\+[[:space:]]*//' | grep -Ev -- '-storage\.max(Hourly|Daily)Series')"
  BOUND_NEARBY="$(echo "$ADDED_CODE_LINES" | grep -EI "$BOUND_RE")"
  if [ -z "$BOUND_NEARBY" ]; then
    echo "FAIL: bare unbounded map (e.g. map[string]uint64) added directly to Storage/index_db/partition for drop tracking, with no accompanying size-bound/eviction code:"
    echo "$RAW_MAP_ADDED"
    exit 1
  else
    echo "MANUAL REVIEW REQUIRED: raw map added directly to Storage for drop tracking, but some bound-related identifiers also appear in the diff - needs human judgement on whether the map itself is actually bounded"
    exit 2
  fi
fi

echo "MANUAL REVIEW REQUIRED: no new lib/storage/ subpackage and no raw drop-tracking map detected - feature appears absent from this repo state, so bounded-size cannot be evaluated"
exit 2
