# R05-TD-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r05-v1
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $2.8457996999999997
Duration: 436250ms, turns: 62

## Agent's own summary

# Change Plan

## Task Classification
Feature (additive) — new observability capability layered onto an existing, unmodified drop path.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| lib/storage/droppedseries (**new cell**) | `CODEMANIFEST` (new), `tracker.go` (new), `tracker_test.go` (new) | New package: bounded, in-memory, fill-until-full, nil-safe `Tracker` that records per-metric-name drop counts and answers top-N queries |
| lib/storage | `storage.go`, `storage_test.go` | Add `droppedSeriesTracker` field, `OpenOptions.TrackDroppedSeriesByMetricName`, size-override plumbing (`SetDroppedSeriesCacheSize`/`getDroppedSeriesCacheSize`), call `registerDroppedSeries` from `registerSeriesCardinality`, add `Metrics` fields + `UpdateMetrics` wiring, add `GetDroppedSeriesStats`/`ResetDroppedSeriesStats` facade methods; extend the existing series-limit test |
| app/vmstorage | `main.go`, `vmstorage.go` (only if a `VMStorage`-level accessor is wanted) | New flags `-storage.trackDroppedSeriesByMetricName` and `-storage.cacheSizeDroppedSeriesByMetricName`; wire into `Init()`; add a read-only JSON HTTP endpoint in `requestHandler`; add the tracker's size gauges to `writeStorageMetrics` |

## Root Cause Analysis
Not a defect — confirmed gap from Investigation Report: `registerSeriesCardinality` (storage.go:2151) drops rows on hitting `-storage.maxHourlySeries`/`-storage.maxDailySeries` and only increments an aggregate atomic counter; no artifact records which metric name caused the drop.

## Trace Summary
Single, exhaustive drop site: `Storage.add()` / `Storage.RegisterMetricNames()` → `registerSeriesCardinality(mr.MetricNameRaw)` → on `bloomfilter.Limiter.Add` failure → today: atomic counter increment + throttled log. This is the only integration point required. `MustOpenStorage`/`OpenOptions`/`UpdateMetrics`/`MustClose` are the only other lib/storage touch points, all following the exact pattern already used for `s.metricsTracker` (metricnamestats) and `s.metadataStorage` (metricsmetadata).

## Change Strategy

