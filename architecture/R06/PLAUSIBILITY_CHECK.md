# PLAUSIBILITY_CHECK.md — R06 (etcd-io/etcd)

## When this check was performed

`tasks/R06/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 10 CODEMANIFEST files were authored, materialized, linted, and
drift-checked — per the assignment's explicit ordering requirement. No content in the
architecture forest was revised in response to reading the tasks (see "Outcome" below for the
one case that needed the closest look).

## The four task prompts (quoted)

- **Task A**: reject empty/blank passwords on user creation and password-change requests unless
  the account is explicitly opted into "no-password (passwordless) mode," with a distinct,
  clear error, "no matter which client or tool is used to talk to the cluster."
- **Task B**: add a configurable cap on how many distinct keys may be attached to a single
  lease at once; a write that would push a lease over the limit must fail cleanly (server stays
  healthy, no partial apply), while re-attaching an already-attached key or writes under the
  limit must keep working exactly as today.
- **Task C**: add a uniform audit trail (caller identity, operation kind, key/range, duration,
  outcome) for every key-value read/write/delete/transaction, "without relying on someone
  remembering to add logging by hand every time a new request type is added."
- **Task D**: add caching for repeated identical read requests, invalidated promptly on any
  write/delete affecting the cached range, never returning data staler than an equivalent
  uncached read would have — for both linearizable and serializable reads — with cache misses
  behaving exactly as before.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 10 CODEMANIFEST files plus `SCOPE.md`/`SETUP_COST.md` for the task-specific terms
each prompt turns on: none of "passwordless", "no-password", "blank password", "empty
password", "key-count"/"keys per lease"/"lease cap", "compliance", "caller identity" appear
anywhere in the forest. For Task D's vocabulary, "cache"/"caching"/"stale" do appear, but only
in contexts unrelated to KV read-request caching: `server/auth`'s pre-existing
`range_permission_cache` practice (a permission-check interval-tree cache, unrelated to caching
KV read *results*) and `server/etcdserver/api/rafthttp`'s "stale peers" (connection liveness,
not data staleness). Neither hints at Task D's read-request cache-with-invalidation mechanism.
One genuine hit is disclosed below under Task C.

## Where genuine overlap exists, and why it's expected rather than leakage

- **Task C ↔ `server/etcdserver/apply`'s `decorator_chain` practice — the closest overlap
  found.** The practice text reads: "Add a new cross-cutting concern (e.g. rate limiting, audit
  logging) as a new decorator in this chain rather than modifying the base applier." The phrase
  "audit logging" is a literal, if generic, match for Task C's "audit trail" framing. This
  cell's entire reason for existing in the forest is that the real `uberApplier` decorator chain
  (`applierV3Corrupt` → `applierV3Capped` → `authApplierV3` → `quotaApplierV3` →
  `applierV3backend`, confirmed verbatim from `uber_applier.go`) is etcd's actual, designed
  Chain-of-Responsibility extension point for exactly this class of requirement — uniform
  cross-cutting behavior applied to every KV request without touching per-request-type code,
  which is precisely what Task C's "without relying on someone remembering to instrument every
  request type" is asking for. "Rate limiting" and "audit logging" are the two textbook
  illustrative examples of what a decorator/middleware chain is for in general (not specific to
  etcd or to this task), and the practice does not mention caller identity, operation-kind
  enumeration, duration, or outcome — the actual content Task C requires — so it names the
  *category* of mechanism, not the task's specific implementation. Per `TREATMENT_DESIGN.md`
  §4's explicit design rule ("this cell is the read path for search queries" is acceptable;
  "add caching here" is forbidden), this sits close to the line but was judged acceptable
  because it describes what the decorator pattern is used for *in general* (as any architecture
  reference would), not "add an audit log to Put/Range/Txn." Judgment call: kept as-is, for the
  same reason `PLAUSIBILITY_CHECK.md` in the R01 run kept its closest overlap (Task C /
  `plugins/protections`) — editing the forest after seeing the task list would itself be a worse
  violation of the freeze discipline than leaving an honestly-disclosed, architecturally-
  justified overlap in place. If a stricter standard is wanted for future repositories, the fix
  would be to drop illustrative examples from decorator/extension-point practices entirely and
  name only the mechanism, not any example use case.
- **Task A ↔ `server/auth`**: the forest documents `AuthStore.UserAdd`/`UserChangePassword`
  (mentioned by name in the interface method list) and the `TokenProvider`/permission-cache
  extension points, but never mentions password validation, blank/empty passwords, or a
  passwordless mode — `UserAdd`'s annotation says only "Create a new user with a
  bcrypt-hashed password." This is weaker overlap than Task C's: it establishes *that* user
  creation/password-change are real, existing entry points in this cell (true, load-bearing
  architecture fact — the forest would be incomplete without documenting `AuthStore` at all),
  not *what* validation Task A wants added to them.
- **Task B ↔ `server/lease`**: the forest documents `Lessor.Attach`/`Detach` and the
  `LeaseItem`/`itemMap` key-to-lease association mechanism generically, but never mentions a
  key-count limit, a configurable cap, or rejecting an `Attach` call. This tells an agent that
  keys-per-lease is tracked as a set (real fact, needed to explain what `Attach`/`Detach` do at
  all) without suggesting where or how a limit should be enforced.
- **Task D ↔ `server/storage/mvcc` / `server/etcdserver`**: no overlap found beyond the
  incidental word "stale" noted above (in an unrelated cell). The forest documents `KV.Range`
  and the `write_path` practice (linearizable reads confirm against the commit index, then read
  `KV` directly) with no mention of caching, memoization, or repeated-request optimization
  anywhere in either cell.

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task C / `server/etcdserver/apply`'s decorator-chain practice) is disclosed
here explicitly, following the same standard the R01 (freqtrade) validation run applied to its
own closest overlap, rather than retroactively edited after seeing the task list.
