#!/usr/bin/env bash
# task_A_AC2 (R04-TA): "No duplicated sanitization logic across multiple call sites."
# Method: scan changed/new files for a bracket-class regex literal embedding the
# reserved-filename-character set (a proxy for "this file defines the
# sanitization rule inline"), and count how many distinct files contain one.
# Exactly one such definition site is expected; two or more indicates the same
# character-stripping logic was re-implemented ad hoc in multiple places.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

CHANGED=$(git diff --name-only HEAD -- . 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk '/^\?\?/ {print $2}')
# exclude test files: assertions in a test naturally re-embed the char class
# to check the *result*, which is not "duplicated production logic".
ALL_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u | grep '\.tsx\?$' | grep -vE '\.(test|spec)\.tsx?$|__tests__/' || true)

if [ -z "$ALL_FILES" ]; then
  echo "FAIL: no changed/new .ts(x) files found to inspect"
  exit 1
fi

RESULT=$(node -e '
const fs = require("fs");
const files = process.argv.slice(1);
const reserved = ["\\\\", "/", ":", "*", "?", "\"", "<", ">", "|"];
const defFiles = [];
for (const f of files) {
  if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) continue;
  const content = fs.readFileSync(f, "utf8");
  // bracket-class regex/character-class literals, e.g. /[\/\\:*?"<>|]/
  const matches = content.match(/\[[^\]\n]{2,60}\]/g) || [];
  let hit = false;
  for (const m of matches) {
    let count = 0;
    for (const ch of reserved) if (m.includes(ch)) count++;
    if (count >= 4) { hit = true; break; }
  }
  if (hit) defFiles.push(f);
}
console.log(JSON.stringify(defFiles));
' -- $ALL_FILES 2>/dev/null)

if [ -z "$RESULT" ]; then
  echo "MANUAL REVIEW REQUIRED: could not run node to scan for duplicated regex logic (node unavailable?)"
  exit 1
fi

COUNT=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$RESULT" 2>/dev/null)

if [ -z "$COUNT" ]; then
  echo "MANUAL REVIEW REQUIRED: could not parse scan result: $RESULT"
  exit 1
fi

if [ "$COUNT" -le 1 ]; then
  echo "PASS: sanitization character-class regex found in $COUNT file(s): $RESULT"
  exit 0
else
  echo "FAIL: sanitization character-class regex found duplicated in $COUNT files (expected a single source of truth): $RESULT"
  exit 1
fi
