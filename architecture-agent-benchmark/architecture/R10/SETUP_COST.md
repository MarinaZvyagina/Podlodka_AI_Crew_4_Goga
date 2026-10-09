# SETUP_COST.md — R10 (signalapp/Signal-iOS)

## initial_generation_time

Active tool-call work spanned a single continuous session on 2026-08-26 for the full pipeline:
reading `TREATMENT_DESIGN.md`/`PROTOCOL.md` (including Amendment 1), locating and reading the
`goga-cell`/`goga-cookbook`/`goga-lang-disp`/`goga-cell-swift`/`goga-apply`/
`goga-cells-by-brainstorm`/`goga-brainstorm-plan-assembly` skill files directly (the connected
Skill tool did not resolve any `goga-*` skill by name — same "does not reliably auto-invoke"
finding as R01's Amendment-1 note; all skill content was read via `Read` against the on-disk
skill directories instead), running `goga init` non-interactively, dispatching 8 parallel
source-reading research passes (via the `Explore` subagent type) over the real
`SignalServiceKit` codebase — one per planned cell area — authoring the ~940-line
`docs/arch/architecture-overview.md` plan (10 cells, written incrementally: one `Write` for the
skeleton, then one `Edit` per cell, per the R01-derived mitigation for large-single-write
transport failures — no transport failures were in fact encountered this run), materializing all
10 CODEMANIFEST files by hand (Python script parsing the plan's fenced YAML blocks and writing
each to its real cell path — the `goga-apply`/`goga-cells-by-brainstorm` Skill tool invocation
was attempted first and failed to resolve, exactly as anticipated by Amendment 1's documented
fallback), one round of `goga lint` correction, `goga schema` verification, and `goga contract`
drift spot-checks on 3 cells.

Wall-clock estimate for the above: roughly 60–75 minutes of active tool-call work (reconnaissance
and the 8 parallel research passes were the dominant cost, given `SignalServiceKit` alone is
~397k lines of Swift — over 60x the size of R01/freqtrade's `freqtrade/` package — spread across
~90 top-level directories that all had to be triaged before narrowing to 10).

## manual_correction_time

One correction pass, a few minutes: fixing 28 invalid backtick cross-references flagged by the
first `goga lint` run (see below). No `Imports.From` path-resolution errors occurred this run —
project-root-relative paths (e.g. `SignalServiceKit/Threads`, not `../Threads`) were used
correctly from the start, having been an explicit, already-known pitfall from R01's Amendment-1
findings.

## number_of_manual_corrections

