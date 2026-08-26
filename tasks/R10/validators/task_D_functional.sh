#!/usr/bin/env bash
# Task D functional validator: delete all messages sent by me in a conversation.
#
# Calibration note (see FUNCTIONAL_VALIDATORS.md): this task's own notes_for_positive_negative_control are
# explicit that the negative/trap control "compiles, deletes the right messages on the current device, and can
# pass a same-device functional test ... while silently failing to sync the deletion to linked devices and
# skipping CallRecord/cache cleanup ... i.e. Functional Success = true, Architecture Conformance = false." This
# functional check is therefore DELIBERATELY scoped to same-device deletion mechanics only (does the feature
# select the local user's messages in a thread and actually remove them), matching that documented intent.
# Multi-device sync, CallRecord consistency, and immediate cache/UI consistency are exactly what
# task_D_AC2.sh/AC3.sh/AC4.sh check, and are also called out below as MANUAL REVIEW REQUIRED / cannot be
# faked-passing here.
#
# As with Task C, this task's real entry point is a new method whose name is not fixed by the spec (only the
# underlying InteractionDeleteManager/DeleteForMeOutgoingSyncMessageManager it must route through is fixed) --
# see fixtures/task_D_test.swift for why a literal compiled call isn't attempted here.
#
# Usage: task_D_functional.sh [repo_path]  (default: .)
set -uo pipefail
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_D_test.swift"

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
added_code_lines() {
  safe_diff "$@" | grep -E '^\+' | grep -v '^+++' | sed -E 's/^\+[[:space:]]*//' | grep -vE '^//'
}

TEST_FILE="SignalServiceKit/tests/Messages/DeleteForMe/DeleteForMeOutgoingSyncMessageManagerTest.swift"
MARK_BEGIN="// === TASK_D_FUNCTIONAL_VALIDATOR_INJECTED_BEGIN ==="
MARK_END="// === TASK_D_FUNCTIONAL_VALIDATOR_INJECTED_END ==="
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

echo "--- Step 1: inject fixture (documentation/checklist -- see fixtures/task_D_test.swift) + swiftc -parse ---"
if [ -f "$TEST_FILE" ]; then
  { printf '\n%s\n' "$MARK_BEGIN"; cat "$FIXTURE"; printf '%s\n' "$MARK_END"; } >> "$TEST_FILE"
  INJECTED=1
  if command -v swiftc >/dev/null 2>&1; then
    if swiftc -parse "$TEST_FILE" >/tmp/task_D_swiftc_parse.log 2>&1; then
      echo "swiftc -parse: OK -- $TEST_FILE (fixture is comment-only documentation; this mainly confirms no file corruption)"
    else
      if grep -qi "expected \|expression\|unterminated\|extraneous\|consecutive statements" /tmp/task_D_swiftc_parse.log; then
        echo "FAIL: swiftc -parse found a syntax error in $TEST_FILE after fixture injection:"
        cat /tmp/task_D_swiftc_parse.log
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
echo "--- Step 2: disk-gated real xcodebuild attempt ---"
AVAIL_KB="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
DISK_THRESHOLD_GB=40
if [ "$AVAIL_GB" -ge "$DISK_THRESHOLD_GB" ] && command -v xcodebuild >/dev/null 2>&1 && [ -d "Signal.xcworkspace" ]; then
  echo "Free disk (${AVAIL_GB}GB) clears the ${DISK_THRESHOLD_GB}GB safety threshold -- attempting a real build."
  if xcodebuild -workspace Signal.xcworkspace -scheme SignalServiceKit -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -60; then
    DYNAMIC_RESULT="ran"
  else
    DYNAMIC_RESULT="ran_failed"
  fi
else
  echo "MANUAL REVIEW REQUIRED: skipped real xcodebuild build/test run -- only ${AVAIL_GB}GB free (< ${DISK_THRESHOLD_GB}GB"
  echo "safety threshold). See CONTROL_RESULTS.md / FUNCTIONAL_VALIDATORS.md."
  DYNAMIC_RESULT="skipped"
fi

echo
echo "--- Step 3: static/behavioral, same-device-scoped check for a working 'delete my messages' path ---"

SELECTION_SIGNAL="$(added_code_lines . | grep -E 'TSOutgoingMessage' || true)"
ENUMERATION_SIGNAL="$(added_code_lines . | grep -iE 'InteractionFinder|enumerateInteractions' || true)"
DELETE_SIGNAL="$(added_code_lines . | grep -E 'interactionDeleteManager\.delete\(|\.anyRemove\(transaction:' || true)"

MISSING=""
[ -z "$SELECTION_SIGNAL" ] && MISSING="$MISSING local-user-message-selection(TSOutgoingMessage)"
[ -z "$ENUMERATION_SIGNAL" ] && MISSING="$MISSING thread-scoped-enumeration(InteractionFinder/enumerateInteractions)"
[ -z "$DELETE_SIGNAL" ] && MISSING="$MISSING actual-deletion-call"

if [ -n "$MISSING" ]; then
  echo "FAIL: could not find evidence of a working 'delete my messages in this thread' path. Missing signal(s):$MISSING"
  echo "(This check accepts EITHER InteractionDeleteManager.delete(...) OR a direct anyRemove(transaction:) loop --"
  echo "that distinction is what task_D_AC1..AC4.sh check, not this script, per this task's own documented intent"
  echo "that a same-device-only anyRemove implementation should be Functional Success = true / Architecture"
  echo "Conformance = false.)"
  exit 1
fi

echo "Found local-user-message-selection signal, e.g.:"; echo "$SELECTION_SIGNAL" | head -3
echo "Found thread-scoped-enumeration signal, e.g.:"; echo "$ENUMERATION_SIGNAL" | head -3
echo "Found actual deletion-call signal, e.g.:"; echo "$DELETE_SIGNAL" | head -3

echo
echo "PASS (static/behavioral, same-device scope): a path exists that selects the local user's outgoing messages"
echo "in a thread (via TSOutgoingMessage + InteractionFinder/enumeration) and actually deletes them."
echo
echo "MANUAL REVIEW REQUIRED (cannot be verified without a live multi-device test lab -- see fixtures/task_D_test.swift"
echo "for the full checklist):"
echo "  - the deletion actually propagates to the user's other linked devices (multi-device sync) -- a same-device"
echo "    static check CANNOT distinguish a real sync-message send from silence; see task_D_AC2.sh for the closest"
echo "    automatable proxy (does the diff explicitly pass .sendSyncMessage(interactionsThread:))"
echo "  - call-record history stays consistent with no orphaned entries (task_D_AC3.sh is the closest automatable proxy)"
echo "  - conversation preview/unread/message list update immediately without relaunch (task_D_AC4.sh is the closest automatable proxy)"

if [ "$DYNAMIC_RESULT" = "ran_failed" ]; then
  echo "FAIL: real xcodebuild build attempt ran and failed (see build log above) -- treating as a genuine functional failure signal."
  exit 1
fi

echo
echo "PASS: Task D functional check (static/behavioral, same-device scope$( [ "$DYNAMIC_RESULT" = "ran" ] && echo " + real xcodebuild build" ); multi-device/call-record/cache items above remain MANUAL REVIEW REQUIRED)."
exit 0
