We've noticed a pattern in our logs during live and dry-run trading: the current market price for the
same pair sometimes gets requested from the exchange multiple times within a very short window — for
example, a strategy's exit-decision logic and its entry-confirmation logic both asking for the latest
price of the same pair moments apart. Each of these requests goes all the way out to the exchange again,
even though the price fetched a couple of seconds earlier is still essentially current. On exchanges with
tighter rate limits this adds up over many pairs and has already tripped rate-limit warnings for a few
users.

Please add short-lived caching so that repeated requests for the same pair's current price within a short
window reuse the previous result instead of going back out to the exchange every single time. A cache
lifetime of a few seconds is plenty — we don't want trading decisions made on noticeably stale prices, so
whatever you build needs to keep refreshing regularly rather than holding onto one price indefinitely.

This should only affect live/dry-run behavior — backtesting and hyperopt work from historical candle data
and don't fetch live prices this way, so there's nothing to change for them, but please double check
existing backtests still behave exactly as before. Callers of the price-lookup should see no change in
behavior on a cache miss (same return value, same error handling as today) — the only observable
difference should be fewer redundant round-trips to the exchange when the same price is asked for twice
in quick succession.
