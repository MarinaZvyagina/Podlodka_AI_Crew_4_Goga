#!/usr/bin/env bash
# AC3: Call sites are added only at the existing drop-detection points
# (logSkippedSeries call sites), not duplicated elsewhere or reimplementing the
# limiter check.
#
# Method (per metadata_D.yaml): grep -n logSkippedSeries lib/storage/storage.go
# and confirm the new tracking call sits immediately alongside these existing
# calls, rather than a separate independent pass over rows re-deriving which
# ones were dropped.
#
# Implementation approach: diff lib/storage/storage.go against the pinned base
# commit (with context lines) and check whether any diff hunk that contains a
# logSkippedSeries(...) line also contains newly added ("+") lines - i.e. new
# code was inserted right next to the existing drop-detection call site.
set -u

REPO="${1:-.}"
BASE_COMMIT="f65ae841ace8f686ddc0dc17fe936d0bf38e568c"
STORAGE_GO="$REPO/lib/storage/storage.go"

if [ ! -f "$STORAGE_GO" ]; then
  echo "FAIL: $STORAGE_GO not found"
  exit 1
fi

CALL_SITES="$(grep -n 'logSkippedSeries(' "$STORAGE_GO" | grep -v ':func ')"
if [ -z "$CALL_SITES" ]; then
  echo "FAIL: no logSkippedSeries(...) call sites found in $STORAGE_GO - drop-detection hook point appears to have been removed/relocated"
  exit 1
fi

HAVE_BASE=0
if git -C "$REPO" cat-file -e "$BASE_COMMIT" 2>/dev/null; then
  HAVE_BASE=1
  DIFF_OUT="$(git -C "$REPO" diff -U5 "$BASE_COMMIT" -- lib/storage/storage.go 2>/dev/null)"
else
  DIFF_OUT="$(git -C "$REPO" diff -U5 -- lib/storage/storage.go 2>/dev/null)"
fi

if [ -z "$DIFF_OUT" ]; then
  echo "FAIL: no diff detected for $STORAGE_GO (against $([ "$HAVE_BASE" -eq 1 ] && echo "base commit $BASE_COMMIT" || echo "working tree")) - no new tracking call has been added anywhere, including next to the logSkippedSeries call sites"
  exit 1
fi

# Split the diff into hunks (blocks starting with "@@") and check each hunk for
# both a logSkippedSeries(...) line (context or otherwise) and at least one
# genuinely new, non-trivial added line.
HUNK_HIT=""
CURRENT_HUNK=""
IN_HUNK=0

check_hunk() {
  local hunk="$1"
  if echo "$hunk" | grep -q 'logSkippedSeries('; then
    # does this hunk contain a non-trivial added line (not blank, not the +++ file header)?
    local added
    added="$(echo "$hunk" | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -Ev '^\+[[:space:]]*$')"
    if [ -n "$added" ]; then
      echo "---"
      echo "$hunk" | head -1
      echo "$added"
    fi
  fi
}

# Use awk to split on lines starting with "@@" and feed each hunk to check_hunk.
TMP_HUNKS_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_HUNKS_DIR"' EXIT

echo "$DIFF_OUT" | awk -v dir="$TMP_HUNKS_DIR" '
  /^@@/{n++; fname=dir"/hunk"n".txt"}
  n>0 {print > fname}
'

RESULTS=""
for f in "$TMP_HUNKS_DIR"/hunk*.txt; do
  [ -f "$f" ] || continue
  hunk_content="$(cat "$f")"
  res="$(check_hunk "$hunk_content")"
  if [ -n "$res" ]; then
    RESULTS="${RESULTS}
${res}"
  fi
done

if [ -z "$RESULTS" ]; then
  echo "FAIL: found logSkippedSeries(...) call site(s) in $STORAGE_GO, but no diff hunk touching those call sites contains newly added code - tracking call is not adjacent to the existing drop-detection points (or is added elsewhere in the file)"
  exit 1
fi

echo "PASS: diff hunk(s) touching the logSkippedSeries(...) call site(s) contain newly added code, consistent with a tracking call added right next to the existing drop-detection points:"
echo "$RESULTS"
exit 0
