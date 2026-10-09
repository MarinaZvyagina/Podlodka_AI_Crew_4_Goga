#!/usr/bin/env bash
# R08 Task C (orphaned thumbnail cache cleanup job) — FUNCTIONAL validator
#
# Unlike Tasks A/B/D, this task's required_existing_abstractions are the *Job framework itself*
# (Job/Job.Factory, JobManagerFactories, NotInCallConstraint, BatteryNotLowConstraint) -- the new
# Job subclass a correct solution adds has no fixed name. So this script:
#
#   1. Diffs the repo against the pinned commit to find a newly-ADDED file under
#      app/src/main/java containing a Job subclass declaration ("class X : Job(" or
#      "class X extends Job"), and extracts its package + class name. No class name is hardcoded.
#   2. Substitutes that into fixtures/task_C_test.kt.template and injects the generated test into
#      the SAME package (so no import is needed for the discovered class), at
#      app/src/test/java/<package path>/FunctionalValidatorGeneratedThumbnailCleanupTest.kt.
#   3. Runs that generated test, which exercises Job registration, constraint attachment, real
#      orphan-file cleanup, and the serialize()/Factory#create resumability round trip, all via the
#      Job base class's own public API (getFactoryKey/run/serialize/getParameters/setContext) so it
#      works for ANY correctly-shaped Job subclass regardless of naming.
#
# Deliberate scope boundary (documented in FUNCTIONAL_VALIDATORS.md): if no new Job subclass is
# found in the diff at all -- e.g. the documented trap shape, a Service/Handler/singleton that
# never subclasses Job -- this script reports FAIL rather than attempting to reverse-engineer an
# arbitrary non-Job mechanism's own private API. metadata_C.yaml's own functional_check_command is
# itself anchored to the Job contract (registration / run-serialize-resume / constraints), and
# architecture_checks AC1 independently and reliably catches that trap shape too.
#
# Usage: task_C_functional.sh [repo_dir] [base_ref]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-.}"
BASE_REF="${2:-80dfcfb4bd96efa5f2c1ed16f4407fea33affacd}"
TEMPLATE="$SCRIPT_DIR/fixtures/task_C_test.kt.template"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }
REPO_DIR="$(pwd)"

if [ ! -f "$TEMPLATE" ]; then
  echo "FAIL: fixture template not found at $TEMPLATE"
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi

if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout."
  exit 1
fi

if [ ! -x "./gradlew" ]; then
  echo "MANUAL REVIEW REQUIRED: ./gradlew not found/executable in '$REPO_DIR'."
  exit 1
fi

# --- Step 1: discover the new Job subclass, if any, among files ADDED relative to the pinned commit.
# "Added" here covers both (a) files committed on top of the pinned commit (git diff --diff-filter=A
# sees these) and (b) files just sitting untracked in the working tree (the common case when a
# candidate diff was applied via `git apply` without a commit) -- git diff alone never reports
# untracked files, so both sources are unioned.
COMMITTED_ADDED=$(git diff --diff-filter=A --name-only "$BASE_REF" -- app/src/main/java 2>/dev/null)
UNTRACKED_ADDED=$(git status --porcelain -- app/src/main/java 2>/dev/null | grep -E '^\?\?' | sed -E 's/^\?\? //')
# Untracked directories are reported with a trailing slash by `git status`; expand them to files.
EXPANDED_UNTRACKED=""
for p in $UNTRACKED_ADDED; do
  if [ -d "$p" ]; then
    EXPANDED_UNTRACKED="${EXPANDED_UNTRACKED}
$(find "$p" -type f)"
  else
    EXPANDED_UNTRACKED="${EXPANDED_UNTRACKED}
$p"
  fi
done
ADDED_FILES=$(printf '%s\n%s\n' "$COMMITTED_ADDED" "$EXPANDED_UNTRACKED" | grep -E '\.(kt|java)$' | sort -u)

JOB_FILE=""
JOB_PACKAGE=""
JOB_CLASS=""
CANDIDATES_FOUND=""

