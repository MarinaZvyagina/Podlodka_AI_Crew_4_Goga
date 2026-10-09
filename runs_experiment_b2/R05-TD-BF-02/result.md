# R05-TD-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $2.6508224999999994
Duration: 468767ms, turns: 62

## Agent's own summary

# Change Plan

## Task Classification
Feature (additive extension of the existing series-cardinality-limiter subsystem)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| lib/storage | `storage.go` (new field, `OpenOptions` field, `Metrics` fields, hook in `registerSeriesCardinality`, two new public methods); new `droppedseries/tracker.go` + `droppedseries/tracker_test.go` | New internal subpackage + wiring; no existing method signatures change |
| app/vmstorage | `main.go` (new flags, `OpenOptions` wiring, new `requestHandler` routes, new gauges in `writeStorageMetrics`) | Additive flags/routes only |

## Root Cause Analysis
Feature gap, not a bug: `registerSeriesCardinality` already knows exactly which raw metric name is rejected and why (hourly vs daily), but today it only bumps an aggregate counter and throttled log line, discarding the name. Support has no way to answer "which metric(s) hit the limit" without customer-side digging.

## Trace Summary
- `AddRows` → `registerSeriesCardinality(mr.MetricNameRaw)` (storage.go, two call sites; the second is skipped by a same-name fast path, so no double counting)
- `registerSeriesCardinality`: unchanged top-level nil-limiter fast path; each of the two rejection branches (`hourlySeriesLimiter`/`dailySeriesLimiter`) gains one additional call into the new tracker
- `MustOpenStorage` gains a third conditionally-constructed tracker (alongside `tsidCache`/`metricsTracker`), following the exact `if opts.Xxx > 0 { s.yyy = ... }` shape already used for `hourlySeriesLimiter`/`dailySeriesLimiter` themselves (storage.go:240-245)
- `app/vmstorage.Init` → builds `storage.OpenOptions{...}` → `vms.requestHandler` gains new path-matched branches, following the existing flat-`if`-chain/`CheckAuthFlag` convention

## Change Strategy
1. **New subpackage `lib/storage/droppedseries`** (`tracker.go`): nil-receiver-safe `Tracker` with `NewTracker`, `Add`, `GetTopRecords`, `Reset`, `UpdateMetrics`. Bounded exactly like `metricnamestats.Tracker.cacheIsFull()`: once `currentSizeBytes > maxSizeBytes`, new never-seen metric names are dropped from tracking (existing entries keep incrementing, so already-known offenders stay accurate). No tenant fields, no disk persistence — deliberately leaner than `metricnamestats.Tracker` per the Investigation Report's rejected-hypothesis reasoning.
2. **`lib/storage/storage.go`**:
   - Add `droppedSeriesTracker *droppedseries.Tracker` field to `Storage`.
   - Add `MaxDroppedSeriesByNameCacheSize int` to `OpenOptions` (bytes; `<= 0` → tracker stays `nil` → every call is a single nil-check → satisfies "zero measurable overhead when disabled"; zero value matches Go's default, so every existing `OpenOptions{...}` literal in current tests/callers is unaffected).
   - In `MustOpenStorage`, construct the tracker only when `opts.MaxDroppedSeriesByNameCacheSize > 0`.
   - Add private helper `registerSeriesLimitExceeded(metricNameRaw []byte)`: nil-check on `s.droppedSeriesTracker` first (fast return when disabled), else pooled `GetMetricName()`/`mn.UnmarshalRaw()`/`droppedSeriesTracker.Add(mn.MetricGroup)`/`PutMetricName()`. Called from both rejection branches in `registerSeriesCardinality`, after the existing `Add(1)` on the aggregate counter, before/alongside the existing `logSkippedSeries` call.
   - Add `Storage.GetDroppedSeriesStats(limit int) droppedseries.StatsResult` and `Storage.ResetDroppedSeriesStats()`, both nil-safe passthroughs (mirroring `GetMetricNamesStats`/`ResetMetricNamesStats` at storage.go:2662/2668).
   - Extend `Metrics` with `DroppedSeriesByNameTrackerSize/-SizeBytes/-SizeMaxBytes uint64` (mirrors `MetricNamesUsageTracker*`), populated in `UpdateMetrics` via `droppedSeriesTracker.UpdateMetrics(...)`.
3. **`app/vmstorage/main.go`**:
   - New flag `storage.maxDroppedSeriesByNameCacheSize` (`flagutil.NewBytes`, default 1MiB, doc note "0 disables") → `opts.MaxDroppedSeriesByNameCacheSize = ....IntN()`.
   - New auth-key flag (mirrors `forceFlushAuthKey`) for the reset route only; the read-only stats route needs no dedicated auth key (same posture as read-only metrics/snapshot-list-style endpoints already unauthenticated beyond the global `-httpAuth.*`).
   - Two new branches in `vms.requestHandler`: `GET /internal/series_limit_exceeded_stats?topN=N` (JSON via `encoding/json`, following `jsonResponseError` conventions for malformed `topN`), `POST /internal/series_limit_exceeded_stats/reset` (auth-gated).
   - Two new gauges in `writeStorageMetrics`, mirroring the three existing `vm_cache_size*{type="storage/metricNamesStatsTracker"}` lines.
4. **Tests**: package-level unit tests for `droppedseries.Tracker` (aggregation, top-N + limit, memory bound, reset, nil safety) + one storage-level integration test proving the wiring (drops recorded end-to-end, and disabled-by-zero-value leaves `GetDroppedSeriesStats` empty).

## Specification Impact
- `lib/storage/CODEMANIFEST`: add two new methods to the existing `"Storage(path: string, opts: OpenOptions)"` entity — `GetDroppedSeriesStats` and `ResetDroppedSeriesStats` — and extend the `OpenOptions(...)` signature/annotation with the new field. No existing entries change meaning; this is pure addition, consistent with `god_package`'s instruction to document the real (messy) shape as-is rather than idealize.
- `lib/storage/droppedseries` gets **no** CODEMANIFEST, matching `metricnamestats`'s current undocumented-internal-subpackage precedent (goga schema confirms `metricnamestats` is not a child cell today).
- `app/vmstorage` CODEMANIFEST currently documents only `DataPath`, `Init`, `Stop`, `VMStorage`, `VMStorageWithTenantID` at the type level, with no per-route documentation of `requestHandler`'s internal paths (`/internal/force_merge` etc. aren't individually listed either) — so the new routes need no CODEMANIFEST edit, consistent with existing sibling routes.
- No conflict with either CODEMANIFEST's documented algorithms found.

