# pragma pylint: disable=missing-docstring, protected-access
"""
Functional validator fixture for R01-TC (consecutive-loss cooldown protection).

Two complementary checks, because this task's "correct" architecture (a new
IProtection subclass, loaded purely by class name) and the documented negative/trap
control (an ad hoc dict bolted directly onto FreqtradeBot, entirely bypassing
IProtection/ProtectionManager/PairLocks) are activated through two DIFFERENT config
surfaces - there is no single call that is guaranteed to exist in both. Rather than
hard-code one specific class name (which would silently break the moment a different,
equally-valid candidate names its handler something else), this fixture:

1. Dynamically DISCOVERS whether a new `IProtection` subclass now exists under
   freqtrade/plugins/protections/ (i.e. it never assumes a class name like
   "MaxConsecutiveLosses" - it scans for whatever the candidate actually added). If
   found, it is driven directly through IProtection's own public, stable interface
   (`stop_per_pair()`/`global_stop()` - the exact abstract methods every conforming
   handler must implement), which is the check the task's own `functional_check_command`
   describes. This is skipped (not failed) if no such class exists, since that alone
   doesn't tell us the feature is missing - see check 2.

2. Runs the REAL production trading loop end-to-end (FreqtradeBot.create_trade() to
   open, FreqtradeBot.execute_trade_exit() to close, repeated for N losing round-trips
   on the same pair) and then asserts that a further FreqtradeBot.create_trade() call on
   that pair is refused, and that it succeeds again once enough (simulated) time has
   passed. This is the authoritative, implementation-structure-agnostic functional
   check: it only observes the bot's real public trading entry points, never an
   internal attribute/class name, so it correctly judges a compliant IProtection-based
   solution AND would equally judge a hypothetical differently-shaped-but-still-correct
   solution. To make sure the feature is actually switched on regardless of which of
   the two known config surfaces a candidate reads, both are populated: the
   discovered IProtection class name (if any) via the strategy's `protections` list,
   and the literal `consecutive_loss_protection` key the documented trap control reads.
   Both are additive/harmless if the candidate's implementation doesn't recognize them.

NOTE: check 2 is expected to PASS for BOTH the correct implementation and the
documented trap control (an ad hoc, `PairLocks`-bypassing dict) - the trap is
functionally indistinguishable from the outside (that's the whole point of the
"Dangerous Success" scenario this benchmark is built to catch); only the separate
architecture-conformance scripts (task_C_AC1.sh..AC5.sh) are able to tell them apart.
"""

import re
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from freqtrade.enums import ExitCheckTuple, ExitType
from freqtrade.persistence import Trade
from tests.conftest import EXMS, get_patched_freqtradebot, patch_get_signal
from tests.plugins.test_protections import generate_mock_trade


KNOWN_BUILTIN_PROTECTIONS = {"CooldownPeriod", "LowProfitPairs", "MaxDrawdown", "StoplossGuard"}
_CLASS_DEF_RE = re.compile(r"^class\s+(\w+)\s*\(([^)]*)\)\s*:", re.MULTILINE)


def _discover_new_protection_class_name() -> str | None:
    """
    Scan freqtrade/plugins/protections/*.py for any class inheriting IProtection that
    isn't one of the four pre-existing built-ins. Returns the class name, or None if
    no new handler was added (e.g. the trap control, which never adds one).
    """
    repo_root = Path(__file__).resolve().parents[1]
    protections_dir = repo_root / "freqtrade" / "plugins" / "protections"
    if not protections_dir.is_dir():
        return None
    for py_file in sorted(protections_dir.glob("*.py")):
        if py_file.name in ("__init__.py", "iprotection.py"):
            continue
        text = py_file.read_text()
        for match in _CLASS_DEF_RE.finditer(text):
            class_name, bases = match.group(1), match.group(2)
            if "IProtection" in bases and class_name not in KNOWN_BUILTIN_PROTECTIONS:
                return class_name
    return None


