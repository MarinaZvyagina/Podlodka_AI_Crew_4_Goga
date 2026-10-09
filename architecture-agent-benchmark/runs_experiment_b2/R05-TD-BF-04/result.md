# R05-TD-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $2.8346009999999993
Duration: 507890ms, turns: 59

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive, observability/diagnostics capability layered on existing series-limit enforcement)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/storage` | `lib/storage/droppedseriesstats/tracker.go` (new), `lib/storage/droppedseriesstats/tracker_test.go` (new), `lib/storage/storage.go`, `lib/storage/storage_test.go`, `lib/storage/CODEMANIFEST` | New bounded per-metric-name drop tracker package; `Storage`/`OpenOptions`/`Metrics` gain new fields; `registerSeriesCardinality` records drops; new public query/reset methods; new tests; manifest additions |
| `app/vmstorage` | `app/vmstorage/main.go`, `app/vmstorage/CODEMANIFEST` | New flags, `Init()` wiring, two new HTTP endpoints, two new exported gauges in `writeStorageMetrics`; manifest additions |

## Root Cause Analysis
Confirmed by investigation: `registerSeriesCardinality` (storage.go:2151) is the single choke point where both series-limit rejections occur, and it already has the rejected row's `metricNameRaw` in scope but discards it after an aggregate-only counter increment. No existing mechanism records per-name drop attribution anywhere in the repository.

## Trace Summary
`AddRows`/`RegisterMetricNames` → `registerSeriesCardinality` → (on rejection) new `Tracker.RecordHourlyLimitDrop`/`RecordDailyLimitDrop` → in-memory bounded map → `Storage.GetDroppedSeriesNamesStats`/`ResetDroppedSeriesNamesStats` → new `app/vmstorage` HTTP handlers → JSON response. This path is confirmed isolated to `lib/storage` + `app/vmstorage`; no `vmselect`/`vminsert`/tenant code is touched, matching investigation scope exactly.

## Change Strategy

1. **New package `lib/storage/droppedseriesstats`** (sibling to `metricnamestats`, same directory nesting pattern):
   - `Tracker` struct: `mu sync.Mutex`, `m map[string]*counts`, `creationTs atomic.Uint64`, `maxEntries int`, `currentEntries atomic.Uint64`, `getCurrentTs func() uint64` (test seam, mirroring `metricnamestats.Tracker`).
   - `counts` struct: `hourlyDropped atomic.Uint64`, `dailyDropped atomic.Uint64`.
   - `NewTracker(maxEntries int) *Tracker` — if `maxEntries <= 0`, treat as 1 (mirrors `metricnamestats.initEmpty`/`newTracker` defensiveness).
   - `(t *Tracker) RecordHourlyLimitDrop(metricNameRaw []byte)` / `RecordDailyLimitDrop(metricNameRaw []byte)`: nil-receiver guard first; RLock to check existing entry and increment atomically if found; otherwise Lock, re-check (double-checked locking, mirrors `metricnamestats.RegisterIngestRequest`), and if `currentEntries >= maxEntries` skip silently (bounded-memory guarantee), else clone the name (allocate a `string` — no need for `metricnamestats`'s buffer-pooling trick since entries are capped at a small fixed count, not proportional to ingestion rate) and insert.
   - `Record`/`StatsResult` types as specified; `GetTopRecords(topN int) StatsResult`: nil-safe, RLock, copy+sort by `HourlyDropped+DailyDropped` descending, truncate to `topN` (if `topN <= 0`, return all).
   - `Reset()`: nil-safe, Lock, reinitialize map, reset `currentEntries`/`creationTs`.

2. **`lib/storage/storage.go`**:
   - Add `droppedSeriesTracker *droppedseriesstats.Tracker` field to `Storage` (near `hourlySeriesLimiter`/`dailySeriesLimiter`, line ~89).
   - Add `TrackDroppedSeriesNames bool` to `OpenOptions` (near `TrackMetricNamesStats`, line ~173).
   - Add `maxDroppedSeriesNames int` package var + `SetMaxDroppedSeriesNames(n int)` + `getMaxDroppedSeriesNames() int` (default `10000` when `<=0`), placed next to the `maxMetricNamesStatsCacheSize` trio (line ~352-364).
   - In `MustOpenStorage`, after the existing limiter-init block (line ~245): `if opts.TrackDroppedSeriesNames { s.droppedSeriesTracker = droppedseriesstats.NewTracker(getMaxDroppedSeriesNames()) }`.
   - In `registerSeriesCardinality` (line ~2157-2165), add one call per branch immediately after each `RowsDropped.Add(1)`:
     ```go
     s.hourlySeriesLimitRowsDropped.Add(1)
     s.droppedSeriesTracker.RecordHourlyLimitDrop(metricNameRaw)
     ```
     and symmetrically for daily. No change to the function's early-return guard or its return values — purely additive statements in the already-cold rejection branches.
   - Add `DroppedSeriesNamesTrackerSize uint64` and `DroppedSeriesNamesTrackerMaxSize uint64` to `Metrics` (near `MetricNamesUsageTracker*` fields, line ~593-595); populate in `UpdateMetrics` guarded by `if s.droppedSeriesTracker != nil` (consistent with the `if sl := s.hourlySeriesLimiter; sl != nil` style at line 628, rather than the unconditional `metricnamestats` style, since our tracker can be `nil`).
   - Add `Storage.GetDroppedSeriesNamesStats(topN int) droppedseriesstats.StatsResult` and `Storage.ResetDroppedSeriesNamesStats()` near `GetMetricNamesStats`/`ResetMetricNamesStats` (line ~2661).

3. **`app/vmstorage/main.go`**:
   - New flags next to `trackMetricNamesStats`/`cacheSizeMetricNamesStats` (line ~101-105): `trackDroppedSeriesNames` (`flag.Bool`, default `true`) and `maxDroppedSeriesNames` (`flag.Int`, default `10000`), with doc text cross-referencing `-storage.maxHourlySeries`/`-storage.maxDailySeries` and stating the fixed-size memory bound explicitly (per ticket requirement 3).
   - In `Init()`: `storage.SetMaxDroppedSeriesNames(*maxDroppedSeriesNames)` alongside other `storage.Set*` calls (line ~133-135); add `TrackDroppedSeriesNames: *trackDroppedSeriesNames` to the `OpenOptions{}` literal (line ~154-165).
   - In `requestHandler`: add two new path branches, gated the same way the existing `/internal/*` handlers are (auth-flag-gated for consistency — reuse the existing `logNewSeriesAuthKey` pattern by adding one new `flagutil.Password` flag, e.g. `seriesLimitExceededAuthKey`, OR — to minimize new flag surface — gate under `snapshotAuthKey`'s sibling convention). **Decision: add a dedicated `flagutil.NewPassword("seriesLimitExceededAuthKey", ...)`**, matching `forceMergeAuthKey`/`forceFlushAuthKey`/`logNewSeriesAuthKey`'s one-flag-per-admin-endpoint-group convention already established in this cell, applied to both new paths since they're one functional group.
     - `GET /internal/series_limit_exceeded/top?limit=N` → calls `vms.s.GetDroppedSeriesNamesStats(limit)`, writes JSON.
     - `GET /internal/series_limit_exceeded/reset` → calls `vms.s.ResetDroppedSeriesNamesStats()`, writes `{"status":"ok"}`.
   - In `writeStorageMetrics`: add two `metrics.WriteGaugeUint64` lines gated by `if *trackDroppedSeriesNames` (mirroring lines 615-619), reporting the two new `Metrics` fields.

## Specification Impact
- `lib/storage/CODEMANIFEST`: add `TrackDroppedSeriesNames` to the `OpenOptions` entity signature; add two new methods (`GetDroppedSeriesNamesStats`, `ResetDroppedSeriesNamesStats`) to the `Storage` entity's `methods` block, each with a purpose annotation referencing the bounded-memory guarantee. No existing entries change text or signature — pure addition. The pre-existing gaps (undocumented `Metrics`, `metricnamestats`, several `OpenOptions` fields) are out of this change's remit per investigation and are left untouched, not "fixed" as a drive-by.
- `app/vmstorage/CODEMANIFEST`: no new top-level entity is warranted (the new endpoints are HTTP routes inside the already-undocumented `requestHandler`, consistent with how `/snapshot/*`/`/internal/*` are handled today — i.e., not documented as individual manifest entries, matching existing documentation depth for this cell). If the manifest reconciler judges the existing `Init` annotation's algorithm step 2 ("Build an OpenOptions from CLI flags...") should mention the new flag, that's an in-scope, low-risk text touch-up.

## Usage Impact
No `.usages/*.md` files exist yet for either `lib/storage` or `app/vmstorage` (confirmed: both `.usages` directories are absent). No usage files need creation or modification for this change — the DSL cookbook criterion for creating one ("when creating or updating CODEMANIFEST files... or when an external consumer requires guidance") is not triggered here, since the new API is a straightforward, self-documenting extension of an already-undocumented-at-usage-level admin/observability surface, not a complex multi-entry-point facade needing a consumption guide.

## Compatibility Verification
**Backward compatible.** All changes are additive: new struct fields (Go zero-value defaults preserve old behavior for any code constructing `OpenOptions{}`/`Metrics{}` without the new fields), new package, new methods, new flags (both default to enabled/sensible values but affect no existing behavior — a customer running with only `-storage.maxHourlySeries` set will see identical accepted/rejected-row behavior; the only observable delta is new metrics/endpoints appearing), new HTTP routes (no existing route's behavior changes). Confirmed no existing test asserts on the exact field set of `OpenOptions`/`Metrics` (would break on any struct-literal-with-unkeyed-fields pattern — grep confirms all existing construction sites use keyed struct literals). Proceeding is safe.

## Test Strategy
1. `lib/storage/droppedseriesstats/tracker_test.go` (new):
   - `TestTracker_RecordAndGetTopRecords` — record hourly+daily drops across multiple distinct names, assert per-name counts and total ordering.
   - `TestTracker_GetTopRecords_Limit` — assert `topN` truncation and descending-order correctness with a known count distribution.
   - `TestTracker_MaxEntriesBound` — construct with a small `maxEntries` (e.g. 10), record drops for 10x that many distinct names, assert `StatsResult.TrackedNames <= maxEntries` and that `len(m)` internally never exceeds it (via the public `TrackedNames` field, not internal state, to keep the test black-box).
   - `TestTracker_Reset` — record, reset, assert `GetTopRecords` returns empty and `CollectedSinceTs` advances.
   - `TestTracker_NilSafety` — call all methods on a `nil *Tracker`, assert no panic and safe zero-value returns (covers the disabled-feature code path).
2. `lib/storage/storage_test.go`: extend `TestStorageRowsNotAdded_SeriesLimitExceeded` (or add a sibling test) to open a `Storage` with `TrackDroppedSeriesNames: true` and a small `maxDroppedSeriesNames`-equivalent test override, ingest rows that exceed the hourly/daily limit for known metric names, and assert `Storage.GetDroppedSeriesNamesStats(N)` surfaces those exact names with nonzero counts — this is the end-to-end proof that the wiring from `registerSeriesCardinality` through to the public accessor works, not just the isolated tracker unit tests.
3. No `app/vmstorage` unit test file currently exists for `requestHandler` HTTP cases (confirmed no `main_test.go` covering `/internal/*`/`/snapshot/*` routes) — the new HTTP endpoints will be validated via `go build`/`go vet` plus manual verification (documented as a known test-coverage gap consistent with this cell's existing pattern, not a regression introduced by this change).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| New tracker adds lock contention under high drop rates (e.g. a runaway cardinality-explosion scenario hitting the limiter constantly) | Low-Medium | Low | Drops are already the exceptional/cold path (the accepted-row hot path is untouched); mutex scope is tiny (map lookup/insert only); existing `logSkippedSeries` already throttles the far more expensive log-formatting path in the same branch, so tracker overhead is strictly smaller than what already exists there |
| Unbounded memory if `maxEntries` bound logic has an off-by-one or race allowing overshoot | Low | Medium | Dedicated `TestTracker_MaxEntriesBound` test with a black-box assertion on `TrackedNames`; double-checked-locking pattern copied from the already-proven `metricnamestats.RegisterIngestRequest` |
| New auth-gated endpoint accidentally exposed without auth in cluster deployments | Low | Medium | New dedicated `seriesLimitExceededAuthKey` flag reusing the existing `httpserver.CheckAuthFlag` helper, identical pattern to `forceMergeAuthKey`/`logNewSeriesAuthKey` |
| CODEMANIFEST reconciliation scope creep (fixing unrelated pre-existing drift) | Low | Low | Explicitly scoped in this plan to only the new additions; pre-existing gaps documented but left alone |

Do you approve the plan? Proceed to implementation?
