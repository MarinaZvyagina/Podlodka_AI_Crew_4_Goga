#!/usr/bin/env bash
# R08 Task C (thumbnail cache cleanup) — AC1
# "Cleanup work is implemented as a Job subclass registered in JobManagerFactories, not as
# a Service/Thread/Handler/WorkManager-direct loop."
#
# Method: grep -n 'extends Job\b|: Job(' among new files under
# app/src/main/java/org/thoughtcrime/securesms/jobs/; check JobManagerFactories.java diff
# for a new job-key -> Factory entry in its registration map; separately grep all
# new/changed files for 'extends Service|new Thread(|new Handler(|WorkManager|AlarmManager'
# as red flags for a parallel mechanism.
#
# Usage: task_C_AC1.sh [repo_dir] [base_ref]
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

NEW_JOB_FILES=$(git diff --name-only --diff-filter=A "$BASE_REF" -- app/src/main/java/org/thoughtcrime/securesms/jobs/)

JOB_SUBCLASS_FOUND=""
for f in $NEW_JOB_FILES; do
  [ -f "$f" ] || continue
  if grep -qE 'extends Job\b|: *Job\(' "$f"; then
    JOB_SUBCLASS_FOUND="$JOB_SUBCLASS_FOUND $f"
  fi
done

# Registrations in JobManagerFactories.java are bare `put(KEY, new Factory())` statements inside a
# `new HashMap<>() {{ ... }}` double-brace initializer (no leading receiver/dot), so match `put(`
# rather than `.put(` — the latter never matches this file's actual registration style.
FACTORY_DIFF=$(git diff "$BASE_REF" -- app/src/main/java/org/thoughtcrime/securesms/jobs/JobManagerFactories.java | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E '(^|[^A-Za-z0-9_.])put\(')

ALL_CHANGED=$(git diff --name-only --diff-filter=ACM "$BASE_REF" --)
RED_FLAGS=""
for f in $ALL_CHANGED; do
  [ -f "$f" ] || continue
  HIT=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E 'extends Service|new Thread\(|new Handler\(|WorkManager|AlarmManager')
  if [ -n "$HIT" ]; then
    RED_FLAGS="$RED_FLAGS\n--- $f ---\n$HIT"
  fi
done

echo "New files under jobs/ that extend Job: ${JOB_SUBCLASS_FOUND:-none}"
echo "New JobManagerFactories.java .put(...) registrations added:"
echo "${FACTORY_DIFF:-  none}"
if [ -n "$RED_FLAGS" ]; then
  echo "Red-flag parallel-mechanism references found:"
  echo -e "$RED_FLAGS"
fi

if [ -n "$RED_FLAGS" ]; then
  echo "FAIL: AC1 — a Service/Thread/Handler/WorkManager/AlarmManager reference was found, suggesting a parallel scheduling mechanism instead of the Job framework."
  exit 1
fi

if [ -n "$JOB_SUBCLASS_FOUND" ] && [ -n "$FACTORY_DIFF" ]; then
  echo "PASS: AC1 — a new Job subclass was added and registered in JobManagerFactories.java, with no red-flag parallel mechanism."
  exit 0
else
  echo "FAIL: AC1 — missing a new Job subclass and/or a new JobManagerFactories.java registration."
  exit 1
fi
