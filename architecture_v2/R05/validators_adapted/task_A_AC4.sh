#!/usr/bin/env bash
# Task A / AC4: no new YAML fields must be added to the RelabelConfig struct in
# lib/promrelabel/config.go that duplicate SourceLabels/Separator/TargetLabel (e.g. a bespoke
# TrimTarget field) - the new action should reuse the existing fields, so only the Action
# string's accepted-value set grows.
#
# Method (per metadata AC4): diff lib/promrelabel/config.go's RelabelConfig struct definition
# against the pre-change version. We do this literally: extract the struct's field names from
# the pinned pre-change commit and from the current working copy, and diff the two lists.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

CONFIG_FILE="lib/promrelabel/config.go"
PINNED_SHA="1afc7bb270a2529639eef177b9c75d549d3169f4"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "FAIL: $CONFIG_FILE not found in repo"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree; cannot diff against the pre-change baseline"
  exit 1
fi

BASE_REF="$PINNED_SHA"
if ! git cat-file -e "${PINNED_SHA}^{commit}" 2>/dev/null; then
  BASE_REF="HEAD"
  echo "NOTE: pinned commit $PINNED_SHA not found in this repo's history; falling back to diffing against HEAD (less reliable if changes were already committed)." >&2
fi

extract_fields() {
  # Reads Go source on stdin, prints the RelabelConfig struct's field names, one per line.
  awk '
    /^type RelabelConfig struct/ { flag=1; next }
    flag && /^}/ { exit }
    flag {
      line=$0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]/ && line !~ /^\/\//) {
        split(line, parts, /[ \t]/)
        print parts[1]
      }
    }
  '
}

ORIG_CONTENT=$(git show "${BASE_REF}:${CONFIG_FILE}" 2>/dev/null || true)
if [ -z "$ORIG_CONTENT" ]; then
  echo "FAIL: cannot read $CONFIG_FILE from $BASE_REF (git show failed)"
  exit 1
fi

ORIG_FIELDS=$(printf '%s\n' "$ORIG_CONTENT" | extract_fields)
CUR_FIELDS=$(extract_fields < "$CONFIG_FILE")

if [ -z "$ORIG_FIELDS" ] || [ -z "$CUR_FIELDS" ]; then
  echo "FAIL: could not locate 'type RelabelConfig struct { ... }' in $BASE_REF and/or the current working copy of $CONFIG_FILE"
  exit 1
fi

ADDED_FIELDS=$(comm -13 <(printf '%s\n' "$ORIG_FIELDS" | sort) <(printf '%s\n' "$CUR_FIELDS" | sort))
REMOVED_FIELDS=$(comm -23 <(printf '%s\n' "$ORIG_FIELDS" | sort) <(printf '%s\n' "$CUR_FIELDS" | sort))

if [ -n "$ADDED_FIELDS" ]; then
  echo "FAIL: RelabelConfig struct gained new field(s) compared to $BASE_REF, which likely duplicate existing SourceLabels/Separator/TargetLabel semantics:"
  echo "$ADDED_FIELDS"
  exit 1
fi

if [ -n "$REMOVED_FIELDS" ]; then
  echo "FAIL: RelabelConfig struct lost field(s) compared to $BASE_REF (struct is not 'unchanged' as required):"
  echo "$REMOVED_FIELDS"
  exit 1
fi

echo "PASS: RelabelConfig struct fields in $CONFIG_FILE are unchanged relative to $BASE_REF (only the Action string's accepted values may have grown)."
echo "Fields: $(printf '%s ' $CUR_FIELDS)"
exit 0
