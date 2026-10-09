# SCOPE.md — R06 (etcd-io/etcd)

## Method

Scope was decided from etcd's own module/package layout — directories at depth ≤ 3 from the
repository's real source roots (`server/`, `api/`, `client/v3`), per `TREATMENT_DESIGN.md` §4 —
verified by directly reading source files in each candidate directory and by repo-wide
`grep -rl '"go.etcd.io/etcd/...'` over `server/`, `etcdctl/`, `etcdutl/`, and `client/` to confirm
which directories are genuinely load-bearing (actually imported by other parts of the
codebase), not just present. This was done **before** reading `tasks/R06/task_A.md`–`task_D.md`
(see `PLAUSIBILITY_CHECK.md` for the post-hoc self-check, performed only after this scoping and
authoring work was complete).

The repository is a 13-module `go.work` workspace (`api`, `cache`, `client/pkg`, `client/v3`,
`etcdctl`, `etcdutl`, `pkg`, `server`, `tests`, plus tooling modules). Candidate directories were
drawn from `server/` (the dominant module: `auth`, `config`, `embed`, `etcdmain`, `etcdserver`,
`features`, `lease`, `proxy`, `storage`, `verify`), `server/storage/` (`backend`, `mvcc`,
`schema`, `wal`, `datadir`), `server/etcdserver/` (`api`, `apply`, `cindex`, `read`, `txn`,
`version`, `errors`, `mock`, `snapshot`), `server/etcdserver/api/` (`membership`, `rafthttp`,
`v3rpc`, `etcdhttp`, `v2store`, `v3alarm`, `v3compactor`, `v3discovery`, `v3election`, `v3lock`,
`v3client`, `snap`, `capability`), `api/` (`authpb`, `etcdserverpb`, `membershippb`, `mvccpb`,
`v3rpc/rpctypes`, `version`, `versionpb`), and `client/v3` (top-level files plus subdirectories
`concurrency`, `leasing`, `mirror`, `namespace`, `ordering`, `snapshot`, `internal`, etc.).

## Cells covered (10) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `server/storage/backend` | `Backend`/`BatchTx`/`ReadTx` are imported by `server/etcdserver`, `server/etcdserver/api/v3alarm`, `server/etcdserver/api/v3rpc`, `server/etcdserver/apply`, `server/etcdserver/cindex`, `server/lease`, `server/storage`, `server/storage/mvcc`, `server/storage/schema`, `server/verify`, `etcdutl/etcdutl`, `etcdutl/snapshot`. The single most widely-depended-upon storage primitive in the codebase; a near-leaf (imports nothing else in this forest). |
| `server/etcdserver/api/membership` | `RaftCluster`/`Member` are imported by `server/embed`, `server/etcdserver`, `server/etcdserver/api`, `server/etcdserver/api/etcdhttp`, `server/etcdserver/api/v3rpc`, `server/etcdserver/apply`, `server/storage`, `server/storage/schema`, `etcdutl/snapshot`. Owns cluster topology — a real, load-bearing boundary consumed by both the raft transport and the client-facing RPC layer. |
| `server/etcdserver/api/rafthttp` | `Transporter` is imported by `server/embed`, `server/etcdmain`, `server/etcdserver`, `server/etcdserver/api/etcdhttp`. The raft consensus network transport — a distinct, substantial subsystem (streams, pipelines, snapshot transfer) with its own package. |
| `client/v3` | Imported by `etcdctl/ctlv3/command`, `etcdutl/snapshot`, `server/embed`, `server/etcdmain`, `server/etcdserver/api/v3client`, `server/etcdserver/api/v3discovery`, `server/etcdserver/api/v3election`, `server/etcdserver/api/v3lock`, `server/etcdserver/api/v3rpc` (embedded server-side client), `server/proxy/grpcproxy`, `server/storage/mvcc` (in tests), plus the entire `tests/` tree. The public-facing API surface every external Go consumer and etcdctl itself link against. |
| `server/lease` | `Lessor`/`LeaseID` are imported by `server/etcdserver`, `server/etcdserver/api/v3rpc`, `server/etcdserver/apply`, `server/etcdserver/txn`, `server/lease/leasehttp`, `server/storage/mvcc`, `etcdutl/etcdutl`. TTL-based key expiration — a real, self-contained subsystem with its own decoupling mechanism (callback injection to avoid circular deps with mvcc). |
| `server/storage/mvcc` | `KV`/`WatchableKV` are imported by `server/etcdserver`, `server/etcdserver/api/v3compactor`, `server/etcdserver/api/v3rpc`, `server/etcdserver/apply`, `server/etcdserver/txn`, `server/proxy/grpcproxy`, `etcdutl/etcdutl`, `etcdutl/snapshot`. etcd's actual key-value/revision data model — the central data-plane cell. |
| `server/auth` | `AuthStore` is imported by `server/etcdserver`, `server/etcdserver/api/etcdhttp`, `server/etcdserver/api/v3rpc`, `server/etcdserver/apply`, `server/storage/schema`. The RBAC/authentication domain — a real, self-contained cell with its own backend abstraction, token-provider strategy pattern (simple/JWT/no-op), and permission-cache extension point. |
| `server/etcdserver/apply` | Imported by `server/etcdserver`, `server/etcdserver/api/v3rpc`. The raft-committed-entry execution layer, structured as a genuine Chain-of-Responsibility/decorator extension point (corrupt → capped → auth → quota → backend) — a designed mechanism for adding cross-cutting request behavior. |
| `server/etcdserver` | Imported by `server/embed`, `server/etcdserver/api/etcdhttp`, `server/etcdserver/api/v3client`, `server/etcdserver/api/v3rpc`. The composition root: every other server-side cell is a field of, or constructed inside, `EtcdServer`. Root of the dependency graph. |
| `server/etcdserver/api/v3rpc` | Imported by `server/embed`, `server/etcdserver/api/v3client`, `server/proxy/grpcproxy`. The gRPC-facing adapter layer — top of the server-side request path, the layer `client/v3` talks to over the wire. |

