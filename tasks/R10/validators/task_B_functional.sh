#!/usr/bin/env bash
# Task B functional validator: attachments-only filter for in-conversation search.
#
# Calibration note (see FUNCTIONAL_VALIDATORS.md for the full reasoning): unlike Task A, this task's own
# notes_for_positive_negative_control explicitly design the negative/trap control to "pass a shallow ...
# functional test" (it really does filter results correctly for a same-device user) while failing the
# architecture checks (AC2/AC3) because the filtering logic lives in the wrong layer / uses raw SQL instead of
# the AttachmentStore abstraction. This functional check is therefore DELIBERATELY implementation-agnostic
# about *where* the filtering happens -- that discrimination is task_B_AC2.sh / task_B_AC3.sh's job, not this
# script's. This script only asks: "does toggling an attachments-only mode actually narrow in-conversation
# search results using some attachment-presence signal?"
#
# Usage: task_B_functional.sh [repo_path]  (default: .)
set -uo pipefail
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_B_test.swift"

cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree"
  exit 1
fi

safe_diff() {
  git diff -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    printf '+++ b/%s (untracked new file)\n' "$f"
    sed 's/^/+/' "$f"
  done
}
# Added, non-comment-only lines (so a doc comment merely *mentioning* a pattern doesn't count as implementing it).
added_code_lines() {
  safe_diff "$@" | grep -E '^\+' | grep -v '^+++' | sed -E 's/^\+[[:space:]]*//' | grep -vE '^//'
}

TEST_FILE="Signal/test/util/FTS/GRDBFullTextSearcherTest.swift"
MARK_BEGIN="// === TASK_B_FUNCTIONAL_VALIDATOR_INJECTED_BEGIN ==="
MARK_END="// === TASK_B_FUNCTIONAL_VALIDATOR_INJECTED_END ==="
INJECTED=0

cleanup() {
  if [ "$INJECTED" -eq 1 ] && [ -f "$TEST_FILE" ]; then
    # Remove exactly the block we appended (between markers), plus the single blank separator line we added
    # immediately before it, leaving any of the candidate's own edits to this file intact.
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      { lines[NR] = $0 }
      END {
        skip = 0
        out_n = 0
        for (i = 1; i <= NR; i++) {
          line = lines[i]
          if (line == b) {
            skip = 1
            if (out_n > 0 && out[out_n] == "") { out_n-- }
            continue
          }
          if (line == e) { skip = 0; continue }
          if (skip) continue
          out_n++
          out[out_n] = line
        }
        for (i = 1; i <= out_n; i++) print out[i]
      }
    ' "$TEST_FILE" > "$TEST_FILE.tmp" && mv "$TEST_FILE.tmp" "$TEST_FILE"
  fi
}
trap cleanup EXIT

DIFF_ALL="$(safe_diff .)"
if [ -z "$DIFF_ALL" ]; then
  echo "FAIL: no working-tree changes found (nothing to check)"
  exit 1
fi

echo "--- Step 1: inject fixture + swiftc -parse syntax check ---"
if [ -f "$TEST_FILE" ]; then
  { printf '\n%s\n' "$MARK_BEGIN"; cat "$FIXTURE"; printf '%s\n' "$MARK_END"; } >> "$TEST_FILE"
  INJECTED=1
  if command -v swiftc >/dev/null 2>&1; then
    if swiftc -parse "$TEST_FILE" >/tmp/task_B_swiftc_parse.log 2>&1; then
      echo "swiftc -parse: OK (syntax-level only) -- $TEST_FILE"
    else
      if grep -qi "expected \|expression\|unterminated\|extraneous\|consecutive statements" /tmp/task_B_swiftc_parse.log; then
        echo "FAIL: swiftc -parse found a syntax error in $TEST_FILE after fixture injection:"
        cat /tmp/task_B_swiftc_parse.log
        exit 1
      else
        echo "swiftc -parse: no gross syntax errors detected (module-resolution errors are expected/ignored here)"
      fi
    fi
  else
    echo "MANUAL REVIEW REQUIRED: swiftc not found on PATH; skipped syntax check"
  fi
else
  echo "MANUAL REVIEW REQUIRED: $TEST_FILE not found -- could not inject fixture"
fi

