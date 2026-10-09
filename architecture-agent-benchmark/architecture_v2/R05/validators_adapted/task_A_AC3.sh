#!/usr/bin/env bash
# Task A / AC3: no parallel/duplicate label-trimming mechanism must be introduced outside
# lib/promrelabel (e.g. inside lib/promscrape's scrape-config loader, or app/vmagent,
# app/vminsert, app/victoria-metrics request handlers).
#
# Method (per metadata AC3): `grep -rn 'TrimSpace|trim' --include=*.go app/ lib/promscrape`
# excluding lib/promrelabel itself and pre-existing unrelated matches, then manually inspect
# any hits *introduced by the diff*. app/ and lib/promscrape already contain plenty of
# pre-existing, unrelated strings.TrimSpace/Trim* usage (URL/header/whitespace trimming
# elsewhere), so a plain grep would false-positive on baseline and even on a correct
# implementation. We instead diff against the pinned pre-change commit and only flag *added*
# lines, which is what "introduced by the diff" means.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

PINNED_SHA="1afc7bb270a2529639eef177b9c75d549d3169f4"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree; cannot diff against the pre-change baseline"
  exit 1
fi

BASE_REF="$PINNED_SHA"
if ! git cat-file -e "${PINNED_SHA}^{commit}" 2>/dev/null; then
  BASE_REF="HEAD"
  echo "NOTE: pinned commit $PINNED_SHA not found in this repo's history; falling back to diffing against HEAD (less reliable if changes were already committed)." >&2
fi

if [ ! -d app ] && [ ! -d lib/promscrape ]; then
  echo "FAIL: neither app/ nor lib/promscrape found in repo '$REPO'"
  exit 1
fi

DIFF_TARGETS=""
[ -d app ] && DIFF_TARGETS="$DIFF_TARGETS app"
[ -d lib/promscrape ] && DIFF_TARGETS="$DIFF_TARGETS lib/promscrape"

# lib/promscrape does not nest lib/promrelabel, and app/ never contains it either, so scoping
# the diff to these two directories already excludes lib/promrelabel by construction.
# shellcheck disable=SC2086
CHANGED_GO_FILES=$(git diff --name-only "$BASE_REF" -- $DIFF_TARGETS 2>/dev/null | grep '\.go$' || true)

ADDED_HITS=""
if [ -n "$CHANGED_GO_FILES" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    hits=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -iE 'trimspace|\btrim\b' || true)
    if [ -n "$hits" ]; then
      ADDED_HITS="${ADDED_HITS}--- ${f} ---
${hits}
"
    fi
  done <<EOF
$CHANGED_GO_FILES
EOF
fi

if [ -n "$ADDED_HITS" ]; then
  echo "FAIL: diff introduces new whitespace-trimming logic outside lib/promrelabel (in app/ or lib/promscrape), suggesting a parallel/duplicate mechanism:"
  printf '%s\n' "$ADDED_HITS"
  exit 1
fi

echo "PASS: no new whitespace-trimming logic (TrimSpace / 'trim') introduced in app/ or lib/promscrape relative to $BASE_REF; pre-existing unrelated matches (if any) are ignored since they are not part of the diff."
exit 0
