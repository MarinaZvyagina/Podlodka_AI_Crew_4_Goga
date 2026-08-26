"""
Standalone, implementation-agnostic functional test for R02 Task B
(saltstack/salt): "minion beacon last-fired/error status query".

Injected by validators/task_B_functional.sh into a target checkout at
tests/pytests/unit/task_B_functional_test.py and run with pytest, then
removed.

The task deliberately leaves the exact attribute/method names open (the
metadata only fixes the *shape* of the solution: status is recorded
inside the real Beacon.process() evaluation loop, and is queryable
through a new function alongside the existing beacon-management commands
in salt/modules/beacons.py). To stay implementation-agnostic across many
different real implementations of the same task, this validator does not
hardcode a specific attribute name like ``beacon_status`` or a specific
function name like ``status``; instead it:

1. Exercises the real, always-present public entry point
   ``salt.beacons.Beacon.process()`` with one beacon that fires
   successfully, one that raises, and one that is configured but never
   invoked -- then auto-discovers whatever *new* (non-baseline) public
   attribute/method the candidate implementation added to the Beacon
   instance, and checks it plausibly records a recent timestamp for the
   two beacons that ran, distinguishes the erroring one from the
   succeeding one, and does not fabricate a timestamp for the one that
   never ran.

2. Auto-discovers whatever *new* (non-baseline) public function the
   candidate implementation added to salt/modules/beacons.py (mirroring
   the existing list_/add/delete/etc. commands) and calls it the same
   way the existing test suite calls those commands: with
   salt.utils.event.SaltEvent.get_event patched to hand back a
   fabricated completion event, and __salt__['event.fire'] mocked. This
   checks the query is exposed on the same execution-module surface
   operators already use for beacon management, without needing a live
   minion daemon.

This is a best-effort automatable proxy for an inherently
architecture-sensitive task: per R02/CONTROL_RESULTS.md, a real trap
implementation (status() re-invoking each beacon's beacon() function
in-process, bypassing the daemon's real evaluation loop and the event
round-trip entirely) can still pass a shallow single-process functional
test. The architecture checks (task_B_AC1.sh..AC5.sh) are the
authoritative discriminator for *how* the data got there; this script
only checks that the observable status-reporting behavior described in
the task exists somewhere reachable from these two real entry points.
"""

import time

import pytest

import salt.beacons
import salt.modules.beacons as beacons_mod
from salt.utils.event import SaltEvent
from tests.support.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Part 1: the real Beacon evaluation loop (salt.beacons.Beacon.process()).
# ---------------------------------------------------------------------------

# Names present on Beacon/salt.modules.beacons at the pinned base commit
# (dd3fe66070a465d045efd6120e0f34e47f3672c2), before this task's changes.
# Anything else found on these objects is new, candidate-added surface.
_BASELINE_BEACON_ATTRS = {"opts", "functions", "beacons", "interval_map"}
_BASELINE_BEACON_METHODS = {
    "__init__",
    "_close_beacon",
    "close_beacons",
    "process",
    "_trim_config",
    "_determine_beacon_config",
    "_process_interval",
    "_get_index",
    "_remove_list_item",
    "_update_enabled",
    "_get_beacons",
    "list_beacons",
    "list_available_beacons",
    "validate_beacon",
    "add_beacon",
    "modify_beacon",
    "delete_beacon",
    "enable_beacons",
    "disable_beacons",
    "enable_beacon",
    "disable_beacon",
    "reset",
}
_BASELINE_MODULES_BEACONS_FUNCS = {
    "list_",
    "list_available",
    "add",
    "modify",
    "delete",
    "save",
    "enable",
    "disable",
    "enable_beacon",
    "disable_beacon",
    "reset",
}


def _new_public_attrs(instance, baseline):
    return {
        name: getattr(instance, name)
        for name in vars(instance)
        if not name.startswith("_") and name not in baseline
    }


def _new_public_methods(cls, baseline):
    import inspect

    return [
        name
        for name, _ in inspect.getmembers(cls, predicate=inspect.isfunction)
        if not name.startswith("_") and name not in baseline
    ]


def _new_module_funcs(module, baseline):
    names = []
    for name in dir(module):
        if name.startswith("_") or name in baseline:
            continue
        obj = getattr(module, name)
        if not callable(obj):
            continue
        if getattr(obj, "__module__", None) != module.__name__:
            continue
        names.append(name)
    return names


def _find_recent_timestamp(value, before, after, slack=5):
    """
    Recursively search an arbitrary status record for a number that looks
    like a recent time.time()-style timestamp.
    """
    if isinstance(value, bool):
        return False
    if isinstance(value, (int, float)):
        return (before - slack) <= value <= (after + slack)
    if isinstance(value, dict):
        return any(_find_recent_timestamp(v, before, after, slack) for v in value.values())
    if isinstance(value, (list, tuple)):
        return any(_find_recent_timestamp(v, before, after, slack) for v in value)
    return False


def _mentions_error(value, needle="Global Thermonuclear War"):
    if isinstance(value, str):
        return needle in value or value is True
    if value is True:
        return True
    if isinstance(value, dict):
        return any(_mentions_error(v, needle) for v in value.values())
    if isinstance(value, (list, tuple)):
        return any(_mentions_error(v, needle) for v in value)
    return False


@pytest.fixture
def real_beacon(minion_opts):
    minion_opts["id"] = "minion"
    minion_opts["__role"] = "minion"
    minion_opts["beacons"] = {
        "watch_ok": [{"beacon_module": "fake_ok"}],
        "watch_err": [{"beacon_module": "fake_err"}],
        "watch_never": [{"beacon_module": "fake_never"}],
    }
    beacon = salt.beacons.Beacon(minion_opts, [])

    ok_mock = MagicMock(return_value=[])
    ok_mock.__globals__ = {}
    err_mock = MagicMock(side_effect=Exception("Global Thermonuclear War"))
    err_mock.__globals__ = {}
    beacon.beacons["fake_ok.beacon"] = ok_mock
    beacon.beacons["fake_err.beacon"] = err_mock
    # Deliberately no "fake_never.beacon" registered: process() will log a
    # warning and skip it, exactly like a beacon that never actually fires.
    return beacon


