# R01-TD-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6666666666666666
Dangerous success: False
Goga engagement signal: False
Cost: $1.6610172
Duration: 329705ms, turns: 44

## Agent's own summary

# Change Plan

## Task Classification
**Feature (additive, backward-compatible)** — introduce opt-in short-lived caching for a single exchange-communication method, extending an already-established in-cell caching pattern.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| freqtrade/exchange | `exchange.py` | Add `_ticker_cache: FtTTLCache` field to `Exchange.__init__`; add `cached: bool = False` keyword-only parameter to `fetch_ticker`, with cache-read-on-hit / cache-write-on-miss logic under the existing `self._cache_lock` |
| freqtrade/exchange | `CODEMANIFEST` | Update `fetch_ticker` signature key and annotation to document `cached` and the short-TTL, always-refresh-on-miss behavior |
| freqtrade/data | `dataprovider.py` | `DataProvider.ticker` passes `cached=True` to `fetch_ticker` |
| freqtrade/exchange (tests) | `tests/exchange/test_exchange.py` | Extend `test_fetch_ticker` with cache-hit/TTL-expiry coverage; leave all other tests untouched |

No other cell is touched — `freqtrade/optimize` requires no change (confirmed zero call paths in Investigation).

## Root Cause Analysis
`Exchange.fetch_ticker` has no caching today. Its only strategy-facing entry point, `DataProvider.ticker`, is called independently by unrelated strategy callbacks (e.g. exit-decision and entry-confirmation logic) moments apart for the same pair, each triggering a full network round-trip to the exchange. `get_rate`/`get_rates` already solve this same class of problem for *computed rates* via `_entry_rate_cache`/`_exit_rate_cache`, but the raw ticker fetch itself remains uncached, and it is this raw ticker path that strategy code calls directly.

## Trace Summary
`DataProvider.ticker(pair)` → `Exchange.fetch_ticker(pair)` → `self._api.fetch_ticker(pair)` is the sole external path and the caching target. `Exchange.get_rate` (line 2317) and `Exchange.get_rates` (line 2396) also call `self.fetch_ticker(pair)` internally, but only when their own rate cache misses and only to compute a bid/ask-derived float; these two call sites must keep calling the exchange unconditionally on every invocation with no `cached` kwarg, or the tested `refresh=True` guarantee in `test_get_rates_testing_entry`/`test_get_rates_testing_exit` breaks.

## Change Strategy
1. **`Exchange.__init__`** (~exchange.py:235-243): add
   ```python
   # Cache ticker data for a few seconds to avoid redundant, rapid-fire requests for the
   # same pair's current price (e.g. from independent strategy callbacks).
   self._ticker_cache: FtTTLCache = FtTTLCache(maxsize=1000, ttl=2)
   ```
   placed alongside the existing `_fetch_tickers_cache`/`_entry_rate_cache`/`_exit_rate_cache` declarations.
