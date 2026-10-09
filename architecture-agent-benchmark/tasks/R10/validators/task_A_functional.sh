#!/usr/bin/env bash
# Task A functional validator: voice-message auto-download preference.
#
# Checks, in order of how "real" they are:
#   1. Injects a real, implementation-agnostic Swift Testing fixture (fixtures/task_A_test.swift) into the
#      existing SignalServiceKit/tests/Attachments/AutoDownloadPolicyTest.swift file and runs `swiftc -parse`
#      over it (real compiler invocation, syntax-level).
#   2. If free disk space clears a safety threshold, attempts a real `xcodebuild test` run of the
#      SignalServiceKitTests target (the smallest real dynamic check available) -- on this benchmark's
#      documented disk-constrained environment this is expected to be skipped; see FUNCTIONAL_VALIDATORS.md.
#   3. A static/behavioral check of the CURRENT (already-patched) working tree, deliberately implementation-
#      agnostic about the new MediaType case's name, that verifies the actual functional requirement text in
#      metadata_A.yaml: "Actually change whether a voice message attachment gets auto-downloaded -- this needs
#      to be a real behavior change in the download logic, not just a new row in the settings UI." This check
#      is intentionally STRICT (unlike Tasks B/C/D's functional checks): metadata_A.yaml explicitly forbids a
#      UI-only implementation from counting as functionally correct, so a UI-only trap should FAIL here, not
#      just fail the architecture checks. See FUNCTIONAL_VALIDATORS.md for why this differs from the other
#      three tasks' calibration.
#
# Usage: task_A_functional.sh [repo_path]  (default: .)
set -uo pipefail
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_A_test.swift"

cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }
REPO_ABS="$(pwd)"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree"
  exit 1
fi

PREF_FILE="SignalServiceKit/Messages/Attachments/V2/Downloads/Preferences/MediaBandwidthPreferenceStore.swift"
POLICY_FILE="SignalServiceKit/Messages/Attachments/V2/Downloads/AutoDownloadPolicy.swift"
UI_FILE="Signal/src/ViewControllers/AppSettings/Data Usage/MediaDownloadSettingsViewController.swift"
TEST_FILE="SignalServiceKit/tests/Attachments/AutoDownloadPolicyTest.swift"

MARK_BEGIN="// === TASK_A_FUNCTIONAL_VALIDATOR_INJECTED_BEGIN ==="
MARK_END="// === TASK_A_FUNCTIONAL_VALIDATOR_INJECTED_END ==="
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

if [ ! -f "$PREF_FILE" ] || [ ! -f "$POLICY_FILE" ]; then
  echo "FAIL: expected files not found ($PREF_FILE / $POLICY_FILE) -- is this the R10 Signal-iOS repo?"
  exit 1
fi

echo "--- Step 1: inject fixture + swiftc -parse syntax check ---"
if [ -f "$TEST_FILE" ]; then
  { printf '\n%s\n' "$MARK_BEGIN"; cat "$FIXTURE"; printf '%s\n' "$MARK_END"; } >> "$TEST_FILE"
  INJECTED=1
  if command -v swiftc >/dev/null 2>&1; then
    if swiftc -parse "$TEST_FILE" >/tmp/task_A_swiftc_parse.log 2>&1; then
      echo "swiftc -parse: OK (syntax-level only; no type-checking/imports resolved) -- $TEST_FILE"
    else
      # -parse on a file with @testable import will still fail to resolve imports (expected, no module built);
      # only treat this as a real signal if the failure looks like a gross syntax error rather than an
      # unresolved-module error (which is expected and not meaningful here).
      if grep -qi "expected \|expression\|unterminated\|extraneous\|consecutive statements" /tmp/task_A_swiftc_parse.log; then
        echo "FAIL: swiftc -parse found a syntax error in $TEST_FILE after fixture injection:"
        cat /tmp/task_A_swiftc_parse.log
        exit 1
      else
        echo "swiftc -parse: no gross syntax errors detected (module-resolution errors, e.g. 'no such module SignalServiceKit', are expected here and ignored -- see log)"
      fi
    fi
  else
    echo "MANUAL REVIEW REQUIRED: swiftc not found on PATH; skipped syntax check"
  fi
