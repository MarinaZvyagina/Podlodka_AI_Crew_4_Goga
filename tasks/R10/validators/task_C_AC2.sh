#!/usr/bin/env bash
# Task C / AC2: A JobRunner + JobRunnerFactory pair drives the actual deletion work, wired into a JobQueueRunner.
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

DIFF_JOBS="$(safe_diff SignalServiceKit/Jobs/)"

if [ -z "$DIFF_JOBS" ]; then
  echo "FAIL: no changes under SignalServiceKit/Jobs/ (nothing to check)"
  exit 1
fi

FAIL=0

RUNNER_CONFORMANCE="$(echo "$DIFF_JOBS" | grep -E '^\+.*func\s+runJobAttempt\s*\(' || true)"
FINISH_CONFORMANCE="$(echo "$DIFF_JOBS" | grep -E '^\+.*func\s+didFinishJob\s*\(' || true)"
FACTORY_CONFORMANCE="$(echo "$DIFF_JOBS" | grep -E '^\+.*func\s+buildRunner\s*\(' || true)"
JOBQUEUERUNNER_WIRED="$(echo "$DIFF_JOBS" | grep -E '^\+.*JobQueueRunner\s*[<(]' || true)"

if [ -z "$RUNNER_CONFORMANCE" ]; then
  echo "FAIL: no new 'func runJobAttempt(' found in SignalServiceKit/Jobs/ diff"
  FAIL=1
fi
if [ -z "$FINISH_CONFORMANCE" ]; then
  echo "FAIL: no new 'func didFinishJob(' found in SignalServiceKit/Jobs/ diff"
  FAIL=1
fi
if [ -z "$FACTORY_CONFORMANCE" ]; then
  echo "FAIL: no new 'func buildRunner(' found in SignalServiceKit/Jobs/ diff"
  FAIL=1
fi
if [ -z "$JOBQUEUERUNNER_WIRED" ]; then
  echo "FAIL: no new JobQueueRunner(...) construction found in SignalServiceKit/Jobs/ diff"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: new runJobAttempt/didFinishJob (JobRunner) and buildRunner (JobRunnerFactory) conformances found, wired into a new JobQueueRunner construction."
exit 0
