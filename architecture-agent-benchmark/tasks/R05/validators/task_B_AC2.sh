#!/usr/bin/env bash
# AC2: New flag lives in lib/promscrape, not duplicated/redefined in app/vmagent.
#
# Method (per metadata_B.yaml AC2): grep -rn 'flag\.' app/vmagent/main.go lib/promscrape/*.go
# for the new flag name; expect exactly one flag declaration, inside lib/promscrape.
#
# Usage: task_B_AC2.sh [REPO_PATH]
# Compares the working tree of REPO_PATH against its current HEAD (the pinned baseline commit).
set -u

REPO="${1:-.}"
VMAGENT_MAIN="$REPO/app/vmagent/main.go"

if [ ! -f "$VMAGENT_MAIN" ] || [ ! -d "$REPO/lib/promscrape" ]; then
  echo "FAIL: expected files not found ($VMAGENT_MAIN / $REPO/lib/promscrape); does not look like a VictoriaMetrics checkout"
  exit 1
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: $REPO is not a git working tree; cannot diff against baseline HEAD"
  exit 1
fi

FLAG_DECL_RE='flag\.(Int|Bool|String|Duration|Float64|Int64|Var)\('
# The new flag is expected to concern per-job/per-target scrape limits - use that as a topical
# filter so unrelated flag additions elsewhere don't produce false positives/negatives.
TOPIC_RE='target|job'

ADDED_VMAGENT_FLAGS="$(git -C "$REPO" diff -- app/vmagent/main.go 2>/dev/null \
  | grep -E '^\+' | grep -Ev '^\+\+\+' \
  | grep -E "$FLAG_DECL_RE" | grep -iE "$TOPIC_RE")"

# NOTE: git pathspec globs treat '*' as crossing directory separators (unlike a shell glob), so
# 'lib/promscrape/*.go' would also match lib/promscrape/discovery/kubernetes/kubernetes.go etc.
# The architectural constraint is specifically about lib/promscrape's own flag-declaring files
# (config.go, scraper.go, ...), NOT its discovery/<name> subpackages - so we take the diff over
# the whole lib/promscrape tree and then restrict to files that are direct children of
# lib/promscrape/ (no further '/' in the relative path).
PROMSCRAPE_DIRECT_FILES="$(git -C "$REPO" diff --name-only -- 'lib/promscrape/*.go' 2>/dev/null | grep -E '^lib/promscrape/[^/]+\.go$')"

ADDED_PROMSCRAPE_FLAGS=""
if [ -n "$PROMSCRAPE_DIRECT_FILES" ]; then
  ADDED_PROMSCRAPE_FLAGS="$(git -C "$REPO" diff -- $PROMSCRAPE_DIRECT_FILES 2>/dev/null \
    | grep -E '^\+' | grep -Ev '^\+\+\+' \
    | grep -E "$FLAG_DECL_RE" | grep -iE "$TOPIC_RE")"
fi

if [ -n "$ADDED_VMAGENT_FLAGS" ]; then
  echo "FAIL: app/vmagent/main.go declares its own new target/job-limit flag (must live only in lib/promscrape): $(echo "$ADDED_VMAGENT_FLAGS" | xargs)"
  exit 1
fi

if [ -z "$ADDED_PROMSCRAPE_FLAGS" ]; then
  # Check whether the flag was instead added inside a lib/promscrape/discovery/<name>
  # subpackage - a common trap shape (per-backend flag instead of a shared one in lib/promscrape).
  ADDED_DISCOVERY_FLAGS="$(git -C "$REPO" diff -- 'lib/promscrape/discovery/*/*.go' 2>/dev/null \
    | grep -E '^\+' | grep -Ev '^\+\+\+' \
    | grep -E "$FLAG_DECL_RE" | grep -iE "$TOPIC_RE")"
  if [ -n "$ADDED_DISCOVERY_FLAGS" ]; then
    echo "FAIL: new target/job-limit flag found inside lib/promscrape/discovery/<name> subpackage instead of lib/promscrape itself: $(echo "$ADDED_DISCOVERY_FLAGS" | xargs)"
    exit 1
  fi
  echo "FAIL: no new target/job-limit related flag.* declaration found under lib/promscrape/*.go (feature appears unimplemented, or flag lives elsewhere)"
  exit 1
fi

FLAG_COUNT="$(echo "$ADDED_PROMSCRAPE_FLAGS" | grep -c 'flag\.')"
if [ "$FLAG_COUNT" -ne 1 ]; then
  echo "MANUAL REVIEW REQUIRED: found $FLAG_COUNT new target/job-limit flag declarations in lib/promscrape (expected exactly 1) - please review manually: $(echo "$ADDED_PROMSCRAPE_FLAGS" | xargs)"
  exit 2
fi

echo "PASS: exactly one new target/job-limit flag declared in lib/promscrape, none in app/vmagent/main.go: $(echo "$ADDED_PROMSCRAPE_FLAGS" | xargs)"
exit 0
