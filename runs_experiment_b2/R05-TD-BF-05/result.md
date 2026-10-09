# R05-TD-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $3.1672197
Duration: 636092ms, turns: 63

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive extension of the existing series-cardinality-limiter subsystem)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/storage/droppedseries` (new) | `tracker.go` (new), `tracker_test.go` (new), `CODEMANIFEST` (new) | New bounded per-metric-name drop-count tracker + tests + contract |
| `lib/storage` (existing) | `storage.go`, `storage_test.go`, `CODEMANIFEST` | Additive `Storage`/`OpenOptions` fields, additive methods, drop-path hook, tests, manifest entries |
| `app/vmstorage` (no manifest) | `main.go`, `vmstorage.go` | New flags, `OpenOptions` wiring, new HTTP endpoints, optional `/metrics` lines |

## Root Cause Analysis
Not a defect — a capability gap. Today `registerSeriesCardinality` only exposes an aggregate `hourlySeriesLimitRowsDropped`/`dailySeriesLimitRowsDropped` counter (storage.go:57-58, 2151-2168); there is no per-metric-name breakdown, so support cannot tell customers which metric(s) triggered `-storage.maxHourlySeries`/`-storage.maxDailySeries` without external instrumentation. Confirmed via Investigation: no existing or dead code covers this; `mn.MetricGroup` is the codebase's sole representation of the bare metric name; the pooled `GetMetricName()`/`UnmarshalRaw()`/`PutMetricName()` round-trip is already performed on this exact branch today (via `logSkippedSeries`→`getUserReadableMetricName`), so doing it again is a bounded, already-idiomatic cost on an already-exceptional path.

## Trace Summary
`Storage.add()` (line 2002) and `Storage.RegisterMetricNames()` (line 1789) → `registerSeriesCardinality(metricNameRaw)` (line 2151) → on `sl.Add(metricID) == false` for either `hourlySeriesLimiter` or `dailySeriesLimiter` → increment aggregate atomic counter → (new) `s.registerSeriesLimitExceeded(metricNameRaw)` → `logSkippedSeries(...)` → `return false`. Query path: new `Storage.GetSeriesLimitExceededStats(limit)`/`ResetSeriesLimitExceededStats()`, mirroring `GetMetricNamesStats`/`ResetMetricNamesStats` (line 2661-2669), called from `app/vmstorage`'s own `requestHandler` (line 246) — not through `vmselectapi`/RPC, per explicit scope.

## Change Strategy
1. **`lib/storage/droppedseries/tracker.go`** — implement `Tracker`, `Record`, `Stats`, `DefaultMaxTrackedMetricNames`, `NewTracker`, `IncrementFor`, `GetTopRecords`, `Size`, `Reset`, all nil-receiver-safe, as specified. Self-contained, zero imports beyond stdlib (`sort`, `sync`, `sync/atomic`) and `lib/fasttime` for the timestamp (matches `metricnamestats`' use of `fasttime.UnixTimestamp()`).
2. **`lib/storage/storage.go`**:
   - Add `seriesLimitExceededTracker *droppedseries.Tracker` field (next to the limiters).
   - Add `OpenOptions.TrackSeriesLimitExceededStats bool`.
   - In `MustOpenStorage`, after limiter construction, conditionally construct the tracker only when both the flag is on and at least one limiter exists (avoids a wasted allocation when limits aren't configured at all).
   - Add `SetSeriesLimitExceededTrackerMaxEntries`/`getSeriesLimitExceededTrackerMaxEntries`, mirroring the `MetricNamesStatsCacheSize` pair exactly.
   - In `registerSeriesCardinality`, insert `s.registerSeriesLimitExceeded(metricNameRaw)` into both drop branches, immediately after each aggregate-counter `.Add(1)`.
   - Add private `registerSeriesLimitExceeded` (nil-check first — this is the "no measurable overhead when disabled" guarantee, since it's a single pointer-nil comparison before any pooled unmarshal work happens).
   - Add public `GetSeriesLimitExceededStats(limit int) droppedseries.Stats` and `ResetSeriesLimitExceededStats()`.
   - Add the two optional `Metrics` fields + `UpdateMetrics` population using `Tracker.Size()` (not `GetTopRecords`, to avoid an unnecessary sort on every `/metrics` scrape).
3. **`app/vmstorage/main.go` / `vmstorage.go`**: add the two flags + authKey flag, wire `Init()`, add the two `requestHandler` branches using `encoding/json` for the list-bearing response, optionally extend the `/metrics` writer.
4. **Tests**: unit tests in the new cell; one integration test in `lib/storage/storage_test.go`.
5. **Manifest reconciliation** (Step 7 of the outer pipeline, not this step): new `lib/storage/droppedseries/CODEMANIFEST`; amend `lib/storage/CODEMANIFEST` additively (new field/method annotations + an `Imports` entry for the `Tracker`/`Stats`/`Record` types). `app/vmstorage` has no manifest, so nothing to reconcile there — noted as a scope boundary, not an omission.

## Specification Impact
- **New CODEMANIFEST** for `lib/storage/droppedseries`: `Tracker` Entity (constructor `NewTracker(maxTrackedMetricNames int)`, methods `IncrementFor`, `GetTopRecords`, `Size`, `Reset`), `Record`/`Stats` as plain data types referenced by `GetTopRecords`'s return signature.
- **`lib/storage/CODEMANIFEST` amendment**: add `Imports` block pulling `Tracker`/`Stats` from `path/to/droppedseries` (relative: `droppedseries`); extend the `Storage` entity's `properties`/`methods`/annotations to document `GetSeriesLimitExceededStats`/`ResetSeriesLimitExceededStats` and the new `OpenOptions` field. No existing entries in `lib/storage/CODEMANIFEST` are altered or removed — purely additive per the DSL's "type mutation not required for additive method growth" convention.

## Usage Impact
No `.usages/*.md` files exist yet for either cell (confirmed: `lib/storage/CODEMANIFEST` has an empty `Usages` list, no `.usages/` directory present). Per goga-cookbook, a cell-level `.usages/` file should be authored for `lib/storage/droppedseries` once the CODEMANIFEST exists, documenting for consumers (i.e., `app/vmstorage`) how to call `GetSeriesLimitExceededStats`/`ResetSeriesLimitExceededStats` and interpret `Stats`/`Record` — this will be produced at Step 8 (Usage Reconciliation), not before, since usage files are consumer-facing documentation written after the contract is stable.

## Compatibility Verification
**Backward compatible.** No existing exported signature, return type, HTTP path, flag, `/metrics` line, or manifest guarantee is changed or removed — every change is additive (new struct fields with zero-value-safe defaults, new methods, new flags defaulting to values that preserve current behavior when unset, new HTTP paths). `registerSeriesCardinality`'s existing control flow and return values are untouched.

## Test Strategy
- `lib/storage/droppedseries/tracker_test.go`:
  - Multiple distinct metric names, verify independent per-name counts.
  - `GetTopRecords(limit)` returns correctly sorted (desc by count, tie-break asc by name), respects `limit`, `limit<=0` returns all.
  - `Reset()` clears all counts and advances `SinceTs`.
  - **Memory-bound test**: construct `NewTracker(smallCap)`, call `IncrementFor` with `>> smallCap` distinct names, assert `GetTopRecords(0).TrackedMetricNames <= smallCap` — directly verifies the ticket's "must not cause unbounded memory growth" requirement.
  - Nil-receiver no-op test for all methods (disabled-feature zero-overhead contract).
- `lib/storage/storage_test.go`: new test using a small `MaxHourlySeries`/`MaxDailySeries` and a handful of distinct metric names each with many series (to force repeated per-name drops), asserting `GetSeriesLimitExceededStats` records are non-empty, attributed to the expected names, and that `Σ Records[i].DroppedRows == Metrics.HourlySeriesLimitRowsDropped` (or daily equivalent).
- Existing `TestStorageRowsNotAdded_SeriesLimitExceeded` is left untouched (it doesn't set `TrackSeriesLimitExceededStats`, so the tracker stays `nil` and behavior is identical to today) — confirms non-regression implicitly.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Extra pooled unmarshal on drop path adds latency under a sustained flood of unique dropped series | Low | Low | Only executes on already-exceptional/rare branch (row already being discarded); identical pattern already exists via `getUserReadableMetricName`, just unthrottled here — acceptable since it's bounded by drop rate, not ingest rate |
| Unbounded memory growth if cap logic has an off-by-one or race | Low | Medium | Dedicated unit test asserts cap is respected; map growth gated by a mutex-protected length check before insert |
| New HTTP endpoints reachable without auth leak internal metric names | Low | Low | GET stats endpoint follows the same pattern as the already-unauthenticated `/api/v1/status/metric_names_stats` (read-only, low sensitivity); reset endpoint gated by new authKey flag matching `forceFlushAuthKey` convention |
| CODEMANIFEST drift if a future contributor edits `registerSeriesCardinality` without updating the new manifest entries | Low | Low | Handled by Step 9 (Drift Analysis) of the outer pipeline going forward, same as all existing `lib/storage` entries |

---

Do you approve the plan? Proceed to implementation?
