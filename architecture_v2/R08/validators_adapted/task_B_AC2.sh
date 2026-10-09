#!/usr/bin/env bash
# R08 Task B (per-attachment full-quality override) — AC2
# "The new capability is exposed through the existing Provider/Repository interface
# pattern, not a new bespoke singleton inside the feature module."
#
# Method (per metadata): manual review of the diff in feature/media-send/src/main/java/
# org/signal/mediasend/{MediaSendDependencies.kt, preupload/PreUploadRepository.kt,
# MediaSendRepository.kt} versus any new standalone static holder class introduced
# elsewhere in the feature module. This is inherently a judgment call, so this script
# automates what it reasonably can (did the Provider/Repository interfaces change? do any
# new files in the feature module declare a suspicious standalone `object` singleton
# reaching for Android job/file APIs directly?) and prints MANUAL REVIEW REQUIRED with the
# supporting evidence rather than faking a verdict.
#
# Usage: task_B_AC2.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-80dfcfb4bd96efa5f2c1ed16f4407fea33affacd}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout."
  exit 1
fi

INTERFACE_FILES="feature/media-send/src/main/java/org/signal/mediasend/MediaSendDependencies.kt \
feature/media-send/src/main/java/org/signal/mediasend/preupload/PreUploadRepository.kt \
feature/media-send/src/main/java/org/signal/mediasend/MediaSendRepository.kt"

CHANGED_INTERFACE_FILES=$(git diff --name-only "$BASE_REF" -- $INTERFACE_FILES)

echo "Provider/Repository interface files changed: ${CHANGED_INTERFACE_FILES:-none}"

# Red flag: any newly-added file under feature/media-send declaring a top-level `object`
# (Kotlin singleton) that also touches Android job-scheduling or filesystem APIs directly.
NEW_FEATURE_FILES=$(git diff --name-only --diff-filter=A "$BASE_REF" -- feature/media-send/src/main/java)

RED_FLAG_HITS=""
for f in $NEW_FEATURE_FILES; do
  [ -f "$f" ] || continue
  if grep -qE '^\s*object [A-Za-z]' "$f" && grep -qE 'WorkManager|JobScheduler|java\.io\.File|FileOutputStream|FileInputStream|SharedPreferences' "$f"; then
    RED_FLAG_HITS="$RED_FLAG_HITS $f"
  fi
done

if [ -n "$RED_FLAG_HITS" ]; then
  echo "FAIL: AC2 — new standalone singleton object(s) in feature/media-send reach directly for Android job/file/prefs APIs instead of going through the Provider/Repository interface:"
  echo "$RED_FLAG_HITS"
  exit 1
fi

if [ -n "$CHANGED_INTERFACE_FILES" ]; then
  echo "PASS (heuristic): AC2 — the Provider/Repository interface files changed and no red-flag standalone singleton was found in new feature-module files."
  echo "MANUAL REVIEW REQUIRED to confirm the new interface method(s) are semantically the right shape (e.g. a new preUpload-related method) rather than an unrelated change."
  exit 0
else
  echo "MANUAL REVIEW REQUIRED: none of MediaSendDependencies.kt / PreUploadRepository.kt / MediaSendRepository.kt changed, and no obvious red-flag singleton was found either. This is ambiguous from grep alone — inspect the diff manually to see how the new capability is exposed."
  exit 1
fi
