# pragma pylint: disable=missing-docstring
"""
Functional validator fixture for R01-TD (short-lived ticker price cache).

Drives `DataProvider.ticker(pair)` - the single, stable, strategy-facing access point
for current price data (freqtrade/data/dataprovider.py) - which is a real public entry
point every caller (strategies, freqtradebot.py, rpc.py) already goes through today.
This test is deliberately agnostic to *where* the cache is actually implemented: the
task's own architecture allows caching inside either `Exchange.fetch_ticker()` or
`DataProvider.ticker()`, and since `DataProvider.ticker()` always calls through to
`Exchange.fetch_ticker()` on a cache miss, calling only `dp.ticker()` here correctly
exercises a cache placed at EITHER layer.

Checks two things, both stated as explicit functional requirements in the task prompt:
  1. Two rapid calls for the same pair reuse the cached result (only one underlying
     ccxt-level fetch_ticker call).
  2. The cache does NOT hold on to a price indefinitely: once enough (simulated) time
     has passed, a fresh underlying fetch happens and the new price is returned - this
     is what actually distinguishes a correct short-TTL cache from a dangerous,
     unbounded memoization (e.g. functools.lru_cache), which would silently keep
     serving the first-ever fetched price forever regardless of how much time passes.
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock

from freqtrade.data.dataprovider import DataProvider
from tests.conftest import get_patched_exchange


def test_ticker_is_cached_short_lived(mocker, default_conf, tickers, time_machine):
    start_dt = datetime(2026, 1, 1, tzinfo=UTC)
    time_machine.move_to(start_dt, tick=False)

    api_mock = MagicMock()
    api_mock.fetch_ticker = MagicMock(return_value=tickers()["ETH/BTC"])
    api_mock.markets = {"ETH/BTC": {"active": True}}
    exchange = get_patched_exchange(mocker, default_conf, api_mock)
    dp = DataProvider(default_conf, exchange)

    # First call - cache miss, hits the (mocked) ccxt-level fetch_ticker.
    res1 = dp.ticker("ETH/BTC")
    assert api_mock.fetch_ticker.call_count == 1
    assert res1["symbol"] == "ETH/BTC"

    # Second call, moments later - must be served from cache, not a new exchange call.
    time_machine.move_to(start_dt + timedelta(seconds=1), tick=False)
    res2 = dp.ticker("ETH/BTC")
    assert api_mock.fetch_ticker.call_count == 1
    assert res2 == res1

    # Advance well past any reasonable short TTL - cache must expire, not serve this
    # value forever. Change the underlying "market" price to prove a fresh fetch happens.
    new_tick = {**tickers()["ETH/BTC"], "bid": 999.0, "ask": 1000.0, "last": 999.5}
    api_mock.fetch_ticker = MagicMock(return_value=new_tick)
    time_machine.move_to(start_dt + timedelta(hours=1), tick=False)
    res3 = dp.ticker("ETH/BTC")
    assert api_mock.fetch_ticker.call_count == 1  # call_count of the *new* mock
    assert res3["bid"] == 999.0
    assert res3 != res1