## Usage Impact
No `.usages/*.md` files exist yet for either cell (repo-wide `find` shows none under `lib/storage/.usages` or `app/vmstorage/.usages`), so none require updates. None will be added — this feature is an internal/operational addition, not a new consumer-facing facade pattern that would warrant a new practice file.

## Compatibility Verification
**Backward compatible.** All changes are additive: new struct fields default to zero values that reproduce today's behavior exactly (tracker absent, no new HTTP routes matched unless explicitly requested by path, no existing counters/log lines altered). No existing method signature, return type, or documented algorithm changes.

## Test Strategy
- `lib/storage/droppedseries/tracker_test.go`:
  - Multiple distinct metric names each dropped multiple times → per-name counts correct.
  - `GetTopRecords(limit)` returns correctly sorted, correctly capped results.
  - Memory bound: seed tracker with a small `maxSizeBytes`, add more distinct names than fit → `currentSizeBytes` never exceeds bound (within one entry's worst-case overhead), item count stays bounded, already-tracked names keep incrementing after the bound is hit.
  - `Reset()` clears state and updates `CollectedSinceTs`.
  - Nil `*Tracker` receiver: all methods no-op/zero-value safely.
- `lib/storage/storage_test.go`: extend/add alongside `TestStorageRowsNotAdded_SeriesLimitExceeded` — ingest a small fixed set of metric names beyond `MaxHourlySeries`/`MaxDailySeries`, assert `GetDroppedSeriesStats` reports the expected names/counts; separately assert `MaxDroppedSeriesByNameCacheSize <= 0` (the zero-value default) leaves `GetDroppedSeriesStats` empty even though rows are still dropped by the limiter (proving no overhead/behavior change for existing callers).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Extra `UnmarshalRaw` per dropped row adds CPU on drop-heavy workloads | Medium (only when limiter is actively rejecting, i.e., already an exceptional/throttled scenario) | Low | Gated behind nil-check on `droppedSeriesTracker`; only runs when feature explicitly enabled; drop path is inherently much lower volume than accepted-row hot path |
| Bound accounting (`storeOverhead`-style constant) drifts from real map memory use | Low | Low | Use the same conservative fixed per-entry overhead constant approach already validated in `metricnamestats` |
| New flag name collides with existing flag namespace | Low | Low | `storage.maxDroppedSeriesByNameCacheSize` checked against current `app/vmstorage/main.go` flag list — no collision |

Do you approve the plan? Proceed to implementation?
