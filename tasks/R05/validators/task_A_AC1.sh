#!/usr/bin/env bash
# Task A / AC1: the new relabeling action must be implemented as a case arm inside the
# existing single dispatch switch in func (prc *parsedRelabelConfig) apply(...) in
# lib/promrelabel/relabel.go - not as a new standalone function/file/package (the trap:
# e.g. lib/promrelabel/trim.go with its own exported Trim() called from outside the switch,
# or trimming logic duplicated into lib/promscrape / app/* handlers).
#
# Method (per metadata AC1): this is nominally "manual code review of the diff to
# relabel.go", but the core question - "is the new logic a case arm inside apply(), not a
# new top-level function called from outside that switch?" - is mechanically decidable by
# locating the byte range of the apply() function body and checking whether the trim-like
# logic lives inside that range, and whether any suspicious standalone Trim function/file
# exists outside it. We automate that instead of bailing to manual review.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

RELABEL_FILE="lib/promrelabel/relabel.go"

if [ ! -f "$RELABEL_FILE" ]; then
  echo "FAIL: $RELABEL_FILE not found in repo"
  exit 1
fi

APPLY_START=$(grep -n '^func (prc \*parsedRelabelConfig) apply(' "$RELABEL_FILE" | head -1 | cut -d: -f1)
if [ -z "$APPLY_START" ]; then
  echo "FAIL: func (prc *parsedRelabelConfig) apply(...) not found in $RELABEL_FILE (has it been renamed/removed?)"
  exit 1
fi

APPLY_END=$(awk -v start="$APPLY_START" 'NR>start && /^func /{print NR-1; exit}' "$RELABEL_FILE")
if [ -z "$APPLY_END" ]; then
  APPLY_END=$(wc -l < "$RELABEL_FILE" | tr -d ' ')
fi

APPLY_BODY_FILE=$(mktemp)
trap 'rm -f "$APPLY_BODY_FILE"' EXIT
sed -n "${APPLY_START},${APPLY_END}p" "$RELABEL_FILE" > "$APPLY_BODY_FILE"

# A trim-like case arm: either `case "...trim..."` or a case body calling strings.TrimSpace.
# grep -n line numbers are relative to APPLY_BODY_FILE; rewrite them to absolute file line
# numbers (offset by APPLY_START-1) for readable output.
to_absolute_lines() {
  awk -F: -v off="$((APPLY_START - 1))" '{ $1 = $1 + off; print }' OFS=:
}
CASE_HIT=$(grep -nE 'case[^:]*"[A-Za-z0-9_]*[Tt]rim[A-Za-z0-9_]*"' "$APPLY_BODY_FILE" | to_absolute_lines || true)
TRIMSPACE_HIT=$(grep -n 'TrimSpace' "$APPLY_BODY_FILE" | to_absolute_lines || true)

if [ -z "$CASE_HIT" ] && [ -z "$TRIMSPACE_HIT" ]; then
  echo "FAIL: no trim-like case arm (case \"trim\"/\"trim_space\", or a case body calling strings.TrimSpace) found inside apply() (lines ${APPLY_START}-${APPLY_END}) in $RELABEL_FILE"
  exit 1
fi

# Guard against a standalone top-level Trim-ish function defined anywhere in lib/promrelabel
# outside the apply() body range - a sign the real logic lives outside the switch and the
# switch (if it has a case at all) just delegates to it.
STANDALONE_HITS=$(grep -nE '^func [A-Za-z0-9_.*() ]*[Tt]rim[A-Za-z0-9_]*\(' lib/promrelabel/*.go 2>/dev/null || true)
SUSPICIOUS=""
if [ -n "$STANDALONE_HITS" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file=$(echo "$line" | cut -d: -f1)
    lineno=$(echo "$line" | cut -d: -f2)
    if [ "$file" = "$RELABEL_FILE" ] && [ "$lineno" -ge "$APPLY_START" ] && [ "$lineno" -le "$APPLY_END" ]; then
      continue
    fi
    SUSPICIOUS="${SUSPICIOUS}${line}
"
  done <<EOF
$STANDALONE_HITS
EOF
fi

# Also check for a suspiciously-named new standalone file (e.g. trim.go) directly under lib/promrelabel.
NEW_TRIM_FILE=$(find lib/promrelabel -maxdepth 1 -iname '*trim*' 2>/dev/null || true)

if [ -n "$SUSPICIOUS" ] || [ -n "$NEW_TRIM_FILE" ]; then
  echo "FAIL: found a standalone top-level Trim-ish function and/or a dedicated trim file outside the apply() switch body, suggesting a separate mechanism:"
  [ -n "$SUSPICIOUS" ] && printf '%s\n' "$SUSPICIOUS"
  [ -n "$NEW_TRIM_FILE" ] && echo "$NEW_TRIM_FILE"
  exit 1
fi

echo "PASS: trim-like logic found as a case arm inside func (prc *parsedRelabelConfig) apply() in $RELABEL_FILE (lines ${APPLY_START}-${APPLY_END}); no standalone Trim function/file found."
[ -n "$CASE_HIT" ] && echo "Case line: $CASE_HIT"
[ -n "$TRIMSPACE_HIT" ] && echo "TrimSpace usage: $TRIMSPACE_HIT"
exit 0
