#!/usr/bin/env bash
# R08 Task C (thumbnail cache cleanup) — AC2
# "Resumability is implemented via the Job's own serialize()/Factory#create state
# round-trip, matching the AnalyzeDatabaseJob.kt precedent, not via an independent
# persistence mechanism."
#
# Method (per metadata): manual review of the new Job subclass for an overridden
# serialize() that persists a progress marker and a Factory#create that reads it back;
# compare shape to AnalyzeDatabaseJob.kt's lastCompletedTable pattern. This script
# automates a structural heuristic (serialize()/Factory#create/Result.retry present; no
# SharedPreferences/ad hoc table used for progress) and flags MANUAL REVIEW REQUIRED for
# final confirmation of semantic correctness.
#
# Usage: task_C_AC2.sh [repo_dir] [base_ref]
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

NEW_JOB_FILES=$(git diff --name-only --diff-filter=A "$BASE_REF" -- app/src/main/java/org/thoughtcrime/securesms/jobs/)
NEW_JOB_FILES=$(for f in $NEW_JOB_FILES; do [ -f "$f" ] && grep -lE 'extends Job\b|: *Job\(' "$f"; done)

if [ -z "$NEW_JOB_FILES" ]; then
  echo "FAIL: AC2 — no new Job subclass found under app/src/main/java/org/thoughtcrime/securesms/jobs/ (see AC1)."
  exit 1
fi

RESUMABLE_OK=1
for f in $NEW_JOB_FILES; do
  echo "Inspecting $f:"
  HAS_SERIALIZE=$(grep -c 'fun serialize\|serialize()' "$f")
  HAS_RETRY=$(grep -c 'Result\.retry\|Result\.RETRY' "$f")
  HAS_FACTORY_CREATE=$(grep -c 'fun create(\|Factory' "$f")
  echo "  serialize() references: $HAS_SERIALIZE, Result.retry references: $HAS_RETRY, Factory/create references: $HAS_FACTORY_CREATE"
  if [ "$HAS_SERIALIZE" -eq 0 ] || [ "$HAS_RETRY" -eq 0 ] || [ "$HAS_FACTORY_CREATE" -eq 0 ]; then
    RESUMABLE_OK=0
  fi
done

# Red flag: progress tracked via SharedPreferences or a bespoke new DB table instead of
# the job's own serialized JsonJobData.
RED_FLAG_HITS=""
for f in $NEW_JOB_FILES; do
  HIT=$(grep -n 'SharedPreferences\|getSharedPreferences' "$f")
  if [ -n "$HIT" ]; then
    RED_FLAG_HITS="$RED_FLAG_HITS\n--- $f ---\n$HIT"
  fi
done

if [ -n "$RED_FLAG_HITS" ]; then
  echo "FAIL: AC2 — new Job subclass references SharedPreferences for progress tracking instead of serialize()/Factory#create:"
  echo -e "$RED_FLAG_HITS"
  exit 1
fi

if [ "$RESUMABLE_OK" -eq 1 ]; then
  echo "PASS (heuristic): AC2 — new Job subclass(es) contain serialize(), Result.retry, and a Factory/create pattern consistent with AnalyzeDatabaseJob.kt's resumable shape."
  echo "MANUAL REVIEW REQUIRED to confirm serialize() actually persists a meaningful progress marker (e.g. last-checked file id/offset) and Factory#create actually restores and resumes from it, rather than these tokens appearing incidentally."
  exit 0
else
  echo "FAIL: AC2 — new Job subclass is missing one of serialize()/Result.retry/Factory-create, suggesting no real resumability."
  exit 1
fi
