#!/usr/bin/env bash
# AC1: The limit is enforced once, in the shared scrape-work assembly path, not per discovery
# backend.
#
# Method (per metadata_B.yaml AC1): locate where the new limiting logic runs; confirm it is a
# single call site touching cfg.getScrapeWorkGeneric / appendScrapeWorkForTargetLabels (or an
# equivalent single shared function) in lib/promscrape/config.go, not edits spread across
# lib/promscrape/discovery/*/*.go.
#
# Usage: task_B_AC1.sh [REPO_PATH]
# Compares the working tree of REPO_PATH against its current HEAD (the pinned baseline commit),
# so it works against an uncommitted positive/negative control diff.
set -u

REPO="${1:-.}"

if [ ! -f "$REPO/lib/promscrape/config.go" ]; then
  echo "FAIL: $REPO/lib/promscrape/config.go not found; does not look like a VictoriaMetrics checkout"
  exit 1
fi

CONFIG_GO="$REPO/lib/promscrape/config.go"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: $REPO is not a git working tree; cannot diff against baseline HEAD"
  exit 1
fi

# --- Part A: any edits under lib/promscrape/discovery/*/*.go at all? ---
# The architectural constraint forbids per-backend limiting logic scattered across
# lib/promscrape/discovery/<name> packages (that would duplicate the check ~22 times).
DISCOVERY_DIFF_FILES="$(git -C "$REPO" diff --name-only -- 'lib/promscrape/discovery/*/*.go' 2>/dev/null)"
if [ -n "$DISCOVERY_DIFF_FILES" ]; then
  echo "FAIL: changes found under lib/promscrape/discovery/*/*.go (per-backend edits) - expected all target-limit enforcement to live in the shared lib/promscrape/config.go path instead: $(echo "$DISCOVERY_DIFF_FILES" | tr '\n' ' ')"
  exit 1
fi

# --- Part B: does lib/promscrape/config.go actually contain new limiting logic? ---
CONFIG_DIFF="$(git -C "$REPO" diff -- lib/promscrape/config.go 2>/dev/null)"
if [ -z "$CONFIG_DIFF" ]; then
  echo "FAIL: lib/promscrape/config.go has no changes; no shared-path enforcement found (feature appears unimplemented)"
  exit 1
fi

if ! grep -qE 'func \(cfg \*Config\) getScrapeWorkGeneric' "$CONFIG_GO"; then
  echo "FAIL: cfg.getScrapeWorkGeneric not found in $CONFIG_GO (unexpected file shape)"
  exit 1
fi

# Extract the bodies of the three functions that must funnel every *_sd_configs / static_configs
# job through the shared assembly path, and look for an added call to a limiting/truncation
# helper inside (or immediately following, in the same loop) one of them.
# Uses grep -F (fixed string) to locate the starting line number, then a plain (no dynamic
# regex, so no shell/awk escaping pitfalls) awk pass to print from that line to the matching
# top-level closing brace.
extract_func() {
  # $1 = fixed function signature substring, $2 = file
  local sig="$1" file="$2" start
  start="$(grep -nF "$sig" "$file" | head -1 | cut -d: -f1)"
  [ -z "$start" ] && return 0
  awk -v s="$start" 'NR>=s{print; if (/^}/) exit}' "$file"
}

GENERIC_BLOCK="$(extract_func 'func (cfg *Config) getScrapeWorkGeneric' "$CONFIG_GO")"
APPEND_BLOCK="$(extract_func 'func appendScrapeWorkForTargetLabels' "$CONFIG_GO")"
STATIC_BLOCK="$(extract_func 'func (cfg *Config) getStaticScrapeWork' "$CONFIG_GO")"

LIMIT_HINT_RE='truncat|maxtargetsperjob|targetsperjob|targetlimit|max_targets_per_job'

LIMIT_CALL_IN_SHARED_PATH="$(printf '%s\n%s\n%s\n' "$GENERIC_BLOCK" "$APPEND_BLOCK" "$STATIC_BLOCK" | grep -iE "$LIMIT_HINT_RE")"

if [ -z "$LIMIT_CALL_IN_SHARED_PATH" ]; then
  echo "FAIL: no target-limiting/truncation logic found inside getScrapeWorkGeneric / appendScrapeWorkForTargetLabels / getStaticScrapeWork in $CONFIG_GO"
  exit 1
fi

# Sanity check: the limiting logic should be backed by a single shared helper function
# definition in config.go (not, say, several independently-named limiter functions), which
# would suggest duplicated logic rather than one shared enforcement point.
HELPER_FUNC_COUNT="$(grep -cE '^func [A-Za-z0-9_.*() ]*(runcat|imitScrapeWork|imitTargets)' "$CONFIG_GO" || true)"
if [ "${HELPER_FUNC_COUNT:-0}" -gt 3 ]; then
  echo "MANUAL REVIEW REQUIRED: found $HELPER_FUNC_COUNT candidate limiter helper functions in config.go; could not automatically confirm a single shared enforcement point - please review manually"
  exit 2
fi

echo "PASS: no per-backend edits under lib/promscrape/discovery/*/*.go; target-limit enforcement is wired into the shared getScrapeWorkGeneric/appendScrapeWorkForTargetLabels/getStaticScrapeWork path in lib/promscrape/config.go"
exit 0