def test_process_records_recent_status_for_fired_beacons(real_beacon, minion_opts):
    """
    The real Beacon.process() evaluation loop, after actually running two
    configured beacons (one success, one raising), must make it possible
    to discover -- via *some* new public attribute/method this
    implementation added -- that both fired recently, that the erroring
    one is distinguishable from the successful one, and that the beacon
    which never fired is not reported with a fabricated recent
    timestamp.
    """
    before = time.time()
    real_beacon.process(minion_opts["beacons"], {})
    after = time.time()

    new_attrs = _new_public_attrs(real_beacon, _BASELINE_BEACON_ATTRS)
    new_methods = _new_public_methods(type(real_beacon), _BASELINE_BEACON_METHODS)

    assert new_attrs or new_methods, (
        "Beacon gained no new public attribute or method beyond the "
        f"pre-existing {sorted(_BASELINE_BEACON_ATTRS | _BASELINE_BEACON_METHODS)} "
        "-- no way to discover per-beacon status was found."
    )

    # Prefer a directly-inspectable new attribute (e.g. an in-memory status
    # dict). Fall back to calling a new read-only method that returns data
    # directly (some implementations may expose status only via the event
    # round trip, which part 2 below covers separately).
    candidate_records = list(new_attrs.values())
    for name in new_methods:
        method = getattr(real_beacon, name)
        try:
            with patch("salt.utils.event.get_event"):
                ret = method()
        except Exception:
            continue
        if isinstance(ret, dict):
            candidate_records.append(ret)
    # Also allow post-call attributes that only appear after invoking a
    # new zero-arg method (e.g. a method that lazily populates a cache).
    candidate_records.extend(_new_public_attrs(real_beacon, _BASELINE_BEACON_ATTRS).values())

    found_ok_timestamp = False
    found_err_signal = False
    found_never_absent_or_none = True

    for record in candidate_records:
        if not isinstance(record, dict):
            continue
        ok_entry = record.get("watch_ok")
        err_entry = record.get("watch_err")
        never_entry = record.get("watch_never", None)

        if ok_entry is not None and _find_recent_timestamp(ok_entry, before, after):
            found_ok_timestamp = True
        if err_entry is not None and (
            _mentions_error(err_entry) or err_entry != ok_entry
        ):
            found_err_signal = True
        if never_entry not in (None,) and _find_recent_timestamp(
            never_entry, before, after
        ):
            found_never_absent_or_none = False

    assert found_ok_timestamp, (
        "Could not find a recent timestamp recorded for 'watch_ok' after "
        "Beacon.process() actually ran it, in any newly-added public "
        f"attribute/method. Inspected: {list(new_attrs)} / {new_methods}"
    )
    assert found_err_signal, (
        "Could not find a status entry for 'watch_err' that is "
        "distinguishable from the successful 'watch_ok' entry (expected "
        "an error flag/message reflecting the raised exception)."
    )
    assert found_never_absent_or_none, (
        "'watch_never' (a beacon that was never actually invoked) was "
        "reported with a fabricated recent timestamp instead of being "
        "clearly absent/None."
    )


# ---------------------------------------------------------------------------
# Part 2: the execution-module surface (salt/modules/beacons.py), reached
# the same way existing beacon-management commands are (event fire + wait
# for a completion event), never a live minion daemon.
# ---------------------------------------------------------------------------


@pytest.fixture
def configure_loader_modules(minion_opts):
    return {beacons_mod: {"__opts__": minion_opts}}


def test_modules_beacons_exposes_a_status_query(minion_opts):
    """
    salt/modules/beacons.py must expose a new, callable, no-required-arg
    function (alongside list_/add/delete/etc.) that an operator could run
    the same way as those existing commands.
    """
    new_funcs = _new_module_funcs(beacons_mod, _BASELINE_MODULES_BEACONS_FUNCS)
    assert new_funcs, (
        "No new public function found in salt/modules/beacons.py beyond "
        f"the pre-existing {sorted(_BASELINE_MODULES_BEACONS_FUNCS)}."
    )

    fabricated_status = {
        "watch_ok": {"last_fired": time.time(), "error": False, "error_msg": None},
        "watch_never": None,
    }
    # Whatever key name/tag the implementation actually keys its payload
    # under, this event dict makes several plausible ones available so the
    # candidate's own extraction logic (not this validator) determines
    # what "the" answer looks like.
    event_ret = {
        "complete": True,
        "beacons": fabricated_status,
        "beacon_status": fabricated_status,
        "status": fabricated_status,
        "data": fabricated_status,
    }

    succeeded = False
    last_exc = None
    for name in new_funcs:
        func = getattr(beacons_mod, name)
        mock_fire = MagicMock(return_value=True)
        try:
            with patch.dict(beacons_mod.__salt__, {"event.fire": mock_fire}, clear=False):
                with patch.object(SaltEvent, "get_event", side_effect=[event_ret]):
                    ret = func()
        except Exception as exc:  # this candidate name/signature didn't work
            last_exc = exc
            continue
        if ret is not None:
            succeeded = True
            break

    assert succeeded, (
        f"None of the candidate new functions {new_funcs} in "
        "salt/modules/beacons.py could be called with no required "
        "arguments and a mocked event round-trip to produce a non-None "
        f"result. Last error seen: {last_exc!r}"
    )