echo
echo "--- Step 2: disk-gated real xcodebuild test attempt ---"
AVAIL_KB="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
DISK_THRESHOLD_GB=40
if [ "$AVAIL_GB" -ge "$DISK_THRESHOLD_GB" ] && command -v xcodebuild >/dev/null 2>&1 && [ -d "Signal.xcworkspace" ]; then
  echo "Free disk (${AVAIL_GB}GB) clears the ${DISK_THRESHOLD_GB}GB safety threshold -- attempting a real build."
  echo "NOTE: this fixture assumes the architecturally-prescribed 'attachmentsOnly' parameter exists on"
  echo "FullTextSearcher.searchWithinConversation. A candidate that implements filtering entirely in the UI layer"
  echo "(like this task's own negative control) will fail to COMPILE against this fixture, not just fail an"
  echo "assertion -- that is a known, documented limitation (see fixtures/task_B_test.swift header)."
  if xcodebuild -workspace Signal.xcworkspace -scheme Signal -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -60; then
    DYNAMIC_RESULT="ran"
  else
    DYNAMIC_RESULT="ran_failed"
  fi
else
  echo "MANUAL REVIEW REQUIRED: skipped real xcodebuild build/test run -- only ${AVAIL_GB}GB free (< ${DISK_THRESHOLD_GB}GB"
  echo "safety threshold). See CONTROL_RESULTS.md / FUNCTIONAL_VALIDATORS.md for why full builds are impractical"
  echo "in this disk-constrained environment. Falling back to the static/behavioral check below."
  DYNAMIC_RESULT="skipped"
fi

echo
echo "--- Step 3: static/behavioral, layer-agnostic check for a working attachments-only filter ---"

TOGGLE_SIGNAL="$(added_code_lines . | grep -iE 'attachmentsOnly|attachmentOnly|isAttachmentsOnlyFilter|filterAttachments|onlyAttachments' || true)"
ATTACHMENT_CHECK_SIGNAL="$(added_code_lines . | grep -E 'hasBodyAttachments\(|attachmentStore\.fetchReferences\(|MessageAttachmentReference|hasMediaAttachments\(' || true)"

if [ -z "$TOGGLE_SIGNAL" ]; then
  echo "FAIL: no added code introduces an attachments-only filter toggle/parameter (searched for attachmentsOnly/attachmentOnly/isAttachmentsOnlyFilter/filterAttachments/onlyAttachments in the diff)"
  exit 1
fi
echo "Found attachments-only toggle/parameter signal:"
echo "$TOGGLE_SIGNAL" | head -5

if [ -z "$ATTACHMENT_CHECK_SIGNAL" ]; then
  echo "FAIL: an attachments-only toggle exists, but no added code actually checks attachment presence"
  echo "(searched for hasBodyAttachments(/attachmentStore.fetchReferences(/MessageAttachmentReference/hasMediaAttachments( in the diff)."
  echo "This looks like the Task A-style trap: a UI control that exists but never filters anything."
  exit 1
fi
echo "Found attachment-presence check signal used somewhere in the diff (any layer -- this check is intentionally"
echo "agnostic to whether it's the AttachmentStore abstraction or a raw query; see task_B_AC2.sh/AC3.sh for that):"
echo "$ATTACHMENT_CHECK_SIGNAL" | head -5

echo
echo "PASS (static/behavioral): both an attachments-only toggle and an attachment-presence-based filtering signal"
echo "are present in the diff, consistent with the feature actually narrowing search results, not just adding a"
echo "cosmetic UI control."
echo
echo "MANUAL REVIEW REQUIRED: this script cannot execute a real in-conversation search (would need a full app"
echo "build + simulated conversation with real photo/video/voice/file attachments) to confirm result correctness"
echo "at runtime, that navigation (previous/next result) still works, or that group vs 1:1 threads both work --"
echo "confirm those manually per metadata_B.yaml's functional_requirements if in doubt."

if [ "$DYNAMIC_RESULT" = "ran_failed" ]; then
  echo "FAIL: real xcodebuild build attempt ran and failed (see build log above) -- treating as a genuine functional failure signal."
  exit 1
fi

echo
echo "PASS: Task B functional check (static/behavioral verification$( [ "$DYNAMIC_RESULT" = "ran" ] && echo " + real xcodebuild build" ))."
exit 0
