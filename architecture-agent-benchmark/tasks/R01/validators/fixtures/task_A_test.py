# pragma pylint: disable=missing-docstring
"""
Functional validator fixture for R01-TA (conflicting capital-sizing config detection).

Black-box, implementation-agnostic check: instantiates a REAL FreqtradeBot (the same
`get_patched_freqtradebot()` helper freqtrade's own test-suite uses everywhere) with a
config that sets both `available_capital` and a non-default `tradable_balance_ratio`
(schema default is 0.99), and asserts that by the time bot start-up has completed, an
unmissable warning naming both settings has been logged OR the bot fails fast with a
ConfigurationError naming both settings -- the task prompt and this task's own
architecture-conformance check (task_A_AC4.sh) both explicitly treat a hard
`raise ConfigurationError(...)` and an unmissable `logger.warning(...)` as equally
valid implementations of "fail fast with a clear, actionable message"; this fixture
originally only recognized the logger.warning path, silently marking every
ConfigurationError-based solution functionally FAIL despite passing every
architecture-conformance check including the one that explicitly approves that style.
Found by manually re-deriving this task's real 800-run-study data (all 20 real Baseline/
Goga runs for R01-TA used the raise style, matching this exact file's own pre-existing
convention) and fixed here to accept either, per the task's actual functional_requirements.

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

from freqtrade.exceptions import ConfigurationError
from tests.conftest import get_patched_freqtradebot


def _start_bot_and_touch_starting_balance(mocker, conf):
    freqtrade = get_patched_freqtradebot(mocker, conf)
    # Exercise the other genuine, pre-existing public call site this check could live
    # behind (see module docstring) - a no-op for implementations that already warned
    # during __init__ above.
    freqtrade.wallets.get_starting_balance()
    return freqtrade


def _set_user_supplied(conf, **kv):
    """
    Mirrors real `Configuration.load_config()` behavior (freqtrade/configuration/
    configuration.py): `original_config` is a deepcopy of the config taken BEFORE any
    `_process_*` step fills in schema defaults (e.g. tradable_balance_ratio's 0.99). A
    correct implementation distinguishing "the user actually typed this" from "the schema
    defaulted it" checks `original_config`, not the live, already-defaulted `conf` dict --
    this fixture must populate both consistently, or it can't validate that (more robust)
    style, and will spuriously fail an implementation that correctly avoids the false-
    positive case `test_default_ratio_with_available_capital_no_warning` below checks for.
    default_conf's own `original_config` starts as `{}` (tests/conftest.py) -- nothing was
    "user-supplied" until a test says so.
    """
    conf.update(kv)
    conf.setdefault("original_config", {}).update(kv)


def test_conflicting_available_capital_and_ratio_warns(mocker, default_conf, caplog):
    conf = deepcopy(default_conf)
    _set_user_supplied(conf, available_capital=1000, tradable_balance_ratio=0.5)  # non-default -> conflicting

    try:
        _start_bot_and_touch_starting_balance(mocker, conf)
    except ConfigurationError as e:
        # fail-fast style: the exception message itself must name both settings.
        assert "available_capital" in str(e)
        assert "tradable_balance_ratio" in str(e)
        return

    # warning style: bot starts, but logs an unmissable warning naming both settings.
    assert "available_capital" in caplog.text
    assert "tradable_balance_ratio" in caplog.text


def test_only_available_capital_set_no_warning(mocker, default_conf, caplog):
    conf = deepcopy(default_conf)
    conf.pop("tradable_balance_ratio", None)
    conf.get("original_config", {}).pop("tradable_balance_ratio", None)
    _set_user_supplied(conf, available_capital=1000)

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "tradable_balance_ratio" not in caplog.text


def test_only_tradable_balance_ratio_set_no_warning(mocker, default_conf, caplog):
    conf = deepcopy(default_conf)
    conf.pop("available_capital", None)
    conf.get("original_config", {}).pop("available_capital", None)
    _set_user_supplied(conf, tradable_balance_ratio=0.5)

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "available_capital" not in caplog.text


def test_default_ratio_with_available_capital_no_warning(mocker, default_conf, caplog):
    # User only ever set available_capital; tradable_balance_ratio is absent from their
    # config and just carries its 0.99 schema default in the live `conf` dict (as it
    # always does) -- the common, non-conflicting case. Must not raise a new warning/error.
    conf = deepcopy(default_conf)
    conf["tradable_balance_ratio"] = 0.99  # schema default, present in the live dict
    conf.get("original_config", {}).pop("tradable_balance_ratio", None)  # but NOT user-supplied
    _set_user_supplied(conf, available_capital=1000)

    _start_bot_and_touch_starting_balance(mocker, conf)

    assert "tradable_balance_ratio" not in caplog.text
