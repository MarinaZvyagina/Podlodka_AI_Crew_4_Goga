# CYCLE_FIXES.md — R06 (etcd-io/etcd)

No real circular dependencies were found among the 10 documented cells.

Verified via the actual Go package import graph (`go list -f '{{join .Imports "\n"}}' <pkg>` per
cell, cross-referenced against the other 9 cells' import paths), not just Goga's own declared-
`Imports` cycle check — a genuinely cell-native codebase needs the *real* code's dependency graph
to be acyclic, not just what happens to be declared in CODEMANIFEST.

Result: the 10 cells form a clean DAG. Topological order (leaves first): `server/storage/backend`,
`client/v3`, `server/auth`, `server/etcdserver/api/membership`, `server/etcdserver/api/rafthttp`
→ `server/lease` → `server/storage/mvcc` → `server/etcdserver/apply` → `server/etcdserver` →
`server/etcdserver/api/v3rpc`.

One surprising-looking edge was found and investigated: `server/storage/mvcc` directly imports
`client/v3` (used only for two shared wire-protocol sentinel constants, `AutoWatchID` and
`InvalidWatchID`) — architecturally unusual (a low-level storage engine depending on the public
client library) but confirmed to be a real, legitimate, pre-existing design choice (avoiding
duplicating a shared client/server watch-ID convention as a magic number), not a defect requiring
correction. It does not participate in any cycle since `client/v3` itself has zero dependencies on
any of the other 9 cells.

No cycle-breaking refactors were needed for this repository.
