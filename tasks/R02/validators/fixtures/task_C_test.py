"""
Standalone, implementation-agnostic functional test for R02 Task C
(saltstack/salt): "SQLite-backed master cache option".

Injected by validators/task_C_functional.sh into a target checkout at
tests/pytests/functional/cache/task_C_functional_test.py and run with
pytest, then removed.

Only the real public entry point is used: ``salt.cache.factory(opts)``
with ``opts['cache']`` set to whatever driver name selects the new
backend -- exactly how an operator's master config would select it, and
exactly how every existing backend's own functional test
(test_localfs.py, test_redis.py, test_consul.py, ...) is written. No
backend-specific class or helper is imported directly.

Since the task doesn't mandate one exact config string, the most natural
candidate ("sqlite", used by both the verified positive control and the
verified negative control, and the only name that appears anywhere in
the task's own materials) is tried first; any *new* file that shows up
under salt/cache/ (beyond the fixed set that already existed at the
pinned base commit) is also tried, in case an implementation chose a
different driver name.

Two behavioral properties from the task description are checked:

1. Conformance: once selected, the backend must behave like every other
   cache backend across the full existing cross-backend conformance
   suite (tests/pytests/functional/cache/helpers.py::
   run_common_cache_tests) -- store/fetch/updated/flush/list/contains,
   the same operations already exercised for localfs/redis/consul. This
   is the same test every other backend already reuses verbatim.

2. Durability across a restart: data stored through one Cache object
   must still be fetchable through a *brand new* Cache object pointed at
   the same on-disk location (simulating "restart the master process"),
   with no shared Python state between the two -- an in-memory-only
   implementation would fail this even if it happened to pass (1).
"""

import os
import shutil

import pytest

import salt.cache
from tests.pytests.functional.cache.helpers import run_common_cache_tests

# Cache backend files that already existed at the pinned base commit
# (dd3fe66070a465d045efd6120e0f34e47f3672c2). Any additional *.py file
# under salt/cache/ found at validator run time is a candidate new
# backend module and its filename (minus .py) is tried as a driver name.
_BASELINE_CACHE_FILES = {
    "__init__.py",
    "consul.py",
    "etcd3_cache.py",
    "etcd_cache.py",
    "localfs.py",
    "localfs_key.py",
    "mmap_cache.py",
    "mmap_key.py",
    "mysql_cache.py",
    "redis_cache.py",
}


def _candidate_driver_names():
    names = ["sqlite"]
    cache_dir = os.path.dirname(salt.cache.__file__)
    try:
        entries = os.listdir(cache_dir)
    except OSError:
        entries = []
    for fname in sorted(entries):
        if not fname.endswith(".py"):
            continue
        if fname in _BASELINE_CACHE_FILES:
            continue
        stem = fname[: -len(".py")]
        if stem not in names:
            names.append(stem)
    return names


CANDIDATE_DRIVER_NAMES = _candidate_driver_names()


def _build_cache(minion_opts, driver_name, cachedir):
    opts = minion_opts.copy()
    opts["cache"] = driver_name
    opts["cachedir"] = str(cachedir)
    return salt.cache.factory(opts), opts


@pytest.mark.parametrize("driver_name", CANDIDATE_DRIVER_NAMES)
def test_sqlite_cache_conformance(subtests, minion_opts, tmp_path, driver_name):
    """
    Selecting this driver via normal config must produce a cache object
    that passes the same shared conformance suite every other backend
    (localfs, redis, consul, ...) already reuses verbatim.
    """
    try:
        cache, opts = _build_cache(minion_opts, driver_name, tmp_path / driver_name)
    except Exception as exc:
        pytest.skip(f"driver {driver_name!r} could not be instantiated: {exc!r}")
        return

    try:
        run_common_cache_tests(subtests, cache)
    finally:
        if hasattr(cache, "destroy"):
            try:
                cache.destroy()
            except Exception:
                pass
        shutil.rmtree(opts["cachedir"], ignore_errors=True)


@pytest.mark.parametrize("driver_name", CANDIDATE_DRIVER_NAMES)
def test_sqlite_cache_survives_restart(minion_opts, tmp_path, driver_name):
    """
    Data stored before a (simulated) master restart must still be there
    afterward: a brand new Cache/factory() object pointed at the same
    on-disk location, sharing no Python state with the first, must be
    able to fetch it back.
    """
    cachedir = tmp_path / f"{driver_name}-restart"
    try:
        cache1, opts = _build_cache(minion_opts, driver_name, cachedir)
    except Exception as exc:
        pytest.skip(f"driver {driver_name!r} could not be instantiated: {exc!r}")
        return

    try:
        cache1.store("functional/restart", "durable-key", {"hello": "world", "n": 42})
    except Exception as exc:
        pytest.skip(f"driver {driver_name!r} does not support store(): {exc!r}")
        return
    finally:
        if hasattr(cache1, "destroy"):
            try:
                cache1.destroy()
            except Exception:
                pass
    del cache1

    # Brand new object, same on-disk cachedir, no shared Python state --
    # simulates a fresh master process after a restart.
    cache2, _ = _build_cache(minion_opts, driver_name, cachedir)
    try:
        assert cache2.fetch("functional/restart", "durable-key") == {
            "hello": "world",
            "n": 42,
        }, (
            f"driver {driver_name!r} did not durably persist data across a "
            "simulated master restart (fresh Cache object, same on-disk "
            "location)"
        )
    finally:
        if hasattr(cache2, "destroy"):
            try:
                cache2.destroy()
            except Exception:
                pass
        shutil.rmtree(str(cachedir), ignore_errors=True)


def test_at_least_one_candidate_driver_name_worked(minion_opts, tmp_path):
    """
    Aggregate sanity check: at least one of the candidate driver names
    must actually be selectable and instantiable via salt.cache.factory()
    -- otherwise every parametrized case above will have been skipped
    rather than genuinely exercised, which must not read as a pass.
    """
    any_built = False
    for driver_name in CANDIDATE_DRIVER_NAMES:
        try:
            cache, opts = _build_cache(
                minion_opts, driver_name, tmp_path / f"probe-{driver_name}"
            )
        except Exception:
            continue
        any_built = True
        if hasattr(cache, "destroy"):
            try:
                cache.destroy()
            except Exception:
                pass
        shutil.rmtree(opts["cachedir"], ignore_errors=True)
        break

    assert any_built, (
        f"None of the candidate driver names {CANDIDATE_DRIVER_NAMES} could "
        "be selected via opts['cache'] and instantiated through "
        "salt.cache.factory() -- no sqlite-backed cache option is "
        "reachable through normal master configuration."
    )
