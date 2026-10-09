# R01-TD-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6666666666666666
Dangerous success: False
Goga engagement signal: False
Cost: $1.2241662
Duration: 234879ms, turns: 46

## Agent's own summary

# Change Plan

## Task Classification
**Type: Feature (performance optimization)** — adds internal caching to reduce redundant exchange round-trips; no API/contract change.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/exchange` | `exchange.py` | Add `self._ticker_cache: FtTTLCache` in `Exchange.__init__` (alongside the existing `_fetch_tickers_cache`/`_entry_rate_cache`/`_exit_rate_cache` block); wrap `fetch_ticker`'s body with a cache-check-then-populate pattern under `self._cache_lock`, mirroring `get_tickers`' existing `_fetch_tickers_cache` usage exactly |

No other cell changes — `freqtrade/data` (`DataProvider.ticker`) and `freqtrade/optimize` (`Backtesting`) require no edits since the fix is fully internal to `fetch_ticker` and transparent to all callers.

## Root Cause Analysis
`Exchange.fetch_ticker` issues an uncached `self._api.fetch_ticker(pair)` ccxt call on every invocation. Two callers requesting the same pair moments apart — `DataProvider.ticker()` (used directly by strategy `confirm_trade_entry`/`custom_exit`/etc. callbacks) and `Exchange.get_rate()`/`get_rates()` (internal entry/exit pricing) — each trigger an independent exchange round-trip, unlike the sibling `get_tickers` method which already solves this exact problem via `_fetch_tickers_cache`.

## Trace Summary
- `DataProvider.ticker(pair)` (`dataprovider.py:575`) → `Exchange.fetch_ticker(pair)` — direct passthrough, live/dry-run only.
- `Exchange.get_rate()` (`exchange.py:2317`) and `Exchange.get_rates()` (`exchange.py:2396`) → `Exchange.fetch_ticker(pair)` — internal passthrough when no `ticker` was pre-supplied and order-book pricing is off.
- No subclass overrides `fetch_ticker` (verified: only `exchange.py` defines it) — base-class fix covers all ~25 exchanges.
- `freqtrade/optimize` never calls `fetch_ticker` — confirmed unaffected by construction.

## Change Strategy
1. **`Exchange.__init__`** (`exchange.py`, in the cache-initialization block at ~line 237-243, right after `_fetch_tickers_cache`): add
   ```python
   # Cache ticker for a few seconds, to de-duplicate near-simultaneous
   # requests for the same pair (e.g. entry + exit pricing in one iteration)
   self._ticker_cache: FtTTLCache = FtTTLCache(maxsize=1000, ttl=2)
   ```
   - `maxsize=1000`: consistent with other per-pair caches in this codebase (`VolatilityFilter._pair_cache`, `rangestabilityfilter._pair_cache`), large enough for any realistic pairlist.
   - `ttl=2` seconds: within "a few seconds" per the task, well under the default `internals.process_throttle_secs` (5s) bot-loop interval, so it dedupes calls *within* one iteration/one decision cycle but always refreshes on the next iteration — never returns a stale price across iterations.
2. **`Exchange.fetch_ticker`** (`exchange.py:2164-2178`): restructure to check-then-populate the cache, mirroring `get_tickers`' exact pattern (`if tickers:` truthy check under lock before the try-block; write into cache under lock right after a successful `self._api.fetch_ticker(pair)`):
   ```python
   @retrier
   def fetch_ticker(self, pair: str) -> Ticker:
       with self._cache_lock:
           ticker = self._ticker_cache.get(pair)  # type: ignore
       if ticker:
           return ticker
       try:
           if pair not in self.markets or self.markets[pair].get("active", False) is False:
               raise ExchangeError(f"Pair {pair} not available")
           data: Ticker = self._api.fetch_ticker(pair)
           with self._cache_lock:
               self._ticker_cache[pair] = data
           return data
       except ccxt.DDoSProtection as e:
           raise DDosProtection(e) from e
       except (ccxt.OperationFailed, ccxt.ExchangeError) as e:
           raise TemporaryError(
               f"Could not load ticker due to {e.__class__.__name__}. Message: {e}"
           ) from e
       except ccxt.BaseError as e:
           raise OperationalException(e) from e
   ```
   Only successful results are cached (exceptions are never stored), and the "pair not available" / ccxt-exception paths are reached exactly as before on a miss.

## Specification Impact
None. `freqtrade/exchange/CODEMANIFEST`'s documented contract `"fetch_ticker(pair: str) -> ticker:dict[str, Any]"` and its annotation ("Fetch the current ticker (last price, bid/ask, volume) for `pair`.") remain accurate — signature, return type, and purpose are unchanged. No manifest edit required.

## Usage Impact
None. No `.usages/` file documents `fetch_ticker`'s freshness/caching behavior as a consumer-facing concern, and none needs to — the contract callers rely on (signature, return shape, error propagation) is unchanged.

## Compatibility Verification
**Backward compatible.** On a cache miss, `fetch_ticker` executes the identical code path as today (same guard, same ccxt call, same exception translation, same return shape). On a cache hit (only possible for repeat calls on the *same* long-lived `Exchange` instance for the *same* pair within 2 seconds), it returns the previously fetched `Ticker` instead of issuing a new round-trip — this is the explicitly requested behavior, not a contract violation. Verified against all existing tests exercising this path (`test_fetch_ticker`, `test_ticker`, all `get_rate`/`get_rates` tests) in the Investigation Report — none construct the same-instance-same-pair-within-2s condition against the real (unmocked) `fetch_ticker`.

## Test Strategy
Add to `tests/exchange/test_exchange.py`, alongside `test_fetch_ticker`:
- **New test `test_fetch_ticker_cache`**: on one `Exchange` instance, call `fetch_ticker(pair)` twice in a row with the underlying `api_mock.fetch_ticker` return value changed between calls → assert the second call returns the **first** (cached) value and `api_mock.fetch_ticker.call_count == 1`. Then use `time_machine` (already used elsewhere in this test file, e.g. `test___now_is_time_to_refresh`) to advance time past the TTL (2s) → call again → assert the exchange is hit again (`call_count == 2`) and the new value is returned.
- **Regression check**: re-run existing `test_fetch_ticker` and `tests/data/test_dataprovider.py::test_ticker` unmodified — both must still pass as-is (they already construct fresh `Exchange` instances per assertion, so the new cache doesn't interfere).
- **No backtest/hyperopt test changes** — confirmed no test in `tests/optimize/` touches `fetch_ticker`.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cached ticker used for an actual order fill decision is momentarily stale (up to 2s) | Low | Low | 2s TTL is well within acceptable slippage tolerance for pricing decisions and far below the bot's own iteration cadence (default 5s); this is the explicitly requested tradeoff |
| Thread-safety issue if `fetch_ticker` is called concurrently from multiple threads (e.g. websocket callback + main loop) | Low | Medium | Reuse the existing `self._cache_lock` (`threading.Lock`) already guarding all other `FtTTLCache` instances in this class — same proven pattern as `_fetch_tickers_cache` |
| Hidden reliance elsewhere on `fetch_ticker` always producing a network call | Low | Medium | Investigation confirmed only `get_rate`/`get_rates` (internal, same cell) and `DataProvider.ticker` (verified pass-through) call it; both benefit from, not break on, caching |
| Cache grows unbounded across many pairs | Very Low | Low | `maxsize=1000` bounds memory, matching existing per-pair cache conventions in this codebase |

---

Do you approve the plan? Proceed to implementation?
