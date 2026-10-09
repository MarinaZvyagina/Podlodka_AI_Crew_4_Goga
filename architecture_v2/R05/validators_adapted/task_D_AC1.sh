#!/usr/bin/env bash
# AC1: New tracking state is encapsulated in its own subpackage under lib/storage/,
# not added as raw fields on the Storage struct.
#
# Method (per metadata_D.yaml):
#   - ls lib/storage/ to check for a new subdirectory (package), analogous to
#     metricnamestats/ and metricsmetadata/.
#   - locate the Storage struct definition in lib/storage/storage.go and inspect
#     whether any new map[string]... or sync.Mutex fields were added directly to
#     that struct (via git diff against the baseline commit if available, else via
#     a heuristic scan of the struct body).
set -u

REPO="${1:-.}"
BASE_COMMIT="1afc7bb270a2529639eef177b9c75d549d3169f4"

if [ ! -d "$REPO/lib/storage" ]; then
  echo "FAIL: $REPO/lib/storage directory not found"
  exit 1
fi

# --- Part A: look for a new subpackage directory under lib/storage/ ---
KNOWN_DIRS="metricnamestats
metricsmetadata"

NEW_PKG_DIRS=""
for d in "$REPO"/lib/storage/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  case "$name" in
    metricnamestats|metricsmetadata) continue ;;
  esac
  # must contain at least one .go file to count as a real package
  if ls "$d"*.go >/dev/null 2>&1; then
    NEW_PKG_DIRS="$NEW_PKG_DIRS $name"
  fi
done
NEW_PKG_DIRS="$(echo "$NEW_PKG_DIRS" | xargs)"

# --- Part B: inspect Storage struct in storage.go for new raw map/mutex fields ---
STORAGE_GO="$REPO/lib/storage/storage.go"
if [ ! -f "$STORAGE_GO" ]; then
  echo "FAIL: $STORAGE_GO not found"
  exit 1
fi

# Extract the Storage struct body (from "type Storage struct {" to its closing brace).
STRUCT_BODY="$(awk '/^type Storage struct \{/{flag=1} flag{print} flag && /^\}/{exit}' "$STORAGE_GO")"

# Heuristic: raw map or sync.Mutex/sync.RWMutex fields added directly on Storage that
# look related to drop/series-limit tracking (not part of the original baseline fields
# such as missingMetricIDs, snapshotLock, etc.). We diff against the pinned base commit
# when the repo has that commit available, to distinguish "new" fields from pre-existing
# ones; otherwise we fall back to keyword matching.
SUSPICIOUS_FIELDS=""
if git -C "$REPO" cat-file -e "$BASE_COMMIT" 2>/dev/null; then
  DIFF_OUT="$(git -C "$REPO" diff "$BASE_COMMIT" -- lib/storage/storage.go lib/storage/index_db.go lib/storage/partition.go 2>/dev/null)"
else
  DIFF_OUT="$(git -C "$REPO" diff -- lib/storage/storage.go lib/storage/index_db.go lib/storage/partition.go 2>/dev/null)"
fi

if [ -n "$DIFF_OUT" ]; then
  ADDED_LINES="$(echo "$DIFF_OUT" | grep -E '^\+' | grep -Ev '^\+\+\+')"
  SUSPICIOUS_FIELDS="$(echo "$ADDED_LINES" | grep -E '(map\[string\](uint64|int|\*|struct)|sync\.(Mutex|RWMutex))' | grep -iE 'drop|serieslimit|series-limit|series_limit|hourly|daily' )"
else
  # No diff available (e.g. repo has no git history / already committed): fall back to
  # scanning the struct body itself for suspicious drop-tracking raw fields.
  SUSPICIOUS_FIELDS="$(echo "$STRUCT_BODY" | grep -E '(map\[string\](uint64|int|\*|struct)|sync\.(Mutex|RWMutex))' | grep -iE 'drop|serieslimit|series-limit|series_limit')"
fi

if [ -n "$SUSPICIOUS_FIELDS" ]; then
  echo "FAIL: Storage struct (or index_db.go/partition.go) appears to gain raw map/mutex fields for drop tracking directly, bypassing subpackage encapsulation:"
  echo "$SUSPICIOUS_FIELDS"
  exit 1
fi

if [ -n "$NEW_PKG_DIRS" ]; then
  echo "PASS: new subpackage(s) found under lib/storage/: $NEW_PKG_DIRS; no raw drop-tracking map/mutex fields detected directly on Storage struct"
  exit 0
fi

# No new subpackage AND no raw fields detected: this is the "no feature implemented at
# all" baseline case. Per the task spec this passes AC1 vacuously (nothing to encapsulate
# badly), but note that in this state the feature itself is missing.
echo "PASS: no new lib/storage/ subpackage found, but also no raw drop-tracking map/mutex fields added directly to Storage struct (vacuous pass - feature may simply be absent)"
exit 0