1. **New cell `lib/storage/droppedseries`** (package `droppedseries`), modeled on metricnamestats' `fill_until_full_no_eviction` policy but without tenant-awareness or disk persistence (matching metricsmetadata's "in-memory only" trait):
   - `Tracker` — internal `map[string]*counterItem` behind a `sync.Mutex`, plus `currentSizeBytes atomic.Uint64` and `maxSizeBytes uint64`.
   - `NewTracker(maxSizeBytes int) *Tracker`.
   - `(t *Tracker) Record(metricName []byte)` — nil-safe; if `t == nil` no-op; if cache full (`currentSizeBytes > maxSizeBytes`) and name not already tracked, silent no-op (no eviction, ever — this alone satisfies the memory-bound requirement); otherwise increments the existing entry's counter or creates a new one and adds `len(metricName) + recordOverhead` to `currentSizeBytes`.
   - `(t *Tracker) TopRecords(limit int) []Record` — nil-safe (returns nil); snapshot + sort by count desc (name asc as tiebreak for determinism) + truncate to `limit` (`<=0` = unlimited, matching metricsmetadata's `Get(limit)` convention).
   - `(t *Tracker) Reset()` — nil-safe; clears the map and resets `currentSizeBytes`.
   - `(t *Tracker) UpdateMetrics(dst *TrackerMetrics)` — nil-safe; populates current item count/bytes/max bytes, mirroring `metricnamestats.TrackerMetrics`/`metricsmetadata.MetadataStorageMetrics` shape exactly.
   - `Record{MetricName string; DroppedRowsCount uint64}`, `TrackerMetrics{CurrentSizeBytes, CurrentItemsCount, MaxSizeBytes uint64}` — plain data types, no behavior.
   - No background goroutine, no `MustClose` needed (nothing to flush — simpler than both sibling cells since there's no persistence).

2. **lib/storage/storage.go**:
   - `Storage.droppedSeriesTracker *droppedseries.Tracker` field.
   - `OpenOptions.TrackDroppedSeriesByMetricName bool`.
   - In `MustOpenStorage`: `if opts.TrackDroppedSeriesByMetricName { s.droppedSeriesTracker = droppedseries.NewTracker(getDroppedSeriesCacheSize()) }`.
   - `maxDroppedSeriesCacheSize`/`SetDroppedSeriesCacheSize`/`getDroppedSeriesCacheSize()` — mirrors `maxMetricNamesStatsCacheSize` pattern exactly, but default (when unset/`<=0`) is a **fixed** sensible constant (1 MiB) rather than a `memory.Allowed()` fraction, since the tracked set (distinct offending metric names) does not scale with total installation memory the way TSID/metricName caches do — this is the most literal reading of the ticket's "bounded by a sensible fixed default."
   - In `registerSeriesCardinality`: on each of the two drop branches (hourly, daily), call a new unexported helper `s.registerDroppedSeries(metricNameRaw)` *after* the existing atomic-counter increment, before/alongside `logSkippedSeries`. `registerDroppedSeries` checks `s.droppedSeriesTracker == nil` first (zero-cost when disabled), else `GetMetricName()`/`mn.UnmarshalRaw(metricNameRaw)`/`s.droppedSeriesTracker.Record(mn.MetricGroup)`/`PutMetricName(mn)` — same primitive `getUserReadableMetricName` already uses, invoked only on the already-exceptional drop path.
   - `Metrics` struct: add `DroppedSeriesTrackerSize`, `DroppedSeriesTrackerSizeBytes`, `DroppedSeriesTrackerSizeMaxBytes uint64`. `UpdateMetrics`: populate via `s.droppedSeriesTracker.UpdateMetrics(&dstm)` (nil-safe).
   - New exported facade: `Storage.GetDroppedSeriesStats(limit int) []droppedseries.Record` and `Storage.ResetDroppedSeriesStats()`, mirroring `GetMetricNamesStats`/`ResetMetricNamesStats` exactly.
   - No change to `MustClose` beyond what nil-safety already handles (no resources to release).

3. **app/vmstorage**:
   - `main.go`: two new flags, `Init()` wiring (`storage.SetDroppedSeriesCacheSize(...)`, `OpenOptions.TrackDroppedSeriesByMetricName: *trackDroppedSeriesByMetricName`), three new gauge lines in `writeStorageMetrics` gated by `if *trackDroppedSeriesByMetricName` (mirrors the existing `trackMetricNamesStats` gate).
   - `requestHandler`: new read-only case (e.g. `/internal/droppedSeriesStats`, GET, optional `topN` query param, default e.g. 10) returning `{"status":"ok","droppedSeries":[{"metricName":"...","droppedRowsCount":N}, ...]}`. No auth-key gating, matching the existing precedent that the read-only `/api/v1/status/metric_names_stats` endpoint is also unauthenticated (only its mutating `/reset` counterpart is auth-gated) — and no reset endpoint is added at all, since the ticket only requires querying, keeping scope minimal.

## Specification Impact
- New `CODEMANIFEST` at `lib/storage/droppedseries/` documenting `Tracker`, `Record`, `TrackerMetrics`, with a `fill_until_full_no_eviction`-style Usages entry explaining the bounded/no-eviction/nil-safe design (cross-referencing, not duplicating, the metricnamestats precedent by name only, since Imports between sibling cells with no dependency relationship are not warranted).
- `lib/storage`'s CODEMANIFEST body gains new entries for `GetDroppedSeriesStats`/`ResetDroppedSeriesStats` methods on the existing `Storage` type and an `Imports` entry for the new `droppedseries` cell's `Record`/`TrackerMetrics` types. No existing entries change semantically — `OpenOptions` signature gains one more field, additive only.
- `app/vmstorage`'s CODEMANIFEST (if it documents `Init`/flags at this granularity) gains the new flags; existing entries unchanged.

## Usage Impact
No existing `.usages` files exist for lib/storage, metricnamestats, or metricsmetadata (confirmed by directory listing — these cells currently ship no `.usages/` directory), so none require updates. No new `.usages` file is planned for the new cell either, consistent with sibling convention (CODEMANIFEST annotations suffice; the only consumers are lib/storage and app/vmstorage, which get their contract directly from the new CODEMANIFEST).

## Compatibility Verification
**Backward compatible.** Every change is additive: new struct fields (Go zero-value = disabled/absent), new package, new exported methods, new flags with safe defaults, new HTTP path. No existing signature, return type, file path, log line, or `/metrics` line is altered or removed. `TestStorageRowsNotAdded_SeriesLimitExceeded` and all other existing tests continue to pass unmodified (verified no existing assertion touches the new fields).

## Test Strategy
1. **lib/storage/droppedseries/tracker_test.go** (new, satisfies ticket's 3 explicit test requirements):
   - Record drops for multiple distinct metric names with different counts → verify each name's count independently.
   - `TopRecords(limit)` returns the correct top-N ordered by count descending, and respects `limit`.
   - Memory bound: construct a `Tracker` with a small `maxSizeBytes`, record enough distinct names to exceed it, assert tracked-entry count stops growing (new names beyond the bound are silently dropped) while already-tracked entries keep counting — directly exercises `fill_until_full_no_eviction`.
   - Nil-receiver no-op safety for all methods (`Record`, `TopRecords`, `Reset`, `UpdateMetrics` on a `nil *Tracker`).
2. **lib/storage/storage_test.go**: extend `TestStorageRowsNotAdded_SeriesLimitExceeded` (or add a sibling test using the same `testGenerateMetricRows` helper) to assert `s.GetDroppedSeriesStats(0)` contains entries summing to `HourlySeriesLimitRowsDropped`/`DailySeriesLimitRowsDropped`, and that disabling `TrackDroppedSeriesByMetricName` yields an empty result with the limiter still functioning identically (proves the toggle doesn't change drop behavior, only observability).
3. No new test at the `app/vmstorage` HTTP-handler layer — consistent with existing convention (the `/snapshot/*`, `/internal/force_merge` etc. cases in `requestHandler` are likewise untested at that layer; the behavior under test lives in `lib/storage`).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Per-drop `UnmarshalRaw` cost matters under sustained high-churn drop storms | Low | Medium | Gated behind nil-check (opt-out available); only runs on already-discarded rows, not the accepted-row hot path; matches cost already paid by throttled `getUserReadableMetricName` |
| Fixed 1 MiB default too small/large for some installs | Low | Low | Exposed as an overridable flag (`-storage.cacheSizeDroppedSeriesByMetricName`), same override mechanism as every other cache in this file |
| New cell duplicates metricnamestats logic, causing future drift | Low | Low | Deliberately not shared (different lifecycle: no tenant, no persistence) — documented explicitly in the new CODEMANIFEST's Description so future readers understand this is an intentional sibling, not an oversight |
| HTTP endpoint path collides with a future real API | Low | Low | Namespaced under `/internal/` alongside existing internal-only admin endpoints (`/internal/force_merge`, `/internal/log_new_series`) |

---

Do you approve the plan? Proceed to implementation?
