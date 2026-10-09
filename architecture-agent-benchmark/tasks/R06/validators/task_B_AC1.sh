#!/usr/bin/env bash
# AC1 (task B / R06-TB): Storage-layer Attach/panic contract is not repurposed
# to carry the new lease-key-limit error under normal operation.
#
# Method (per metadata_B.yaml AC1): manual review of
# server/storage/mvcc/kvstore_txn.go's storeTxnWrite.put() and
# server/lease/lessor.go's Attach().
#
# PASS: the panic("unexpected error from lease Attach") call in
#       kvstore_txn.go is still present, verbatim, AND lessor.go's Attach()
#       function body still only ever returns ErrLeaseNotFound (no new error
#       type returned from Attach itself).
# FAIL: the panic string was removed/altered (Attach's error contract at the
#       call site was repurposed), OR Attach() now returns some other error
#       (the trap: enforcing the limit inside Attach so that a normal client
#       Put hitting the limit crashes the process during raft apply).

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
KVSTORE_REL="server/storage/mvcc/kvstore_txn.go"
LESSOR_REL="server/lease/lessor.go"
KVSTORE_FILE="$REPO/$KVSTORE_REL"
LESSOR_FILE="$REPO/$LESSOR_REL"

if [ ! -f "$KVSTORE_FILE" ] || [ ! -f "$LESSOR_FILE" ]; then
  echo "FAIL: expected files not found under repo path '$REPO' ($KVSTORE_REL / $LESSOR_REL)"
  exit 1
fi

# --- kvstore_txn.go: panic call must still be present verbatim ---------

if ! grep -qF 'panic("unexpected error from lease Attach")' "$KVSTORE_FILE"; then
  echo "FAIL: panic(\"unexpected error from lease Attach\") is missing or altered in $KVSTORE_REL — the Attach error contract at the apply-path call site appears to have been repurposed"
  exit 1
fi

# Also confirm the call site still only guards with a plain `if err != nil`
# (not, e.g., special-casing a new error to swallow it, which would also be
# a repurposing of the contract, just in the other direction).
attach_call_ctx="$(grep -n -A3 'le.Attach(leaseID' "$KVSTORE_FILE" 2>/dev/null || grep -n -A3 '\.le\.Attach(' "$KVSTORE_FILE")"
if [ -z "$attach_call_ctx" ]; then
  echo "FAIL: could not locate the tw.s.le.Attach(...) call site in $KVSTORE_REL to verify its error handling"
  exit 1
fi
if ! echo "$attach_call_ctx" | grep -q 'if err != nil {'; then
  echo "FAIL: the Attach(...) call site in $KVSTORE_REL no longer uses a plain 'if err != nil' guard leading into panic — error handling appears to have been changed"
  exit 1
fi

# --- lessor.go: Attach() function body must not return a new error type ---

# Extract Attach()'s body: from its signature line to the next top-level
# "func " line (or EOF).
attach_start="$(grep -n '^func (le \*lessor) Attach(' "$LESSOR_FILE" | head -1 | cut -d: -f1)"
if [ -z "$attach_start" ]; then
  echo "FAIL: could not find 'func (le *lessor) Attach(' in $LESSOR_REL"
  exit 1
fi
rel_end="$(tail -n +"$((attach_start + 1))" "$LESSOR_FILE" | grep -n '^func ' | head -1 | cut -d: -f1)"
if [ -z "$rel_end" ]; then
  attach_end="$(wc -l < "$LESSOR_FILE")"
else
  attach_end="$((attach_start + rel_end - 1))"
fi
attach_body="$(sed -n "${attach_start},${attach_end}p" "$LESSOR_FILE")"

# Collect every identifier immediately following a `return` statement inside
# Attach()'s body (crude but effective: matches `return <expr>` where <expr>
# starts with an identifier, e.g. `return ErrLeaseNotFound` or `return nil`).
returned_idents="$(echo "$attach_body" | grep -oE 'return +[A-Za-z_][A-Za-z0-9_]*' | awk '{print $2}' | sort -u)"

bad_returns=0
while IFS= read -r ident; do
  [ -z "$ident" ] && continue
  case "$ident" in
    nil|ErrLeaseNotFound) ;;
    *) bad_returns=1; echo "  -> unexpected return value from Attach(): $ident" ;;
  esac
done <<< "$returned_idents"

if [ "$bad_returns" -ne 0 ]; then
  echo "FAIL: server/lease/lessor.go's Attach() now returns an error other than ErrLeaseNotFound (or nil) — this is the trap signature: the limit is being enforced inside Attach, so a normal client Put that hits the limit will crash the process at the kvstore_txn.go panic call site during raft apply."
  exit 1
fi

echo "PASS: kvstore_txn.go's panic(\"unexpected error from lease Attach\") is present and unmodified with its original guard, and lessor.go's Attach() still only returns ErrLeaseNotFound (or nil) — the limit is not enforced inside Attach."
exit 0
