#!/usr/bin/env bash
# Task C functional validator: message retention cleanup.
#
# Calibration note (see FUNCTIONAL_VALIDATORS.md): this task's own notes_for_positive_negative_control
# explicitly design the negative/trap control (a Timer/lifecycle-driven bolt-on with its own UserDefaults-style
# cursor) to "functionally delete old messages and 'resume' via its own ... cursor, passing a shallow functional
# test" while failing every architecture check (AC1-AC5, which require the real JobRecord/JobRunner/
# JobRunnerFactory/JobQueueRunner/TimeGatedBatch/InteractionDeleteManager framework). This functional check is
# therefore DELIBERATELY implementation-agnostic about job-framework-vs-bolt-on -- that discrimination is
# task_C_AC1..AC5.sh's job, not this script's. This script only asks: "is there a plausible, wired-up retention
# cleanup mechanism at all (preference + cutoff-based deletion + some resumption signal + some trigger)?"
#
# Also note: Task C's required entry point is a PATTERN (JobRecord/JobRunner), not one fixed pre-existing
# symbol name (unlike Tasks A/B) -- see fixtures/task_C_test.swift for why a literal compiled unit test isn't
# feasible here, and why the true dynamic requirements (interruption-resume, sign-out safety, immediate UI
# refresh) are always flagged MANUAL REVIEW REQUIRED regardless of the static verdict.
#
# Usage: task_C_functional.sh [repo_path]  (default: .)
set -uo pipefail
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_C_test.swift"

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

TEST_FILE="SignalServiceKit/tests/Jobs/JobQueueRunnerTest.swift"
MARK_BEGIN="// === TASK_C_FUNCTIONAL_VALIDATOR_INJECTED_BEGIN ==="
MARK_END="// === TASK_C_FUNCTIONAL_VALIDATOR_INJECTED_END ==="
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

echo "--- Step 1: inject fixture (documentation/checklist -- see fixtures/task_C_test.swift) + swiftc -parse ---"
if [ -f "$TEST_FILE" ]; then
  { printf '\n%s\n' "$MARK_BEGIN"; cat "$FIXTURE"; printf '%s\n' "$MARK_END"; } >> "$TEST_FILE"
  INJECTED=1
  if command -v swiftc >/dev/null 2>&1; then
    if swiftc -parse "$TEST_FILE" >/tmp/task_C_swiftc_parse.log 2>&1; then
      echo "swiftc -parse: OK -- $TEST_FILE (fixture is comment-only documentation; this mainly confirms no file corruption)"
    else
      if grep -qi "expected \|expression\|unterminated\|extraneous\|consecutive statements" /tmp/task_C_swiftc_parse.log; then
        echo "FAIL: swiftc -parse found a syntax error in $TEST_FILE after fixture injection:"
        cat /tmp/task_C_swiftc_parse.log
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
  echo "safety threshold). See CONTROL_RESULTS.md / FUNCTIONAL_VALIDATORS.md. Even with disk available, this would"
  echo "only compile the framework -- there is no fixed symbol name to dynamically invoke for this task (see"
  echo "fixtures/task_C_test.swift), so the checklist there always remains MANUAL REVIEW regardless."
  DYNAMIC_RESULT="skipped"
fi

echo
echo "--- Step 3: static/behavioral, framework-agnostic check for a working retention cleanup mechanism ---"

PREF_SIGNAL="$(added_code_lines . | grep -iE 'retention|autoDelete|autoExpire' || true)"
CUTOFF_SIGNAL="$(added_code_lines . | grep -iE 'cutoff|olderThan|receivedAtTimestamp *[<>]|timestamp *[<>]' || true)"
DELETE_SIGNAL="$(added_code_lines . | grep -E 'interactionDeleteManager\.delete\(|\.anyRemove\(transaction:' || true)"
RESUME_SIGNAL="$(added_code_lines . | grep -iE 'TimeGatedBatch|anchorMessageRowId|lastProcessedRowId|lastCleanupCompletedThrough|JobRecord|cursor' || true)"
TRIGGER_SIGNAL="$(added_code_lines . | grep -iE 'start\(shouldRestartExistingJobs|applicationDidBecomeActive|OWSApplicationDidBecomeActive|DispatchQueue|Task[[:space:]]*\{|Timer\(' || true)"

MISSING=""
[ -z "$PREF_SIGNAL" ] && MISSING="$MISSING retention-preference"
[ -z "$CUTOFF_SIGNAL" ] && MISSING="$MISSING cutoff-date-computation"
[ -z "$DELETE_SIGNAL" ] && MISSING="$MISSING actual-deletion-call"
[ -z "$RESUME_SIGNAL" ] && MISSING="$MISSING resumption/batching-signal"
[ -z "$TRIGGER_SIGNAL" ] && MISSING="$MISSING launch/trigger-mechanism"

if [ -n "$MISSING" ]; then
  echo "FAIL: could not find evidence of a working retention cleanup mechanism. Missing signal(s):$MISSING"
  echo "(Searched added lines for: retention preference keywords / cutoff-date computation / an actual deletion"
  echo "call (InteractionDeleteManager.delete or anyRemove) / any resumption or batching signal / any launch or"
  echo "lifecycle trigger. This check accepts EITHER the correct job-framework pattern OR a bolt-on"
  echo "Timer+lifecycle-hook equivalent -- that distinction is what task_C_AC1..AC5.sh check, not this script.)"
  exit 1
fi

echo "Found retention-preference signal, e.g.:"; echo "$PREF_SIGNAL" | head -3
echo "Found cutoff-date-computation signal, e.g.:"; echo "$CUTOFF_SIGNAL" | head -3
echo "Found actual deletion-call signal, e.g.:"; echo "$DELETE_SIGNAL" | head -3
echo "Found resumption/batching signal, e.g.:"; echo "$RESUME_SIGNAL" | head -3
echo "Found launch/trigger signal, e.g.:"; echo "$TRIGGER_SIGNAL" | head -3

echo
echo "PASS (static/behavioral): a retention preference, a cutoff-based deletion path, a resumption/batching"
echo "signal, and a launch/trigger mechanism are all present in the diff."
echo
echo "MANUAL REVIEW REQUIRED (cannot be automated without actually running the app -- see fixtures/task_C_test.swift"
echo "for the full checklist):"
echo "  - UI does not freeze during a large cleanup"
echo "  - an interrupted cleanup (force-quit/background/network loss) actually resumes on next launch instead of"
echo "    restarting from scratch or silently stopping"
echo "  - signing out mid-cleanup leaves no half-deleted/corrupted conversation state"
echo "  - conversation previews/unread counts/message lists are correct immediately after a cleanup pass, with no relaunch"
echo "  - turning the window on for the first time applies retroactively to existing history"
echo "  - the window can be changed/disabled at any time"

if [ "$DYNAMIC_RESULT" = "ran_failed" ]; then
  echo "FAIL: real xcodebuild build attempt ran and failed (see build log above) -- treating as a genuine functional failure signal."
  exit 1
fi

echo
echo "PASS: Task C functional check (static/behavioral verification$( [ "$DYNAMIC_RESULT" = "ran" ] && echo " + real xcodebuild build" ); dynamic behaviors above remain MANUAL REVIEW REQUIRED)."
exit 0
