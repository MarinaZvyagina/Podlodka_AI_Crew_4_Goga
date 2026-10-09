#!/usr/bin/env bash
# Task A / AC2: the new action must be validated at config-parse time inside the existing
# validation switch in lib/promrelabel/config.go (func parseRelabelConfig - the switch that
# already validates "uppercase", "lowercase", "keep", "drop", etc. and ends in a `default`
# case returning "unknown action"), with checks mirroring uppercase/lowercase's missing
# source_labels / missing target_label errors.
#
# Method (per metadata AC2): `grep -n 'case "<name>' lib/promrelabel/config.go`. We do that,
# scoped to the parseRelabelConfig() function body, and additionally confirm the matched case
# arm actually checks sourceLabels/targetLabel (not just an empty case that would fall through
# to unvalidated behavior), and that there is no duplicate validation switch elsewhere.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

CONFIG_FILE="lib/promrelabel/config.go"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "FAIL: $CONFIG_FILE not found in repo"
  exit 1
fi

FUNC_START=$(grep -n '^func parseRelabelConfig(' "$CONFIG_FILE" | head -1 | cut -d: -f1)
if [ -z "$FUNC_START" ]; then
  echo "FAIL: func parseRelabelConfig(...) not found in $CONFIG_FILE (has the validation entry point been renamed/removed?)"
  exit 1
fi

FUNC_END=$(awk -v start="$FUNC_START" 'NR>start && /^func /{print NR-1; exit}' "$CONFIG_FILE")
if [ -z "$FUNC_END" ]; then
  FUNC_END=$(wc -l < "$CONFIG_FILE" | tr -d ' ')
fi

FUNC_BODY_FILE=$(mktemp)
trap 'rm -f "$FUNC_BODY_FILE"' EXIT
sed -n "${FUNC_START},${FUNC_END}p" "$CONFIG_FILE" > "$FUNC_BODY_FILE"

# grep -n 'case "<name>' scoped to the validation function, per the metadata's literal method.
CASE_HIT=$(grep -nE 'case[^:]*"[A-Za-z0-9_]*[Tt]rim[A-Za-z0-9_]*"' "$FUNC_BODY_FILE" || true)

if [ -z "$CASE_HIT" ]; then
  echo "FAIL: no 'case \"...trim...\"' found inside the validation switch (func parseRelabelConfig) in $CONFIG_FILE"
  echo "(invalid configs for the new action would only be caught at runtime via the default unknown-action path, if at all)"
  exit 1
fi

CASE_LINE_NUM=$(echo "$CASE_HIT" | head -1 | cut -d: -f1)

# Grab the body of this case arm: from the matched line up to (but excluding) the next
# top-level `case` or `default:` line within the switch.
WINDOW_FILE=$(mktemp)
trap 'rm -f "$FUNC_BODY_FILE" "$WINDOW_FILE"' EXIT
tail -n "+${CASE_LINE_NUM}" "$FUNC_BODY_FILE" | awk 'NR==1{print; next} /^\tcase |^\tdefault:/{exit} {print}' > "$WINDOW_FILE"

HAS_SOURCE_CHECK=$(grep -c 'sourceLabels' "$WINDOW_FILE" || true)
HAS_TARGET_CHECK=$(grep -c 'targetLabel' "$WINDOW_FILE" || true)

if [ "${HAS_SOURCE_CHECK:-0}" -eq 0 ] || [ "${HAS_TARGET_CHECK:-0}" -eq 0 ]; then
  echo "FAIL: case arm for the trim-like action was found in $CONFIG_FILE but does not check both sourceLabels and targetLabel (mirroring uppercase/lowercase). Case-arm body:"
  cat "$WINDOW_FILE"
  exit 1
fi

# Check for a duplicate/second validation switch elsewhere in the file (outside this function's
# range) that also matches a trim-like case - a sign validation was duplicated in a new function.
ALL_HITS=$(grep -nE 'case[^:]*"[A-Za-z0-9_]*[Tt]rim[A-Za-z0-9_]*"' "$CONFIG_FILE" || true)
DUPLICATE_HITS=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  lineno=$(echo "$line" | cut -d: -f1)
  if [ "$lineno" -ge "$FUNC_START" ] && [ "$lineno" -le "$FUNC_END" ]; then
    continue
  fi
  DUPLICATE_HITS="${DUPLICATE_HITS}${line}
"
done <<EOF
$ALL_HITS
EOF

if [ -n "$DUPLICATE_HITS" ]; then
  echo "FAIL: found additional trim-like case(s) in $CONFIG_FILE outside parseRelabelConfig()'s switch, suggesting duplicated validation logic:"
  printf '%s\n' "$DUPLICATE_HITS"
  exit 1
fi

ABS_CASE_LINE=$((CASE_LINE_NUM + FUNC_START - 1))
echo "PASS: trim-like action is validated inside parseRelabelConfig()'s switch in $CONFIG_FILE, with sourceLabels/targetLabel checks present, and no duplicate validation switch found."
echo "${CONFIG_FILE}:${ABS_CASE_LINE}: $(sed -n "${ABS_CASE_LINE}p" "$CONFIG_FILE")"
exit 0
