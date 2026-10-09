# SETUP_COST.md — R06 (etcd-io/etcd)

## initial_generation_time

Active tool-call work spanned roughly **10:53–11:15 MSK (≈ 22 minutes)** on 2026-08-26 for the
full pipeline: reading `TREATMENT_DESIGN.md`/`PROTOCOL.md` (Amendment 1), verifying the pinned
commit and repo layout, running `goga init`, dispatching 5 parallel source-reading research
passes over the real etcd Go source (`server/storage/backend`+`server/storage/mvcc`,
`server/auth`+`server/lease`, `server/etcdserver`(core)+`server/etcdserver/apply`,
`server/etcdserver/api/membership`+`rafthttp`+`v3rpc`, `client/v3`), loading the
`goga-cell`/`goga-cookbook`/`goga-lang-disp`/`goga-cell-go` DSL skills directly from
`~/.claude/skills/` (the Skill tool did not surface them, consistent with Amendment 1's known
issue), authoring the ~1,070-line `docs/arch/architecture-overview.md` plan (10 cells) via one
skeleton `Write` plus 10 incremental per-cell `Edit` appends, materializing it to 10
CODEMANIFEST files via a direct extraction script (the `goga-apply`/`goga-cells-by-brainstorm`
procedure followed by hand per Amendment 1, since the Skill tool did not auto-invoke it either),
2 rounds of `goga lint`, one `goga schema` verification, and `goga contract` drift spot-checks
on 3 cells.

Unlike the R01 (freqtrade) validation run, this session experienced no transport/connection
failures — the incremental skeleton-then-per-cell-`Edit` authoring approach from Amendment 1
worked cleanly on the first attempt.

## manual_correction_time

One concentrated pass, a few minutes within the session above (not separately timed): 24
distinct `goga lint` findings, all fixed directly in `docs/arch/architecture-overview.md` and
re-materialized via the same extraction script, then re-linted clean in one additional round.

## number_of_manual_corrections

