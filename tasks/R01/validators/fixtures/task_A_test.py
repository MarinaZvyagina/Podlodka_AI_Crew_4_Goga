# pragma pylint: disable=missing-docstring
"""
Functional validator fixture for R01-TA (conflicting capital-sizing config detection).

Black-box, implementation-agnostic check: instantiates a REAL FreqtradeBot (the same
`get_patched_freqtradebot()` helper freqtrade's own test-suite uses everywhere) with a
config that sets both `available_capital` and a non-default `tradable_balance_ratio`
(schema default is 0.99), and asserts that by the time bot start-up has completed, an
unmissable warning naming both settings has been logged.

Deliberately does NOT call `validate_config_consistency()` directly and does NOT assume
the check lives in any particular module/function - it drives two things that are both
genuine, stable, pre-existing PUBLIC surfaces of the bot (not private helpers invented
for one candidate):
  1. FreqtradeBot.__init__() itself (via `get_patched_freqtradebot()`), which is where
     `validate_config_consistency()` already runs today.
  2. `wallets.get_starting_balance()`, an existing public method already called from
     several real production call sites (FreqtradeBot.startup(), the entry-protections
     path, Backtesting's own startup, and RPC's balance/profit endpoints) - i.e. it is
     exercised during ordinary bot operation regardless of which internal module a
     candidate chose to add this check to, including the exact trap location the
     task's own metadata sketches (inside Wallets.get_starting_balance()/
     get_total_stake_amount()).
Together these two calls exercise BOTH plausible warning locations without assuming
either is "the" correct one - the architecture-conformance checks (task_A_AC*.sh) are
what verify *where* the check lives; this script only verifies *that* the user is
warned by the time the bot would actually be running.
"""

from copy import deepcopy

from tests.conftest import get_patched_freqtradebot


def _start_bot_and_touch_starting_balance(mocker, conf):
    freqtrade = get_patched_freqtradebot(mocker, conf)
    # Exercise the other genuine, pre-existing public call site this check could live
    # behind (see module docstring) - a no-op for implementations that already warned
    # during __init__ above.
    freqtrade.wallets.get_starting_balance()
    return freqtrade


def test_conflicting_available_capital_and_ratio_warns(mocker, default_conf, caplog):
    conf = deepcopy(default_conf)
    conf["available_capital"] = 1000
    conf["tradable_balance_ratio"] = 0.5  # non-default -> conflicting

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "available_capital" in caplog.text
    assert "tradable_balance_ratio" in caplog.text


def test_only_available_capital_set_no_warning(mocker, default_conf, caplog):
    conf = deepcopy(default_conf)
    conf.pop("tradable_balance_ratio", None)
    conf["available_capital"] = 1000

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "tradable_balance_ratio" not in caplog.text


def test_only_tradable_balance_ratio_set_no_warning(mocker, default_conf, caplog):
    conf = deepcopy(default_conf)
    conf.pop("available_capital", None)
    conf["tradable_balance_ratio"] = 0.5

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "available_capital" not in caplog.text


def test_default_ratio_with_available_capital_no_warning(mocker, default_conf, caplog):
    # available_capital + tradable_balance_ratio left at its 0.99 schema default is the
    # common, non-conflicting case - must not raise a new warning/error.
    conf = deepcopy(default_conf)
    conf["available_capital"] = 1000
    conf["tradable_balance_ratio"] = 0.99

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "tradable_balance_ratio" not in caplog.text