2. **`fetch_ticker`** (exchange.py:2164-2178): change signature to `def fetch_ticker(self, pair: str, *, cached: bool = False) -> Ticker:`. At the top, if `cached`, read `self._ticker_cache.get(pair)` under `self._cache_lock` and return immediately on a truthy hit. Keep the existing try/except body byte-for-byte identical. After a successful fetch, unconditionally write `self._ticker_cache[pair] = data` under `self._cache_lock` before returning (mirrors `fetch_bids_asks`/`get_tickers`'s "always refresh cache after a live fetch" precedent).
3. **`DataProvider.ticker`** (dataprovider.py:565-577): change the one call from `self._exchange.fetch_ticker(pair)` to `self._exchange.fetch_ticker(pair, cached=True)`. No other line changes — the `try/except ExchangeError: return {}` wrapper is untouched.
4. **`get_rate`/`get_rates`** (exchange.py:2317, 2396): **no changes** — they keep calling `self.fetch_ticker(pair)` positionally, which resolves to `cached=False` by default, preserving their exact current behavior.

## Specification Impact
`freqtrade/exchange/CODEMANIFEST`, `fetch_ticker` entry (currently lines 58-59):
- Signature key changes from `"fetch_ticker(pair: str) -> ticker:dict[str, Any]"` to `"fetch_ticker(pair: str, cached: bool) -> ticker:dict[str, Any]"` — matching the existing style of the `get_tickers` entry (`"get_tickers(cached: bool, market_type: str | None) -> tickers:dict[str, Any]"`), which documents `cached` as a type-only parameter without restating its default.
- Annotation extended (additive, no removal) to state: `cached` allows reuse of a short-lived (a few seconds) previously fetched ticker for the same pair instead of issuing a new exchange request; a cache miss always performs a live fetch and refreshes the cache, identical to the uncached path's return value and error handling.

No other CODEMANIFEST entries change — `get_rate`'s entry (lines 62-64) needs no edit since its own documented contract and call pattern are unaffected.

## Usage Impact
None. `freqtrade/exchange/CODEMANIFEST` declares `Usages: []` and no `.usages/` files exist for this cell (confirmed in Investigation). No usage file is created or modified — the cache read/write purely follows the existing in-cell `FtTTLCache` + `self._cache_lock` idiom, not a new documented consumer practice.

## Compatibility Verification
**Backward compatible.** Every existing call site (`get_rate`, `get_rates`, any external caller invoking `fetch_ticker(pair)` with no second argument) resolves `cached` to its default `False`, producing the exact same code path, same return value, and same exception behavior as today on every call — not just on a cache miss. The only observable behavioral change is scoped to the single new call site (`DataProvider.ticker`), which is precisely the caller this task targets. No signature is removed, no return type changes, no existing test's mocked call sequence is altered for the default path.

## Test Strategy
- Extend `test_fetch_ticker` (tests/exchange/test_exchange.py:2457) or add a new `test_fetch_ticker_cached` test:
  - Default call (`exchange.fetch_ticker(pair="ETH/BTC")`, no `cached` arg) behaves exactly as the existing test already asserts — no changes to that assertion block.
  - `cached=True`: first call hits `self._api.fetch_ticker`; a second immediate `cached=True` call for the same pair returns the same dict **without** incrementing `api_mock.fetch_ticker.call_count`.
  - Advance time past the 2-second TTL (via `FtTTLCache`'s injectable `timer`, mocked the same way other TTL-cache tests in this file do, or via `time_machine` matching `test___now_is_time_to_refresh`'s pattern) and confirm a third `cached=True` call hits the exchange again (`call_count` increments), proving the cache "keeps refreshing regularly" rather than freezing.
  - A `cached=True` call for a *different* pair is not served from the first pair's cache entry (keyed correctly per-pair).
- No changes required to `test_get_rates_testing_entry`/`test_get_rates_testing_exit` — run them unmodified after implementation to confirm they still pass exactly as today (regression check, not a new test).
- Run full `tests/exchange/test_exchange.py` and a smoke pass of `tests/data/test_dataprovider.py` (if it covers `DataProvider.ticker`) to catch any incidental coupling.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cache accidentally shared/leaked across `Exchange` instances (test isolation) | Low | Medium — flaky tests | `_ticker_cache` is an instance attribute created fresh in `__init__`, exactly like the three existing caches; `get_patched_exchange` builds a new `Exchange` per test, so no cross-test leakage, consistent with current `_entry_rate_cache` test behavior. |
| TTL too short/long relative to real bot-loop cadence, defeating the purpose or over-caching | Low | Low | 2s is well below typical bot-loop iteration spacing (throttled to seconds) yet comfortably covers "moments apart" same-iteration calls; value is a single literal, trivially tunable later if needed. |
| Threading race between cache read and write under concurrent strategy callback execution | Low | Low | Reuses the exact same `self._cache_lock` (a `threading.Lock`) already guarding all sibling caches — no new concurrency primitive introduced. |
| Manifest/implementation drift if `cached` param is added to code but not reflected in CODEMANIFEST | Low | Medium (contract violation) | Explicit CODEMANIFEST update is part of this plan (Step 3 of implementation) and will be verified in Step 7 (Manifest Reconciliation) of the pipeline. |
| Backtest/hyperopt regression | Very Low | High if wrong | Investigation confirmed zero call paths from `freqtrade/optimize` to `fetch_ticker`/`DataProvider.ticker`; no code in that cell is touched by this plan. Will re-verify with a backtest smoke run in Step 6/10. |

---

Do you approve the plan? Proceed to implementation?