- **Lint correction rounds: 1** (`goga lint` was run 2 times total):
  1. Initial `goga lint` on the freshly materialized 10-cell forest: **24 errors**, all
     `annotation_links_exists` except one `import_type_exists`:
     - **Bracket-expression backticks** (7 occurrences): annotations backtick-quoted range
       notations like `` `[key, endKey)` `` / `` `[key, end)` `` / `` `[key, rangeEnd)` `` —
       not valid link targets (not a signature parameter, type, or practice name). Rewritten as
       plain prose ("the range from `key` up to (excluding) `endKey`").
     - **Method-name self/cross-references** (13 occurrences): annotations backtick-quoted
       sibling or self method names — e.g. `` `LockInsideApply` ``/`` `LockOutsideApply` ``
       (entity-level annotation referencing its own methods' names),
       `` `UnsafePut` ``/`` `UnsafeDelete` `` (`Hooks.OnPreCommitUnsafe` referencing sibling
       `BatchTx` methods by name), `` `Send` ``/`` `SendSnapshot` ``/`` `AddPeer` ``/
       `` `UpdatePeer` `` (header-level `Annotations` referencing `Transporter`'s own method
       names), `` `Apply` `` (a method's own annotation naming itself), `` `Cluster` `` (a
       leftover from an earlier draft where the method was renamed but the backtick wasn't
       updated to the real imported type name `RaftCluster`), `` `If` `` ×2 (`Txn.Then`/`Else`
       annotations referencing sibling method `If`), `` `Lessor` `` and `` `WatchResponse` ``
       (client/v3's `Lease`/`Watcher` annotations naming server-side/wire types that are
       neither declared nor imported in that cell), and one dotted expression
       `` `configuration.Endpoints` ``. Per the DSL spec ("Annotations must not reference
       entities outside the current CODEMANIFEST file context") and `goga-cookbook`'s reference
       rules, only signature parameters, same-document Entity/Routine names, Imports-declared
       types, and Usages/Imports practice keys are valid backtick targets — plain method names
       are not, even when they belong to the same entity. All 13 were rewritten as plain prose.
     - **`import_type_exists`** (1 occurrence, `server/etcdserver`): `LeaseID` was imported from
       `server/lease`, but `server/lease`'s CODEMANIFEST never declares a standalone `LeaseID`
       type (it only appears as `Lease.ID -> int64`, matching how the rest of the forest already
       simplifies `LeaseID`/`WatchID` to plain `int64` in signatures). Fixed by dropping the
       import and changing `LeaseRenew(id LeaseID)` to `LeaseRenew(id int64)`, consistent with
       every other lease-ID-typed parameter already documented elsewhere in the forest.
  2. Re-lint after all 24 fixes: **0 errors**.
- **Contract-drift corrections: 0.** `goga contract` was run against 3 cells (see
  `contract_drift_findings` below); all findings were either cosmetic (expected, per
  `TREATMENT_DESIGN.md`'s own precedent) or a tool-extraction limitation, not a documentation
  error, so no CODEMANIFEST content was changed as a result.

## artifact_size

- **10 CODEMANIFEST files** (one per documented cell)
- **890 total lines** (`wc -l` across all 10 files in the deliverable directory)
- Cell sizes range from 65 lines (`server/etcdserver/api/v3rpc`) to 115 lines
  (`server/storage/backend`)
- No `.usages/` files were created — every practice was short and cell-specific, so all of them
  used the DSL's inline `Usages` form (per `goga-cookbook`'s guidance), matching the R01
  precedent.

## contract_drift_findings

`goga contract --lang golang` was run against 3 cells (`server/storage/backend`, `server/lease`,
`server/storage/mvcc`) to compare CODEMANIFEST signatures against the real tree-sitter-extracted
Go implementation (these are real, pre-existing etcd source directories, so `contract` compared
directly against production code, not a stub):

- **`server/lease`** — near-perfect match on every method of `Lessor` and `Lease`; only cosmetic
  drift (`LeaseID` shown as plain `int64`, `time.Duration` shown as `Duration`,
  `Checkpointer`/`RangeDeleter` function types shown under the descriptive aliases
  `CheckpointerFunc`/`RangeDeleterFunc`, `Grant`'s `*Lease` return shown without the pointer per
  the Go-cell DSL's own no-pointer-notation rule) — all expected simplifications for
  public-contract legibility, consistent with `TREATMENT_DESIGN.md`'s established precedent
  from the R01 run. One expected, already-disclosed divergence: `ExpiredLeasesC` is documented
  as returning `leases:[]Lease` where the real signature returns a channel
  (`<-chan []*Lease`) — channels are a forbidden DSL signature construct per `goga-cell-go`, so
  this was a deliberate, annotated simplification from the start, not a drift correction.
- **`server/storage/backend`** — `Backend`'s methods matched closely (cosmetic-only:
  `ignore BucketKeyPredicate` vs. the real inline `func(bucketName, keyName []byte) bool`, again
  a forbidden-construct simplification). Found a **tool-extraction limitation, not a
  documentation error**: `BatchTx.UnsafeCreateBucket`/`UnsafePut`/`UnsafeDelete`/`UnsafeRange`
  and `ReadTx.UnsafeRange` were reported with `"implementation": null`. Reading the real source
  confirms these methods are real and correctly documented — they are declared via the embedded
  `UnsafeReadWriter`/`UnsafeReader`/`UnsafeWriter` interfaces (`type BatchTx interface { ...;
  UnsafeReadWriter }`) rather than listed literally inside the `BatchTx`/`ReadTx` interface
  bodies, and `goga contract`'s extractor does not appear to flatten embedded-interface method
  sets when matching against a CODEMANIFEST entity of the outer interface's name. This is
  disclosed here as a known limitation of the spot-check tooling on Go's interface-embedding
  idiom, not a defect in the frozen forest.
- **`server/storage/mvcc`** — `New`'s constructor signature, `WatchStream`'s methods, and `KV`'s
  `Close`/`Read`/`Write`/`Restore`/`Compact` all matched (cosmetic-only differences: `WatchID`
  shown as `int64`, `*traceutil.Trace`/`*zap.Logger` tracing/logging parameters omitted from
  the documented signatures as non-contractual plumbing). The same embedded-interface
  extraction limitation as above caused `Put`/`Range`/`DeleteRange` (declared via embedded
  `WriteView`/`ReadView`) and `WatchableKV.NewWatchStream` (declared via embedded `Watchable`)
  to show `"implementation": null`; manually re-verified against the real `kv.go` source
  (already read in full during initial research) confirms all three signatures are accurate.
  One genuine, minor, disclosed omission (judged non-material, following the same standard
  applied to the R01 run's `get_tickers` finding): the real `ReadView.Range` signature also
  takes a `ctx context.Context` and a `RangeOptions` struct (limit/countOnly/etc. refinements)
  that the CODEMANIFEST's simplified `Range(key []byte, end []byte)` omits — the semantic core
  of the method (read a key or range, return matches plus an error) is unchanged, so this was
  not corrected retroactively.

No drift was found that would materially mislead an agent about a cell's real public shape.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if etcd or Goga change
mid-benchmark.