## Deliberately excluded / deprioritized

- **`server/storage/schema`** — real and load-bearing (bucket/key layout, migrations, and the
  concrete `AuthBackend`/`MembershipBackend` implementations), but it is a thin persistence-
  mapping layer between `server/storage/backend` and its consumers (`auth`, `membership`,
  `lease`, `mvcc`) rather than an independent architectural component with its own multi-type
  public surface; documenting it as an eleventh cell would mostly restate facts already covered
  by the cells it glues together, and each of `auth`/`membership`/`lease` already documents its
  own backend abstraction generically without needing `schema`'s concrete types.
- **`server/etcdserver/api/etcdhttp`, `v3alarm`, `v3compactor`, `v3discovery`, `v3election`,
  `v3lock`, `v3client`, `snap`, `capability`, `v2store`** — real subsystems, but each is either a
  thin wrapper/glue layer (`v3client` is literally an in-process `client/v3`-shaped facade over
  `EtcdServer`), a narrow single-purpose feature (`v3election`/`v3lock` are small client-side
  recipes built on `client/v3`'s existing `concurrency` package), or a legacy/internal-only
  surface (`v2store`, `capability`) — none surfaced as independently depended-upon by ≥ 3 other
  documented cells the way the ten chosen cells did.
- **`server/proxy/grpcproxy`** — a real, substantial component (a gRPC watch/KV proxy), but it
  is a deployment-mode add-on consumed only by itself and `etcdmain`, not depended upon by any
  of the ten spine cells above; including it would not add a new *dependency edge* to the
  documented graph, only a new leaf consumer.
- **`server/config`, `server/embed`, `server/etcdmain`** — these are composition/bootstrapping
  glue (CLI flag parsing, top-level `Etcd`/`Config` struct that calls into `etcdserver.NewServer`
  and `rafthttp`), not independent architectural components with their own data model; `embed`
  in particular exists specifically to wire together the cells already documented here.
- **`server/etcdserver` sub-packages** (`cindex`, `read`, `txn`, `version`, `errors`, `mock`,
  `snapshot`) and **`server/storage` sub-packages** (`wal`, `datadir`) — real components, but the
  CODEMANIFEST `location` constraint (files must sit at the same directory level as
  `CODEMANIFEST`, no subdirectory traversal) means each would need its own cell; given the
  "roughly 6–10 cells, not an exhaustive catalog" budget, only `server/etcdserver/apply` was
  promoted to its own cell (the one sub-package that is itself a real, designed extension point —
  the decorator chain — and is directly imported by `server/etcdserver/api/v3rpc` as well as by
  `server/etcdserver` itself, unlike the others which are consumed only by `server/etcdserver`).
- **`api/authpb`, `api/etcdserverpb`, `api/membershippb`, `api/mvccpb`, `api/v3rpc/rpctypes`,
  `api/version`, `api/versionpb`** — these are protobuf-generated wire types and small constant/
  error-code packages, not independent architectural components with hand-written behavior; the
  ten documented cells reference the domain concepts these packages carry (requests/responses,
  key-value/event wire shapes) in their own vocabulary rather than importing the wire types
  literally, consistent with how CODEMANIFEST signatures are meant to describe a public contract
  rather than mirror generated protobuf structs field-for-field.
- **`client/pkg`, `pkg`, `cache`** — shared low-level utility modules (file locking, ID
  generation, interval trees, scheduling, etc.) referenced internally by several of the ten
  cells above but with no independent multi-type public surface of their own that a consumer
  would import for its domain meaning (as opposed to as a generic utility), matching the same
  exclusion rationale `TREATMENT_DESIGN.md` §4 applied to freqtrade's `enums`/`constants`/
  `misc`/`util` in the R01 validation run.

This scoping was performed and frozen before `tasks/R06/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