@pytest.mark.usefixtures("init_persistence")
def test_new_protection_handler_streak_logic():
    """
    Check 1 (informational when skipped): if a new IProtection subclass exists, drive
    it directly via its own public stop_per_pair()/global_stop() interface with a
    manufactured consecutive-loss streak, exactly mirroring the task's own
    functional_check_command and tests/plugins/test_protections.py's existing style
    for the four built-in handlers.
    """
    class_name = _discover_new_protection_class_name()
    if class_name is None:
        pytest.skip(
            "No new IProtection subclass found under freqtrade/plugins/protections/; "
            "test_full_production_loop_consecutive_loss_pause is the authoritative "
            "functional check for implementations that use a different mechanism."
        )

    from freqtrade.resolvers.protection_resolver import ProtectionResolver

    config = {"timeframe": "5m"}
    protection_config = {"trade_limit": 3, "stop_duration": 60}
    handler = ProtectionResolver.load_protection(
        class_name, config=config, protection_config=protection_config
    )

    pair = "XRP/BTC"
    now = datetime.now(UTC)

    # 2 consecutive losses - below the configured threshold of 3, must not lock yet.
    generate_mock_trade(
        pair, 0.001, False, exit_reason=ExitType.STOP_LOSS.value,
        min_ago_open=200, min_ago_close=150, profit_rate=0.9,
    )
    generate_mock_trade(
        pair, 0.001, False, exit_reason=ExitType.STOP_LOSS.value,
        min_ago_open=140, min_ago_close=100, profit_rate=0.9,
    )
    Trade.commit()
    assert handler.stop_per_pair(pair, now, "long", 100.0) is None

    # 3rd consecutive loss - threshold reached, must lock.
    generate_mock_trade(
        pair, 0.001, False, exit_reason=ExitType.STOP_LOSS.value,
        min_ago_open=50, min_ago_close=20, profit_rate=0.9,
    )
    Trade.commit()
    result = handler.stop_per_pair(pair, now, "long", 100.0)
    assert result is not None
    assert result.lock is True


def test_full_production_loop_consecutive_loss_pause(mocker, default_conf_usdt, fee, time_machine):
    """
    Check 2 (authoritative): drives the actual bot trading loop through real,
    unmodified public entry points (create_trade / execute_trade_exit) and observes
    whether new entries on a pair are genuinely blocked after N consecutive losses,
    and genuinely unblocked again after the configured cool-down elapses.
    """
    start_dt = datetime(2026, 1, 1, tzinfo=UTC)
    time_machine.move_to(start_dt, tick=True)

    pair = "ETH/USDT"
    default_conf_usdt["max_open_trades"] = 1
    default_conf_usdt["stake_amount"] = 60
    default_conf_usdt["dry_run_wallet"] = 1000
    default_conf_usdt["exchange"]["pair_whitelist"] = [pair]

    trade_limit = 3
    stop_duration_minutes = 60

    discovered_class = _discover_new_protection_class_name()
    if discovered_class:
        default_conf_usdt["_strategy_protections"] = [
            {
                "method": discovered_class,
                "trade_limit": trade_limit,
                "stop_duration": stop_duration_minutes,
            }
        ]
    # Also populate the exact config surface the documented trap control reads
    # (freqtrade/freqtradebot.py's ad hoc `consecutive_loss_protection` dict) - a no-op
    # for any implementation that doesn't recognize this key.
    default_conf_usdt["consecutive_loss_protection"] = {
        "trade_limit": trade_limit,
        "stop_duration": stop_duration_minutes,
    }

    mocker.patch.multiple(
        EXMS,
        fetch_ticker=MagicMock(return_value={"bid": 2.0, "ask": 2.02, "last": 2.0}),
        get_fee=fee,
        _dry_is_price_crossed=MagicMock(return_value=True),
    )

    freqtrade = get_patched_freqtradebot(mocker, default_conf_usdt)
    patch_get_signal(freqtrade, enter_long=True)
    freqtrade.strategy.confirm_trade_entry = MagicMock(return_value=True)
    freqtrade.strategy.confirm_trade_exit = MagicMock(return_value=True)

    # Open and close `trade_limit` losing round-trips in a row on the same pair,
    # through the real production entry/exit methods.
    for _ in range(trade_limit):
        assert freqtrade.create_trade(pair) is True
        open_trades = Trade.get_open_trades()
        assert len(open_trades) == 1
        trade = open_trades[0]
        # Exit well below entry price -> a clear loss.
        freqtrade.execute_trade_exit(
            trade=trade, limit=1.0, exit_check=ExitCheckTuple(exit_type=ExitType.STOP_LOSS)
        )
        assert len(Trade.get_open_trades()) == 0
        time_machine.shift(timedelta(minutes=5))

    # threshold reached: a further entry attempt on this pair must now be refused.
    assert freqtrade.create_trade(pair) is False
    assert len(Trade.get_open_trades()) == 0

    # Once the configured cool-down window has elapsed, new entries must resume
    # automatically - no manual intervention.
    time_machine.shift(timedelta(minutes=stop_duration_minutes + 5))
    assert freqtrade.create_trade(pair) is True
    assert len(Trade.get_open_trades()) == 1
