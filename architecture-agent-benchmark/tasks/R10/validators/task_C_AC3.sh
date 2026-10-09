#!/usr/bin/env bash
# Task C / AC3: The cleanup is NOT implemented as a parallel bolt-on scheduling mechanism (Timer/Task.detached/
# app-lifecycle notification hook + hand-rolled UserDefaults cursor) instead of the job framework.
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

DIFF_ALL="$(safe_diff .)"

if [ -z "$DIFF_ALL" ]; then
  echo "FAIL: no working-tree changes found (nothing to check)"
  exit 1
fi

FAIL=0

# Exclude added lines that are pure comments/doc-comments (e.g. `+    // some explanation`) from the pattern
# matches below, since referencing these anti-pattern names in an explanatory comment (contrasting the correct
# approach with what NOT to do) is not itself a violation.
CODE_ONLY_DIFF="$(echo "$DIFF_ALL" | grep -vE '^\+[[:space:]]*(//|\*)')"

BOLT_ON_TIMER="$(echo "$CODE_ONLY_DIFF" | grep -E '^\+.*(Timer\(|DispatchQueue\.main\.asyncAfter|Task\.detached)' || true)"
LIFECYCLE_HOOK="$(echo "$CODE_ONLY_DIFF" | grep -E '^\+.*(applicationDidBecomeActive|OWSApplicationDidBecomeActive|didBecomeActiveNotification)' || true)"
USERDEFAULTS_CURSOR="$(echo "$CODE_ONLY_DIFF" | grep -iE '^\+.*(UserDefaults.*(lastDeleted|cursor|resumeFrom|processedThrough))' || true)"

if [ -n "$BOLT_ON_TIMER" ]; then
  echo "FAIL: diff adds Timer(/DispatchQueue.main.asyncAfter/Task.detached, a bolt-on scheduling primitive:"
  echo "$BOLT_ON_TIMER"
  FAIL=1
fi

if [ -n "$LIFECYCLE_HOOK" ]; then
  echo "FAIL: diff adds a new app-lifecycle notification hook (applicationDidBecomeActive/OWSApplicationDidBecomeActive) apparently driving the cleanup directly:"
  echo "$LIFECYCLE_HOOK"
  FAIL=1
fi

if [ -n "$USERDEFAULTS_CURSOR" ]; then
  echo "FAIL: diff stores a hand-rolled resume cursor in UserDefaults/KV-store instead of a JobRecord field:"
  echo "$USERDEFAULTS_CURSOR"
  FAIL=1
fi

START_PATTERN="$(echo "$DIFF_ALL" | grep -E '^\+.*start\(shouldRestartExistingJobs:' || true)"
if [ -z "$START_PATTERN" ]; then
  echo "NOTE: diff does not show a new 'start(shouldRestartExistingJobs:' call — MANUAL REVIEW REQUIRED to confirm the new job queue is (re)started via the standard JobQueueRunner.start pattern at app launch (this file may live outside the diffed path, e.g. AppSetup/SignalApp bootstrap)."
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: no bolt-on Timer/lifecycle-hook/UserDefaults-cursor scheduling pattern detected."
exit 0
