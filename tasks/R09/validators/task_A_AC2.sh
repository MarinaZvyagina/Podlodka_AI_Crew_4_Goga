#!/usr/bin/env bash
# R09 Task A (TabDataStore backup-cleanup fix) — AC2
# "Backup removal is implemented via the existing TabFileManager abstraction, not ad-hoc file I/O."
# Method: grep -n 'FileManager' TabDataStore.swift — any match must be pre-existing
# (the constructor's `fileManager: TabFileManager = DefaultTabFileManager()` line), not a
# newly introduced direct `FileManager.default...` / `FileManager()` call inside removeWindowData
# or anywhere else in the file.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
FILE="$REPO/BrowserKit/Sources/TabDataStore/TabDataStore.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC2 - $FILE not found"
  exit 1
fi

# Word-boundary guarded: must not match inside "DefaultTabFileManager()" etc.
MATCHES=$(grep -nE '(^|[^A-Za-z])FileManager\.default|(^|[^A-Za-z])FileManager\(\)' "$FILE" || true)

if [ -n "$MATCHES" ]; then
  echo "FAIL: AC2 - direct FileManager usage found in TabDataStore.swift; this bypasses the TabFileManager abstraction:"
  echo "$MATCHES"
  exit 1
else
  echo "PASS: AC2 - no direct FileManager.default/FileManager() usage found in TabDataStore.swift; the injected TabFileManager abstraction is preserved"
  grep -n 'fileManager\.' "$FILE" | sed 's/^/  /'
  exit 0
fi
