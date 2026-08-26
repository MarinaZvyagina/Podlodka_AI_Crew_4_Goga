# pragma pylint: disable=missing-docstring, protected-access
"""
Functional validator fixture for R01-TB (per-underlying-currency exposure cap).

Verifies that opening a new trade which would push the combined open exposure to a
shared base currency above the configured fraction of tradable capital is resized down
IDENTICALLY whether the code path is:
  (1) live/dry-run - FreqtradeBot.execute_entry()
  (2) backtesting - Backtesting._enter_trade()

Both are real, stable public entry points every correct implementation must route a
new trade through - this is not a private helper name specific to one candidate.

The `max_pair_exposure` config key name matches the ground-truth reference
implementation (controls/task_B_positive.diff and task_B_negative.diff both use it);
since the task's own architectural constraints require this to be an additive,
opt-in, per-strategy config value, and both real diffs converge on this name, it is
used here as the black-box activation switch.

NOTE on the "identical live vs. backtest" requirement: the task prompt explicitly lists
this as a FUNCTIONAL requirement ("this needs to behave identically whether someone is
running the bot live/dry-run or running a backtest..."), not merely an architectural
nicety. Consequently, test_max_pair_exposure_backtesting below is a genuine functional
assertion, not an architecture check - an implementation that only wires the cap into
freqtradebot.py (and leaves backtesting.py untouched) is expected to FAIL this half of
the functional check, even though the live-only half above it still passes. This is a
deliberate, documented case (see FUNCTIONAL_VALIDATORS.md) where the negative/trap
control is expected to functionally FAIL, not merely fail architecture conformance.

Both pairs used below ("XRP/BTC" and "XRP/USDT") share the same base currency (XRP) but
have different quote currencies - mirroring the "several pairs backed by the same
underlying currency" scenario described in the task.
"""

import pandas as pd
import pytest

from freqtrade.freqtradebot import FreqtradeBot
from freqtrade.persistence import LocalTrade, Trade
from tests.conftest import EXMS, get_patched_freqtradebot, patch_exchange


def test_max_pair_exposure_freqtradebot(mocker, default_conf, fee, limit_order_open) -> None:
    """
    Live/dry-run path: FreqtradeBot.execute_entry() must resize a second trade in a pair
    that shares a base currency with an already-open trade, once the combined exposure to
    that base currency would exceed max_pair_exposure * total tradable capital.
    """
    default_conf["max_open_trades"] = 2
    default_conf["stake_amount"] = 150
    default_conf["dry_run_wallet"] = 1000
    default_conf["tradable_balance_ratio"] = 0.99
    default_conf["max_pair_exposure"] = 0.2  # 20% of ~990 => 198

    patch_exchange(mocker)
    freqtrade: FreqtradeBot = get_patched_freqtradebot(mocker, default_conf)
    freqtrade.strategy.confirm_trade_entry = mocker.MagicMock(return_value=True)

    mocker.patch.multiple(
        EXMS,
        get_rate=mocker.MagicMock(return_value=1.0),
        fetch_ticker=mocker.MagicMock(return_value={"bid": 1.0, "ask": 1.0, "last": 1.0}),
        create_order=mocker.MagicMock(return_value=limit_order_open["buy"]),
        get_min_pair_stake_amount=mocker.MagicMock(return_value=1),
        get_max_pair_stake_amount=mocker.MagicMock(return_value=500000),
        get_fee=fee,
        get_funding_fees=mocker.MagicMock(return_value=0),
    )

    # First trade, XRP/BTC: 150 is well within the 198 exposure allowance for XRP - opens
    # at full requested size.
    assert freqtrade.execute_entry("XRP/BTC", 150) is True
    open_trades = Trade.get_open_trades()
    assert len(open_trades) == 1
    assert open_trades[0].stake_amount == pytest.approx(150)

    # Second trade, XRP/USDT: shares base currency XRP with the trade above. Combined
    # exposure of 150 + 150 = 300 would breach the 198 cap, so it must be resized down to
    # the remaining headroom (198 - 150 = 48), not rejected outright (mirrors how
    # min_stake/max_stake already clamp trade size) and not silently allowed at full size.
    assert freqtrade.execute_entry("XRP/USDT", 150) is True
    open_trades = Trade.get_open_trades()
    assert len(open_trades) == 2
    xrp_usdt_trade = next(t for t in open_trades if t.pair == "XRP/USDT")
    assert xrp_usdt_trade.stake_amount == pytest.approx(48)


def test_max_pair_exposure_backtesting(mocker, default_conf, fee) -> None:
    """
    Backtesting path: Backtesting._enter_trade() must produce the SAME resize outcome as
    the live/dry-run test above, for the same strategy+config+stake sequence across the
    same two pairs - this is the core functional guarantee the task prompt demands: the
    cap must not be a live-only feature that backtests silently ignore.
    """
    from freqtrade.optimize.backtesting import Backtesting

    default_conf["use_exit_signal"] = False
    default_conf["max_open_trades"] = 2
    default_conf["stake_amount"] = 150
    default_conf["dry_run_wallet"] = 1000
    default_conf["tradable_balance_ratio"] = 0.99
    default_conf["max_pair_exposure"] = 0.2  # Identical config to the live/dry-run test.

    mocker.patch(f"{EXMS}.get_fee", fee)
    mocker.patch(f"{EXMS}.get_min_pair_stake_amount", return_value=0.00001)
    mocker.patch(f"{EXMS}.get_max_pair_stake_amount", return_value=float("inf"))
    patch_exchange(mocker)

    backtesting = Backtesting(default_conf)
    backtesting._set_strategy(backtesting.strategylist[0])

    row = [
        pd.Timestamp(year=2020, month=1, day=1, hour=5, minute=0),
        1,  # Buy
        0.001,  # Open
        0.0011,  # Close
        0,  # Sell
        0.00099,  # Low
        0.0012,  # High
        "",  # Buy Signal Name
    ]

    try:
        # First trade, XRP/BTC: same 150 stake, same 198 allowance => opens at full size.
        trade1 = backtesting._enter_trade("XRP/BTC", row=row, direction="long")
        assert trade1 is not None
        assert trade1.stake_amount == pytest.approx(150)
        backtesting.wallets.update()

        # Second trade, XRP/USDT: same base currency (XRP) as trade1. Must be resized down
        # to the same 48 remaining headroom as the live/dry-run engine above - IDENTICAL
        # accept/reject/resize outcome for the equivalent trade sequence.
        trade2 = backtesting._enter_trade("XRP/USDT", row=row, direction="long")
        assert trade2 is not None
        assert trade2.stake_amount == pytest.approx(48)
    finally:
        # LocalTrade.bt_trades_open/bt_trades_open_pp are process-global state shared across
        # tests - clean up so other backtesting tests are unaffected.
        LocalTrade.bt_trades_open = []
        LocalTrade.bt_trades_open_pp.clear()
        LocalTrade.bt_open_open_trade_count = 0
        LocalTrade.bt_trades = []
