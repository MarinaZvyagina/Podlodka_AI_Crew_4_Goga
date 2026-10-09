#!/usr/bin/env bash
# R08 Task C (thumbnail cache cleanup) — AC3
# "Call/battery gating reuses the existing Constraint implementations rather than
# hand-rolled device-state polling inside the work itself."
#
# Method: grep -n 'NotInCallConstraint|BatteryNotLowConstraint|addConstraint' in the new
# Job subclass's Parameters.Builder() construction; separately grep new files for
# 'TelephonyManager|BatteryManager|CALL_STATE' as a red flag for hand-rolled checks
# duplicating existing constraints.
#
# Usage: task_C_AC3.sh [repo_dir] [base_ref]
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

ALL_NEW_FILES=$(git diff --name-only --diff-filter=A "$BASE_REF" --)

NEW_JOB_FILES=""
for f in $ALL_NEW_FILES; do
  case "$f" in
    app/src/main/java/org/thoughtcrime/securesms/jobs/*)
      [ -f "$f" ] && grep -qE 'extends Job\b|: *Job\(' "$f" && NEW_JOB_FILES="$NEW_JOB_FILES $f"
      ;;
  esac
done

if [ -z "$NEW_JOB_FILES" ]; then
  echo "FAIL: AC3 — no new Job subclass found (see AC1)."
  exit 1
fi

CONSTRAINT_OK=1
for f in $NEW_JOB_FILES; do
  HIT=$(grep -n 'NotInCallConstraint\|BatteryNotLowConstraint\|addConstraint' "$f")
  echo "Constraint references in $f:"
  echo "${HIT:-  none}"
  if [ -z "$HIT" ] || ! echo "$HIT" | grep -q 'NotInCallConstraint' || ! echo "$HIT" | grep -q 'BatteryNotLowConstraint'; then
    CONSTRAINT_OK=0
  fi
done

RED_FLAG_HITS=""
for f in $ALL_NEW_FILES; do
  [ -f "$f" ] || continue
  HIT=$(grep -n 'TelephonyManager\|BatteryManager\|CALL_STATE' "$f")
  if [ -n "$HIT" ]; then
    RED_FLAG_HITS="$RED_FLAG_HITS\n--- $f ---\n$HIT"
  fi
done

if [ -n "$RED_FLAG_HITS" ]; then
  echo "FAIL: AC3 — hand-rolled device-state polling found (TelephonyManager/BatteryManager/CALL_STATE), duplicating existing constraints:"
  echo -e "$RED_FLAG_HITS"
  exit 1
fi

if [ "$CONSTRAINT_OK" -eq 1 ]; then
  echo "PASS: AC3 — new Job declares both NotInCallConstraint and BatteryNotLowConstraint via addConstraint, with no hand-rolled polling found."
  exit 0
else
  echo "FAIL: AC3 — new Job subclass does not declare both NotInCallConstraint and BatteryNotLowConstraint."
  exit 1
fi