for f in $ADDED_FILES; do
  [ -f "$f" ] || continue
  # The Kotlin convention this codebase uses for multi-constructor Jobs (see AnalyzeDatabaseJob.kt)
  # puts the superclass call on its own line, well after "class X private constructor(":
  #   class ThumbnailCleanupJob private constructor(
  #     parameters: Parameters,
  #     ...
  #   ) : Job(parameters) {
  # so superclass and class-name can be many lines apart. Find the superclass-declaration line
  # first (": Job(" or Java's "extends Job\b"), then look upward for the nearest preceding
  # "class X" declaration.
  SUPER_LINE=$(grep -nE '(^|[^A-Za-z0-9_])(:[[:space:]]*Job\(|extends[[:space:]]+Job\b)' "$f" | head -1 | cut -d: -f1)
  if [ -n "$SUPER_LINE" ]; then
    START=$((SUPER_LINE - 20))
    [ "$START" -lt 1 ] && START=1
    CLASS_NAME=$(sed -n "${START},${SUPER_LINE}p" "$f" | grep -oE '(^|[^A-Za-z0-9_])class[[:space:]]+[A-Za-z0-9_]+' | tail -1 | grep -oE '[A-Za-z0-9_]+$')
    PACKAGE_NAME=$(grep -m1 -E '^package ' "$f" | sed -E 's/^package[[:space:]]+//; s/;$//')
    if [ -n "$CLASS_NAME" ] && [ -n "$PACKAGE_NAME" ]; then
      CANDIDATES_FOUND="${CANDIDATES_FOUND}${f} -> ${PACKAGE_NAME}.${CLASS_NAME}\n"
      if [ -z "$JOB_FILE" ]; then
        JOB_FILE="$f"
        JOB_PACKAGE="$PACKAGE_NAME"
        JOB_CLASS="$CLASS_NAME"
      fi
    fi
  fi
done

if [ -z "$JOB_FILE" ]; then
  echo "FAIL: R08-TC functional — no new Job subclass (a file added under app/src/main/java containing"
  echo "'class X : Job(' or 'class X extends Job') was found in the diff against pinned commit $BASE_REF."
  echo "This task requires the cleanup routine to be implemented as a Job subclass registered with"
  echo "JobManagerFactories (see required_existing_abstractions in metadata_C.yaml). A mechanism built"
  echo "some other way (Service, Handler/Thread loop, standalone WorkManager usage, an Application-level"
  echo "singleton, etc. -- the documented trap shape) does not satisfy this, and this script does not"
  echo "attempt to reverse-engineer an arbitrary non-Job mechanism's private API to test it anyway."
  echo "See FUNCTIONAL_VALIDATORS.md for the full rationale."
  exit 1
fi

echo "Discovered candidate Job subclass: ${JOB_PACKAGE}.${JOB_CLASS}  (file: $JOB_FILE)"
if [ "$(printf "%b" "$CANDIDATES_FOUND" | grep -c '.')" -gt 1 ]; then
  echo "Note: more than one file matched the Job-subclass pattern; using the first one found. All matches:"
  printf "%b" "$CANDIDATES_FOUND"
fi

# --- Step 2: generate the test into the same package as the discovered class.
PACKAGE_PATH="$(echo "$JOB_PACKAGE" | tr '.' '/')"
TARGET_REL="app/src/test/java/${PACKAGE_PATH}/FunctionalValidatorGeneratedThumbnailCleanupTest.kt"
TARGET="$REPO_DIR/$TARGET_REL"
BACKUP=""
CLEANUP_DONE=0

cleanup() {
  [ "$CLEANUP_DONE" -eq 1 ] && return
  CLEANUP_DONE=1
  if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
    mv -f "$BACKUP" "$TARGET"
    echo "Cleanup: restored pre-existing $TARGET_REL"
  elif [ -f "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Cleanup: removed generated $TARGET_REL"
  fi
}
trap cleanup EXIT

mkdir -p "$(dirname "$TARGET")"
if [ -f "$TARGET" ]; then
  BACKUP="${TARGET}.functional-validator.bak"
  cp -f "$TARGET" "$BACKUP"
  echo "Note: a file already existed at $TARGET_REL; backing it up and overwriting with the generated fixture for this check."
fi

sed -e "s/__PACKAGE__/${JOB_PACKAGE}/g" -e "s/__CLASS__/${JOB_CLASS}/g" "$TEMPLATE" > "$TARGET"
echo "Generated fixture -> $TARGET_REL"

TEST_CLASS_FQCN="${JOB_PACKAGE}.FunctionalValidatorGeneratedThumbnailCleanupTest"
echo "Running: ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests \"${TEST_CLASS_FQCN}\""
if ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "${TEST_CLASS_FQCN}" --console=plain; then
  echo "PASS: R08-TC functional — ${JOB_PACKAGE}.${JOB_CLASS} is registered in JobManagerFactories, declares NotInCallConstraint + BatteryNotLowConstraint, deletes orphaned files while preserving referenced ones, and survives a serialize()/Factory#create resume round trip."
  exit 0
else
  GRADLE_EXIT=$?
  echo "FAIL: R08-TC functional — ${JOB_PACKAGE}.${JOB_CLASS} did not pass all checks (gradle exit $GRADLE_EXIT). This can mean: (a) not registered in JobManagerFactories, (b) missing NotInCallConstraint/BatteryNotLowConstraint, (c) it does not actually delete orphaned files / does delete referenced ones, (d) it does not resume correctly via serialize()/Factory#create, or (e) a build/compile error (e.g. no public no-arg constructor) — inspect Gradle output above to distinguish these."
  exit 1
fi
