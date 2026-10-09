Our compliance team wants a consistent audit trail for every key-value read and write that goes
through the cluster: who made the request (if authentication is enabled), what kind of
operation it was (read, write, delete, or transaction), which key or key range was involved, how
long the server took to handle it, and whether it succeeded or failed.

This needs to cover every key-value request the same way, going forward, without relying on
someone remembering to add logging by hand every time a new request type is added or an existing
one changes. Please add this.

Requirements:
- Every key-value read, write, delete, and transaction request handled by the server produces an
  audit record with: caller identity (or "unauthenticated" if auth is off / no identity is
  available), operation kind, key or key range, duration, and outcome (success/failure).
- Coverage must be uniform across all key-value request types — no request type should be missed
  because someone forgot to instrument it individually.
- The audit mechanism must not change the functional behavior or response content of the
  underlying operations.
- Existing request logging/latency-warning behavior should keep working.
