A number of users trade several pairs that are all priced against, or backed by, the same underlying
currency (for example a handful of BTC-margined futures, or several coins that are all quoted in the
same stablecoin). They've asked for a safety limit: don't let the bot commit more than a configurable
share of the total trading capital to positions that share the same underlying currency at the same
time, even if each individual trade looks perfectly fine in isolation. The concern is concentration risk
— if that one underlying currency moves against them, several open positions get hit at once.

Please add support for this kind of exposure cap. The user should be able to configure, per strategy,
what fraction of tradable capital may be committed to a single underlying currency across all
simultaneously open trades. When opening a new trade would push the combined exposure to that currency
over the configured limit, the new trade should not be opened (or should be sized down to fit under the
limit — whichever is more consistent with how we already handle similar sizing limits). The reason for
skipping or resizing the trade should be visible to the user the same way other entry-sizing decisions
already are.

Importantly, this needs to behave identically whether someone is running the bot live/dry-run or running
a backtest over historical data with the same strategy and config. We've been burned before by features
that quietly only worked in one of those two modes because they were only wired into one code path —
that's exactly the kind of inconsistency we're trying to avoid this time, since traders rely on backtest
results reflecting how the bot will actually behave live.