- **Lint correction rounds: 1** (`goga lint` was run 2 times total):
  1. Initial `goga lint` on the freshly materialized 10-cell forest: **28 errors**, all of a
     single rule type, `annotation_links_exists` (invalid backtick cross-references). Root
     causes, none of them path-resolution issues this time:
     - Backtick-referencing a **method or property name** from a different annotation scope
       than the one that declares it (e.g. referencing `` `registrationState` `` or
       `` `attemptJob` `` at the entity/header level, or `` `failureCount` `` from a sibling
       method's annotation) — the DSL only treats **signature parameters of the annotation's
       own method**, **imported/declared types**, and **Usages/Imports practice keys** as valid
       link targets; a method or property name is never itself a valid link target, even for
       its own declaring type's other annotations.
     - Backtick-referencing a **dotted expression** (`` `JobQueueRunner.start` ``,
       `` `delete(interactions:sideEffects:tx:)` ``) or an **enum case literal**
       (`` `.registered` ``, `` `.valid` ``) — neither is a named document element.
     - Backtick-referencing a **native/foreign type name that was never declared or imported**
       in that cell (`` `Data` ``, `` `Codable` ``, `` `NSSecureCoding` ``) — used because the
       underlying real Swift code genuinely uses `Codable`/`NSSecureCoding`, but since the
       CODEMANIFEST forest doesn't import `Foundation`/`Swift` standard-library protocols as
       cells, these must stay as plain prose, not backtick links.
     - Backtick-referencing a **signature parameter name that belongs to a different method**
       than the one being annotated (e.g. mentioning `` `aci` `` / `` `pni` `` in prose when the
       actual parameter in that method's own signature was named `identity`).
     All 28 were fixed by either removing the backticks (converting to plain prose) or
     rephrasing to avoid the cross-scope/dotted/enum-case reference entirely. Re-lint:
     **0 errors**, `cells: 10 errors: 0`.
- **Contract-drift corrections: 0** (see findings below — all drift found was judged cosmetic/
  simplification or a static-analysis overload-matching artifact, not a fabricated or materially
  misleading contract; no CODEMANIFEST content was changed as a result of the `goga contract`
  spot-checks).

## artifact_size

- **10 CODEMANIFEST files** (one per documented cell)
- **793 total lines** (`wc -l` across all 10 files in the deliverable directory)
- Cell sizes range from 28 lines (`SignalServiceKit/Jobs/JobRecords`) to 129 lines
  (`SignalServiceKit/Account/TSAccountManager`)
- No `.usages/` files were created — all practices used the DSL's **inline** `Usages` form
  (each practice was short, specific to one cell, and did not need to be reused across the
  forest), consistent with `goga-cookbook`'s guidance and with R01's precedent.

## contract_drift_findings

`goga contract --lang swift` was run against 3 cells: `SignalServiceKit/Threads`,
`SignalServiceKit/Account/TSAccountManager`, and
`SignalServiceKit/Storage/Database/SDSDatabaseStorage`.

- **`SignalServiceKit/Account/TSAccountManager`** — near-perfect match. Every method on
  `TSAccountManager` matched on parameter count/order and return-optionality; only cosmetic
  drift (`Int` shown in place of `UInt32`/`OWSIdentity`/`PhoneNumberDiscoverability` internal
  type aliases, as expected for a public-contract-only description simplifying framework-internal
  types to primitives, per the same simplification convention R01 used for `dict[str, Any]`).
  `TSRegistrationState`'s four computed properties (`isRegistered`, `wasEverRegistered`,
  `isDeregistered`, `isRegisteredPrimaryDevice`) show `implementation: null` in the contract-tool
  output — confirmed by direct source re-inspection that all four are real, currently-existing
  computed properties; this is a static-extraction limitation of `goga contract` for
  enum-computed-property detection, not a documentation error.
- **`SignalServiceKit/Storage/Database/SDSDatabaseStorage`** — `read`/`write`/`awaitableWrite`/
  `asyncWrite` all matched in shape (block-based transaction methods), modulo the tool showing
  `SDSDatabaseStorage`'s real generic/file-function-line tracing parameters
  (`file:`/`function:`/`line:`) that the CODEMANIFEST intentionally omits as internal
  instrumentation detail, not part of the public behavioral contract. One overload-matching
  artifact: `SDSDatabaseStorage.touch` has three real overloads (thread/interaction/
  storyMessage); the CODEMANIFEST documents the `touch(thread:shouldReindex:tx:)` overload
  (confirmed real during initial research) but the contract tool's static match surfaced the
  `touch(storyMessage:tx:)` overload instead — both are real overloads of the same method name,
  so this is a tool-side overload-disambiguation limitation, not a fabricated method.
  `logFileSizes` shows `implementation: null` despite being a confirmed real, currently-existing
  `public func logFileSizes()` — likely the same static-extraction limitation as above. `init`
  signature drift is expected and intentional: the CODEMANIFEST's `(databaseFileUrl: String)`
  omits `appReadiness`/`keychainStorage` constructor dependencies that are launch-time wiring
  detail, not part of what a consumer calling `read`/`write` needs to know.
- **`SignalServiceKit/Threads`** — `ThreadStore`/`ThreadDeletionManager` methods matched in
  purpose and general shape; the main pattern of drift is the same overload-matching artifact
  as above (`ThreadStore` has multiple real overloads of `fetchThread`/`getOrCreateContactThread`
  differing by parameter type — e.g. a `uniqueId`-keyed and a `forGroupIdData`-keyed
  `fetchThread` overload both exist for real; the CODEMANIFEST documents the `uniqueId`-keyed
  one, the tool's static match surfaced the `forGroupIdData`-keyed one instead) plus the expected
  type-simplification convention (`TSThread` shown as `TSGroupThread` in signatures, since the
  CODEMANIFEST scope excludes the abstract `TSThread` base class — see `SCOPE.md` — and
  `LocalIdentifiers` shown as `String`). One minor, genuinely worth flagging: the real
  `getOrCreateContactThread` uses the external parameter label `with` (`with address:
  SignalServiceAddress`), not `address`; the CODEMANIFEST uses `address` as both the external
  and internal name. Judged cosmetic (a caller substitution difference, not a behavioral one)
  and left as-is rather than hand-tuning after the fact, consistent with R01's disclosed
  precedent of leaving honestly-disclosed cosmetic drift in place rather than re-editing after
  seeing tool output.

No drift was found across any of the three spot-checked cells that fabricates a method that
doesn't exist, misstates what a real method does, or would materially mislead an agent about a
cell's real public shape.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if Signal-iOS or Goga
change mid-benchmark.
