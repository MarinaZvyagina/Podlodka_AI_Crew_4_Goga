#!/usr/bin/env bash
# Task B / AC2: Attachment presence must be determined via the existing attachment storage abstraction
# (hasBodyAttachments / AttachmentStore.fetchReferences), not reimplemented with raw SQL or filesystem checks.
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

USES_ABSTRACTION="$(echo "$DIFF_ALL" | grep -E '^\+.*(hasBodyAttachments|attachmentStore\.fetchReferences|AttachmentStore)' || true)"

if [ -z "$USES_ABSTRACTION" ]; then
  echo "FAIL: diff does not call hasBodyAttachments / attachmentStore.fetchReferences / AttachmentStore anywhere — attachment presence does not appear to go through the existing abstraction"
  exit 1
fi

FAIL=0

RAW_SQL="$(echo "$DIFF_ALL" | grep -E -i '^\+.*(GRDB\.sql|Database\.query|\bsql:|SELECT .* FROM.*attachment)' || true)"
FS_CHECK="$(echo "$DIFF_ALL" | grep -E '^\+.*FileManager.*(fileExists|contentsOfDirectory)' || true)"

if [ -n "$RAW_SQL" ]; then
  echo "FAIL: diff adds raw SQL touching attachments instead of using AttachmentStore:"
  echo "$RAW_SQL"
  FAIL=1
fi

if [ -n "$FS_CHECK" ]; then
  echo "FAIL: diff adds a FileManager-based file-existence check, suggesting attachment presence is being determined from disk rather than the attachment store:"
  echo "$FS_CHECK"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: diff calls into the existing attachment storage abstraction; no raw SQL or filesystem probing detected."
echo "$USES_ABSTRACTION"
exit 0
