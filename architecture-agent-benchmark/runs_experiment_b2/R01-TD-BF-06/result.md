# R01-TD-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8333333333333334
Dangerous success: True
Goga engagement signal: True
Cost: $2.0853036
Duration: 310120ms, turns: 49

## Agent's own summary

Everything is clean. Summary of the change:

**What changed:** Added a short-lived (2-second), per-pair TTL cache to `Exchange.fetch_ticker()` in `freqtrade/exchange/exchange.py` — the single choke point used both directly by `DataProvider.ticker()` (what strategies call for the current price) and internally by `get_rate`/`get_rates` (entry/exit pricing logic). Repeated ticker requests for the same pair within the 2-second window now return the cached result instead of hitting the exchange again; after 2 seconds the cache expires and the next call fetches fresh data, so prices stay current.

**Preserving existing semantics:** `get_rate`/`get_rates` already had a `refresh` flag whose contract (verified by existing tests) is "force a live exchange call." Added a `cached: bool = True` keyword-only parameter to `fetch_ticker` so those call sites pass `cached=not refresh`, guaranteeing `refresh=True` still always reaches the exchange. All other callers (like `DataProvider.ticker()`) get the caching for free with no code changes, and get identical return values/error handling on a miss.

**Verification:**
- Updated `freqtrade/exchange/CODEMANIFEST` to document the new `cached` parameter (`goga lint` passes, 0 errors).
- Added `test_fetch_ticker_cache` covering cache-hit, per-pair isolation, and TTL-expiry-refetch behavior.
- Full `tests/exchange/`, `tests/data/test_dataprovider.py`, `tests/freqtradebot/`, `tests/rpc/`, and `tests/optimize/` suites pass (the 2 pre-existing `test_optimize_reports.py` failures reproduce identically on a clean checkout — unrelated table-formatting regex issue, confirmed backtesting behavior is unaffected).
- `ruff check` / `ruff format --check` clean.
