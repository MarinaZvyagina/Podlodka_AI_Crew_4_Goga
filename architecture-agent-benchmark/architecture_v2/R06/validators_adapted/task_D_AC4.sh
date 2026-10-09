#!/usr/bin/env bash
# AC4: Linearizable-read guarantee is preserved for non-serializable Range
# requests regardless of cache state.
#
# Method: extract the body of EtcdServer.Range in
# server/etcdserver/v3_server.go from the *working tree* (post-change) and
# confirm s.read.LinearizableReadNotify(ctx) is still called, still gated
# only on r.Serializable (not additionally gated behind a cache-hit check).
set -u

REPO="${1:-.}"
BASELINE="abe967acfac35ba278795c42e0a8968637594cef"
FILE="server/etcdserver/v3_server.go"

if ! git -C "$REPO" rev-parse "$BASELINE" >/dev/null 2>&1; then
  echo "MANUAL REVIEW REQUIRED: baseline commit $BASELINE not found in $REPO"
  exit 2
fi

full="$REPO/$FILE"
if [ ! -f "$full" ]; then
  echo "MANUAL REVIEW REQUIRED: $FILE not found in $REPO"
  exit 2
fi

DIFF=$(git -C "$REPO" diff "$BASELINE" -- "$FILE" 2>/dev/null)

# Extract the EtcdServer.Range function body (from its signature to the
# next top-level "func " line) from the current working tree.
BODY=$(awk '
  /^func \(s \*EtcdServer\) Range\(/ { infunc=1 }
  infunc { print }
  infunc && /^func \(s \*EtcdServer\) RangeStream\(/ && !/^func \(s \*EtcdServer\) Range\(/ { exit }
' "$full")

# The awk above prints starting at Range( and stops once it also prints the
# RangeStream( line; trim that trailing line back off.
BODY=$(printf '%s\n' "$BODY" | sed '$d' 2>/dev/null)

if [ -z "$BODY" ]; then
  echo "MANUAL REVIEW REQUIRED: could not locate EtcdServer.Range function body in $FILE (signature may have changed); inspect manually"
  exit 2
fi

if ! printf '%s\n' "$BODY" | grep -q 'LinearizableReadNotify'; then
  echo "FAIL: LinearizableReadNotify is no longer called in EtcdServer.Range"
  exit 1
fi

# Grab the LinearizableReadNotify line and the few lines immediately
# preceding it (the guarding if-condition) to check what gates the call.
CALL_LINE_NO=$(printf '%s\n' "$BODY" | grep -n 'LinearizableReadNotify' | head -1 | cut -d: -f1)
START=$((CALL_LINE_NO - 4))
[ "$START" -lt 1 ] && START=1
GUARD=$(printf '%s\n' "$BODY" | sed -n "${START},${CALL_LINE_NO}p")

if ! printf '%s\n' "$GUARD" | grep -q 'r\.Serializable'; then
  echo "FAIL: LinearizableReadNotify call is no longer directly gated on r.Serializable (guard context):"
  printf '%s\n' "$GUARD"
  exit 1
fi

if printf '%s\n' "$GUARD" | grep -qiE 'cache|[^a-zA-Z]hit[^a-zA-Z]|hit$'; then
  echo "FAIL: a cache-hit-looking condition appears to gate/short-circuit LinearizableReadNotify:"
  printf '%s\n' "$GUARD"
  exit 1
fi

echo "PASS: LinearizableReadNotify is still called in EtcdServer.Range, gated only on r.Serializable, with no cache short-circuit detected"
if [ -n "$DIFF" ]; then
  echo "(note: $FILE has other changes vs baseline; guard context inspected below)"
  printf '%s\n' "$GUARD"
fi
exit 0
