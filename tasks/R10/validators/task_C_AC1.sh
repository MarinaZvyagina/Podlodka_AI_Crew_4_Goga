#!/usr/bin/env bash
# Task C / AC1: A new JobRecord subclass and JobRecordType case were added for this feature.
set -uo pipefail
REPO="${1:-.}"
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
safe_new_files() {
  git diff --diff-filter=A --name-only -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null
}
safe_changed_files() {
  git diff --name-only -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null
}

JOB_RECORD_BASE="SignalServiceKit/Jobs/JobRecords/JobRecord.swift"

FAIL=0

NEW_JOBRECORD_FILES="$(safe_new_files SignalServiceKit/Jobs/JobRecords/ || true)"
NEW_SUBCLASS=""
for f in $NEW_JOBRECORD_FILES; do
  if [ -f "$f" ]; then
    hit="$(grep -nE 'class\s+\w+\s*:\s*JobRecord\b' "$f" || true)"
    if [ -n "$hit" ]; then
      NEW_SUBCLASS="$NEW_SUBCLASS
$f: $hit"
    fi
  fi
done
CHANGED_JOBS_FILES="$(safe_changed_files SignalServiceKit/Jobs/ || true)"
for f in $CHANGED_JOBS_FILES; do
  d="$(safe_diff "$f" 2>/dev/null || true)"
  hit="$(echo "$d" | grep -E '^\+\s*(public |final )*class\s+\w+\s*:\s*JobRecord\b' || true)"
  if [ -n "$hit" ]; then
    NEW_SUBCLASS="$NEW_SUBCLASS
$f: $hit"
  fi
done

if [ -z "$NEW_SUBCLASS" ]; then
  echo "FAIL: no new class inheriting JobRecord found under SignalServiceKit/Jobs/"
  FAIL=1
else
  echo "Found new JobRecord subclass(es):$NEW_SUBCLASS"
fi

DIFF_BASE="$(safe_diff "$JOB_RECORD_BASE")"
NEW_CASE="$(echo "$DIFF_BASE" | grep -E '^\+\s*case\s+\w+' || true)"
if [ -z "$NEW_CASE" ]; then
  echo "FAIL: no new 'case' added to JobRecordType enum in $JOB_RECORD_BASE"
  FAIL=1
else
  echo "Found new JobRecordType case(s):"
  echo "$NEW_CASE"
fi

# The two exhaustive switches (jobRecordLabel and concreteType(forRecordType:)) don't repeat the words
# "jobRecordLabel"/"concreteType" on every case line (those are the enclosing function/property names, stated
# once). Instead, verify the new case identifier itself was added multiple times in JobRecord.swift: once in
# the `enum JobRecordType` declaration, and once in each of the two switches that must exhaustively handle it
# (the compiler enforces this, so a correct implementation touches the identifier 3 times; a diff that only
# adds the enum case but forgets the switches would touch it only once).
NEW_CASE_NAME="$(echo "$NEW_CASE" | head -1 | sed -E 's/^\+[[:space:]]*case[[:space:]]+([A-Za-z0-9_]+).*/\1/')"
if [ -n "$NEW_CASE_NAME" ]; then
  OCCURRENCE_COUNT="$(echo "$DIFF_BASE" | grep -E '^\+' | grep -c "\\.${NEW_CASE_NAME}\\b\|case ${NEW_CASE_NAME}\\b" || true)"
  if [ "$OCCURRENCE_COUNT" -lt 3 ]; then
    echo "FAIL: new JobRecordType case '.$NEW_CASE_NAME' only appears $OCCURRENCE_COUNT time(s) as an added line in JobRecord.swift (expected >= 3: the enum declaration, the jobRecordLabel switch, and the concreteType(forRecordType:) switch) — the exhaustive switches may not have been extended"
    FAIL=1
  fi
else
  echo "FAIL: could not extract new case name from JobRecordType diff"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: new JobRecord subclass, new JobRecordType case, and updated concreteType/jobRecordLabel switches all found."
exit 0