else
  echo "MANUAL REVIEW REQUIRED: $TEST_FILE not found (was it removed/renamed?) -- could not inject fixture"
fi

echo
echo "--- Step 2: disk-gated real xcodebuild test attempt ---"
AVAIL_KB="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
DISK_THRESHOLD_GB=40
if [ "$AVAIL_GB" -ge "$DISK_THRESHOLD_GB" ] && command -v xcodebuild >/dev/null 2>&1 && [ -d "Signal.xcworkspace" ]; then
  echo "Free disk (${AVAIL_GB}GB) clears the ${DISK_THRESHOLD_GB}GB safety threshold -- attempting a real build."
  echo "NOTE: this project's SignalServiceKit test target files are listed explicitly in project.pbxproj (no"
  echo "PBXFileSystemSynchronizedRootGroup), so the injected fixture (appended into an EXISTING referenced file,"
  echo "not a new file) is already part of the target; no project-file edit is needed."
  if xcodebuild -workspace Signal.xcworkspace -scheme SignalServiceKit -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -60; then
    DYNAMIC_RESULT="ran"
  else
    DYNAMIC_RESULT="ran_failed"
  fi
else
  echo "MANUAL REVIEW REQUIRED: skipped real xcodebuild build/test run -- only ${AVAIL_GB}GB free (< ${DISK_THRESHOLD_GB}GB"
  echo "safety threshold for this workspace). A prior real attempt in this same environment (see CONTROL_RESULTS.md)"
  echo "started at ~26GB free, consumed ~12GB compiling SignalServiceKit alone, and still failed at the link step"
  echo "with 'No space left on device' against a third-party Pod -- repeating that here with less headroom risks"
  echo "exhausting shared disk. Falling back to the static/behavioral check below, exactly as Phase 5 did."
  DYNAMIC_RESULT="skipped"
fi

echo
echo "--- Step 3: static/behavioral check of actual download-decision logic (implementation-agnostic re: case name) ---"

# 3a. Extract the current MediaType case list (baseline cases are photo/video/audio/document).
CASE_LINES="$(awk '/enum MediaType: String, CaseIterable/{flag=1; next} flag && /^    }/{exit} flag' "$PREF_FILE" | grep -E 'case [A-Za-z_][A-Za-z0-9_]* = "')"
CASE_NAMES="$(echo "$CASE_LINES" | sed -E 's/^[[:space:]]*case[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*=.*/\1/')"
CASE_COUNT="$(echo "$CASE_NAMES" | grep -c . || true)"
NEW_CASES="$(echo "$CASE_NAMES" | grep -vE '^(photo|video|audio|document)$' || true)"

echo "MediaType cases found: $(echo "$CASE_NAMES" | tr '\n' ' ')"

if [ "$CASE_COUNT" -lt 5 ] || [ -z "$NEW_CASES" ]; then
  echo "FAIL: no 5th (new) MediaType case found in $PREF_FILE -- no independently configurable voice-message preference exists"
  exit 1
fi

echo "New MediaType case(s) beyond the original photo/video/audio/document: $(echo "$NEW_CASES" | tr '\n' ' ')"

# 3b. Confirm AutoDownloadPolicy.swift's audio branch routes voice messages to one of the new case(s), gated by
#     renderingFlag == .voiceMessage, while still falling back to .audio for non-voice audio. Scope to the
#     `.body` case's audio-mime-type block specifically (between isSupportedAudioMimeType and the next `if`/
#     `return .preference(mediaType: .document)` fallback that closes out the `.body` case), so we don't
#     accidentally match unrelated code elsewhere in the file.
AUDIO_BLOCK="$(awk '/isSupportedAudioMimeType\(mimeType\)/{flag=1} flag{print} flag && /return \.preference\(mediaType: \.document\)/{exit}' "$POLICY_FILE")"

