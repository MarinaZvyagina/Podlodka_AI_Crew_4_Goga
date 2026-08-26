#!/usr/bin/env bash
# AC3: Status visibility reuses lib/promscrape/targetstatus.go (tsmGlobal / the existing
# droppedTargets mechanism) rather than a new tracking structure, and is rendered through the
# existing WriteHumanReadableTargetsStatus / WriteAPIV1Targets handlers rather than a new
# bespoke HTTP endpoint in app/vmagent/main.go.
#
# Method (per metadata_B.yaml AC3): manual review of the diff to targetstatus.go /
# WriteHumanReadableTargetsStatus / WriteAPIV1Targets vs. any newly introduced status-tracking
# types. This script automates what it reasonably can (new HTTP routes / new tracking
# maps-or-structs added in app/vmagent/main.go; whether targetstatus.go's diff touches the known
# existing abstractions) and otherwise defers to manual review.
#
# Usage: task_B_AC3.sh [REPO_PATH]
set -u

REPO="${1:-.}"
TARGETSTATUS_GO="$REPO/lib/promscrape/targetstatus.go"
VMAGENT_MAIN="$REPO/app/vmagent/main.go"

if [ ! -f "$TARGETSTATUS_GO" ] || [ ! -f "$VMAGENT_MAIN" ]; then
  echo "FAIL: expected files not found ($TARGETSTATUS_GO / $VMAGENT_MAIN); does not look like a VictoriaMetrics checkout"
  exit 1
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: $REPO is not a git working tree; cannot diff against baseline HEAD"
  exit 1
fi

TS_DIFF="$(git -C "$REPO" diff -- lib/promscrape/targetstatus.go lib/promscrape/targetstatus.qtpl lib/promscrape/targetstatus.qtpl.go 2>/dev/null)"
VMAGENT_DIFF="$(git -C "$REPO" diff -- app/vmagent/main.go 2>/dev/null)"

# --- Trap signal 1: a brand-new ad hoc HTTP route/case added directly in app/vmagent/main.go ---
NEW_ROUTE="$(echo "$VMAGENT_DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -E '"(/[A-Za-z0-9_./-]*)"[[:space:]]*:' )"
if [ -n "$NEW_ROUTE" ]; then
  echo "FAIL: app/vmagent/main.go gained new HTTP route case(s) - suggests a bespoke ad hoc endpoint was added instead of reusing WriteHumanReadableTargetsStatus/WriteAPIV1Targets: $(echo "$NEW_ROUTE" | xargs)"
  exit 1
fi

# --- Trap signal 2: a brand-new package-level status-tracking map/struct added in
# app/vmagent/main.go, independent of tsmGlobal/droppedTargets in lib/promscrape ---
NEW_TRACKING_ELSEWHERE="$(echo "$VMAGENT_DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+' \
  | grep -E '^\+[[:space:]]*(var[[:space:]]+[A-Za-z0-9_]+[[:space:]]*(=|\[)|type[[:space:]]+[A-Za-z0-9_]+[[:space:]]+struct)' \
  | grep -iE 'limit|target')"
if [ -n "$NEW_TRACKING_ELSEWHERE" ]; then
  echo "FAIL: app/vmagent/main.go appears to introduce its own status-tracking map/struct, independent of lib/promscrape/targetstatus.go: $(echo "$NEW_TRACKING_ELSEWHERE" | xargs)"
  exit 1
fi

# --- Positive signal: targetstatus.go (or its qtpl templates) was actually extended ---
if [ -z "$TS_DIFF" ]; then
  echo "FAIL: lib/promscrape/targetstatus.go (and its qtpl templates) have no changes; no evidence that existing status tracking/rendering was extended (feature appears unimplemented)"
  exit 1
fi

REUSES_EXISTING="$(echo "$TS_DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+' \
  | grep -iE 'droppedtargets|tsmglobal|jobtargetsstatuses|writeapiv1targets|writehumanreadabletargetsstatus|dropreason|targetdropreason')"
if [ -z "$REUSES_EXISTING" ]; then
  echo "MANUAL REVIEW REQUIRED: lib/promscrape/targetstatus.go changed, but could not automatically confirm the new code reuses tsmGlobal/droppedTargets/jobTargetsStatuses rather than adding a parallel structure - please review the diff manually"
  exit 2
fi

echo "PASS: no new ad hoc HTTP route or independent status-tracking struct found in app/vmagent/main.go; lib/promscrape/targetstatus.go was extended and reuses existing tsmGlobal/droppedTargets-based structures"
exit 0
