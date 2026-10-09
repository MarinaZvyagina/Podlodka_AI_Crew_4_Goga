# R05-TD-BF-08

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $6.6073322999999995
Duration: 701219ms, turns: 109

## Agent's own summary

Everything builds cleanly and `goga lint` passes with 0 errors. Here's a summary of the implementation.

## Summary

Implemented per-metric-name tracking of samples dropped due to `-storage.maxHourlySeries`/`-storage.maxDailySeries`, modeled closely on the existing `lib/storage/metricnamestats` precedent in this codebase.

**New package `lib/storage/droppedseries`** — a bounded, nil-safe `Tracker`: `Register(metricName)` increments a per-name counter; once a configurable byte budget is exhausted, previously-unseen names stop being tracked while existing ones keep accumulating (never unbounded even with millions of distinct dropped names); `GetTop(limit)` returns top offenders sorted descending with a "collected since" timestamp; `Reset()` clears it. Nil-tracker methods are no-ops.

**`lib/storage/storage.go`** — new `OpenOptions.TrackDroppedSeriesByMetricName` flag; a tracker field that's only allocated when that flag is set *and* a limiter is configured; hooked into both drop branches of `registerSeriesCardinality`; metric-name extraction (`mn.UnmarshalRaw`) only happens when the tracker is non-nil, so it's zero-cost when disabled; new `GetDroppedSeriesStats`/`ResetDroppedSeriesStats` methods; size metrics wired into `Storage.Metrics`/`UpdateMetrics`.

**`app/vmstorage`** — new flags `-storage.trackDroppedSeriesByMetricName` (default true), `-storage.cacheSizeDroppedSeriesTracker`, `-droppedSeriesStatsResetAuthKey`; two new admin HTTP endpoints served directly by vmstorage (same pattern as `/internal/log_new_series` and `/snapshot/*`, not through the vmselect RPC protocol per the ticket's scope): `GET /api/v1/status/dropped_series_stats?limit=N` and `POST /api/v1/admin/status/dropped_series_stats/reset`; cache-size metrics registered in `writeStorageMetrics`.

**Tests**: `lib/storage/droppedseries/tracker_test.go` covers multi-name accumulation, top-N ordering/limit, memory-bound enforcement (10k distinct names against a 2KB budget — bound respected, already-tracked names keep growing), reset, and nil-tracker no-ops. `lib/storage/storage_test.go` adds two integration tests tying real `AddRows` drops through to `GetDroppedSeriesStats`/`ResetDroppedSeriesStats`, and confirming the feature is off by default. All pass, plus the full pre-existing `lib/storage`/`app/vmstorage` suites.

I also smoke-tested the real single-node binary end-to-end (curl against a live server with `-storage.maxHourlySeries=3`): drops were correctly attributed per metric name, the reset endpoint worked, and cache-size metrics appeared on `/metrics`.

CODEMANIFEST files for `lib/storage` and `app/vmstorage` were updated to document the new surface; `goga lint` passes (9 cells, 0 errors).
