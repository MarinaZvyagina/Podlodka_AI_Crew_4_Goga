#!/usr/bin/env bash
# Task A / AC3: Non-voice audio attachments are unaffected — the `.body` case in AutoDownloadPolicy.build must
# still fall through to `.preference(mediaType: .audio)` for audio that is NOT a voice message.
# This is inherently a manual-review judgment call (the exact structure of the branch matters, not just
# keyword presence), but we automate what is greppable and flag the rest for manual review.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

POLICY_FILE="SignalServiceKit/Messages/Attachments/V2/Downloads/AutoDownloadPolicy.swift"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree"
  exit 1
fi

if [ ! -f "$POLICY_FILE" ]; then
  echo "FAIL: $POLICY_FILE not found in repo"
  exit 1
fi

# 1. Confirm the working copy still routes non-voice audio to `.preference(mediaType: .audio)` SOMEWHERE
#    in the .body-handling logic (i.e. this fallback was not deleted).
AUDIO_FALLBACK="$(grep -nE '\.preference\(mediaType:\s*\.audio\)' "$POLICY_FILE" || true)"
if [ -z "$AUDIO_FALLBACK" ]; then
  echo "FAIL: no remaining '.preference(mediaType: .audio)' reference in $POLICY_FILE — the non-voice audio fallback appears to have been removed"
  exit 1
fi

# 2. Confirm removed lines (the '-' side of the diff) did not delete the audio-mime-type gate itself.
DIFF_POLICY="$(git diff -- "$POLICY_FILE")"
REMOVED_AUDIO_GATE="$(echo "$DIFF_POLICY" | grep -E '^-.*isSupportedAudioMimeType' || true)"
ADDED_AUDIO_GATE="$(echo "$DIFF_POLICY" | grep -E '^\+.*isSupportedAudioMimeType' || true)"

if [ -n "$REMOVED_AUDIO_GATE" ] && [ -z "$ADDED_AUDIO_GATE" ]; then
  echo "FAIL: diff removes the audio mime-type gate (isSupportedAudioMimeType) without replacing it"
  exit 1
fi

# 3. If the diff removed the '.preference(mediaType: .audio)' return without an unconditional equivalent
#    being re-added, that's a strong signal that ALL audio (voice or not) was rerouted to the new case
#    (the trap: "All audio, voice message or not, is routed to the new preference case").
REMOVED_AUDIO_PREF="$(echo "$DIFF_POLICY" | grep -E '^-.*\.preference\(mediaType:\s*\.audio\)' || true)"
ADDED_AUDIO_PREF="$(echo "$DIFF_POLICY" | grep -E '^\+.*\.preference\(mediaType:\s*\.audio\)' || true)"
if [ -n "$REMOVED_AUDIO_PREF" ] && [ -z "$ADDED_AUDIO_PREF" ]; then
  echo "FAIL: diff removes the '.preference(mediaType: .audio)' return path and does not re-add an equivalent guarded fallback — likely ALL audio was rerouted to the new voice-message case"
  exit 1
fi

# 3. Sanity check: the new voice-message branch and the .audio fallback should not have been collapsed into
#    a single unconditional route (i.e. grep that '.audio' still appears at all after the diff, and that the
#    voiceMessage-specific case does not appear to swallow ALL audio unconditionally). This is a heuristic;
#    final confirmation requires human reading of the branch structure.
echo "PARTIAL PASS (automated signal only): '.preference(mediaType: .audio)' fallback and mime-type gate still present in $POLICY_FILE."
echo "$AUDIO_FALLBACK"
echo
echo "MANUAL REVIEW REQUIRED: confirm the branch structure is:"
echo "  if renderingFlag == .voiceMessage { route to new preference } else { route to .audio }"
echo "  (as opposed to unconditionally routing ALL audio, voice or not, to the new preference — which would fail this check)."
exit 0