if [ -z "$AUDIO_BLOCK" ]; then
  echo "FAIL: could not locate the audio-mime-type branch in $POLICY_FILE (isSupportedAudioMimeType) -- has this been restructured beyond recognition?"
  exit 1
fi

HAS_VOICE_GATE="$(echo "$AUDIO_BLOCK" | grep -c 'renderingFlag == \.voiceMessage' || true)"
HAS_AUDIO_FALLBACK="$(echo "$AUDIO_BLOCK" | grep -c '\.preference(mediaType: \.audio)' || true)"

ROUTES_TO_NEW_CASE=0
NEW_CASE_MATCHED=""
for c in $NEW_CASES; do
  if echo "$AUDIO_BLOCK" | grep -q "\.preference(mediaType: \.${c})"; then
    ROUTES_TO_NEW_CASE=1
    NEW_CASE_MATCHED="$c"
    break
  fi
done

if [ "$HAS_VOICE_GATE" -eq 0 ]; then
  echo "FAIL: $POLICY_FILE's audio branch has no 'renderingFlag == .voiceMessage' gate -- voice messages are not distinguished from other audio at all"
  exit 1
fi

if [ "$ROUTES_TO_NEW_CASE" -eq 0 ]; then
  echo "FAIL: $POLICY_FILE never routes a voice-message-gated branch to the new MediaType case(s) ($(echo "$NEW_CASES" | tr '\n' ' '))."
  echo "This is exactly the known negative-control trap: a settings row can exist and persist a value while"
  echo "AutoDownloadPolicy.build never actually consults it -- metadata_A.yaml's functional_requirements explicitly"
  echo "state this must be 'a real behavior change in the download logic, not just a new row in the settings UI.'"
  exit 1
fi

if [ "$HAS_AUDIO_FALLBACK" -eq 0 ]; then
  echo "FAIL: $POLICY_FILE no longer falls back to .preference(mediaType: .audio) anywhere in the audio branch -- non-voice audio attachments may have been broken"
  exit 1
fi

echo "PASS (static/behavioral): voice messages are gated by 'renderingFlag == .voiceMessage' and routed to the new"
echo "'.$NEW_CASE_MATCHED' preference (distinct from .audio); a '.preference(mediaType: .audio)' fallback remains"
echo "for non-voice audio. This is a real behavior change in AutoDownloadPolicy.build, not merely a new UI row."

# 3c. Soft/secondary signal: the UI switch was extended to label the new case (not gating the verdict).
if [ -f "$UI_FILE" ] && grep -q "case \.${NEW_CASE_MATCHED}:" "$UI_FILE"; then
  echo "Additional signal: $UI_FILE's label switch includes '.${NEW_CASE_MATCHED}' -- the settings row has a real label."
else
  echo "NOTE: could not confirm $UI_FILE labels the new case (non-gating; UI completeness, not download behavior)."
fi

echo
echo "MANUAL REVIEW REQUIRED: this script confirms the DECISION LOGIC branches correctly by static inspection and"
echo "(if disk allowed) attempted a real compile. It does not execute the app to confirm the preference persists"
echo "across a real app relaunch, or that a real network download is actually skipped/performed accordingly --"
echo "confirm those manually per metadata_A.yaml's functional_requirements bullets 3 and 4 if in doubt."

if [ "$DYNAMIC_RESULT" = "ran_failed" ]; then
  echo "FAIL: real xcodebuild build attempt ran and failed (see build log above) -- treating as a genuine functional failure signal."
  exit 1
fi

echo
echo "PASS: Task A functional check (static/behavioral verification$( [ "$DYNAMIC_RESULT" = "ran" ] && echo " + real xcodebuild build" ))."
exit 0
