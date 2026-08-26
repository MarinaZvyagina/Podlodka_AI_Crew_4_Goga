#!/usr/bin/env bash
# R08 Task B (per-attachment full-quality override) — AC4
# "AttachmentCompressionJob remains the single place that decides whether to compress; no
# duplicate compression-decision logic is added elsewhere."
#
# Method: grep -n 'compress|Transcod|skipTransform' across new/changed files outside
# app/src/main/java/org/thoughtcrime/securesms/jobs/AttachmentCompressionJob.java.
#
# Usage: task_B_AC4.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-441ba42c3f3175476a1f54eba8e72d8d6d304db7}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout."
  exit 1
fi

EXCLUDE_FILE="app/src/main/java/org/thoughtcrime/securesms/jobs/AttachmentCompressionJob.java"
CHANGED_FILES=$(git diff --name-only "$BASE_REF" -- | grep -v "^${EXCLUDE_FILE}\$")

RED_FLAG_HITS=""
for f in $CHANGED_FILES; do
  [ -f "$f" ] || continue
  # Look only at newly-added lines that perform an actual compression/transcode DECISION
  # (a plain reference to skipTransform when *reading* the flag upstream, e.g. to set it,
  # is expected and fine — the red flag is re-implementing "if compress/transcode" logic).
  HIT=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E 'compress\(|Transcod|MediaCompress|shouldCompress|shouldTranscode')
  if [ -n "$HIT" ]; then
    RED_FLAG_HITS="$RED_FLAG_HITS\n--- $f ---\n$HIT"
  fi
done

if [ -n "$RED_FLAG_HITS" ]; then
  echo "FAIL: AC4 — possible duplicate compression-decision logic found outside AttachmentCompressionJob.java:"
  echo -e "$RED_FLAG_HITS"
  echo "MANUAL REVIEW REQUIRED to confirm these are not innocuous matches (e.g. comments, unrelated compression of a different asset type)."
  exit 1
fi

echo "PASS: AC4 — no new compression/transcode-decision logic found outside AttachmentCompressionJob.java."
exit 0
