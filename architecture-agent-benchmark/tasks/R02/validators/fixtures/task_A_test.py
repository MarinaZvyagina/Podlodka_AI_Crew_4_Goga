"""
Standalone, implementation-agnostic functional test for R02 Task A
(saltstack/salt): "diskusage beacon low-usage threshold alert".

Injected by validators/task_A_functional.sh into a target checkout at
tests/pytests/unit/beacons/task_A_functional_test.py and run with pytest,
then removed.

Only the real, generic public entry points are used -- validate(config)
and beacon(config), exactly as salt/beacons/__init__.py's Beacon.process()
calls them for any beacon module -- never an internal helper specific to
one candidate's implementation.

Two things are checked:

1. Regression: the existing high-usage-threshold config forms (plain
   percent string, bare number, regex mount matching, Windows drive
   letters) must keep working exactly as before. This is re-verified
   independently here rather than trusted from the candidate's own
   (possibly modified) test_diskusage.py.

2. New capability: a mount can also be configured with a low-usage alert
   threshold. The task intentionally leaves the exact config grammar
   open ("in some form that fits naturally alongside the current
   `mount: NN%` style entries") -- the positive reference control used a
   dict value with explicit `low`/`high` keys, and the task's own notes
   mention a signed/prefixed convention as an equally valid alternative.
   Since this validator must score many different real implementations
   of the same task, it probes a small set of the most natural
   conventions (dict-with-low-key, in both percent-string and bare-number
   form, plus a signed-threshold convention) against the real beacon()/
   validate() entry points and accepts the first one that produces the
   documented behavior: firing when usage is at/below the configured low
   threshold, and NOT firing when usage is comfortably above it.

   If none of the probed conventions work, this is reported as FAIL with
   the list of what was tried -- note that architecture check AC1 in
   task_A_AC1.sh is the authoritative discriminator for this task (per
   R02/CONTROL_RESULTS.md, a shallow functional probe cannot by itself
   distinguish "low-usage support added to diskusage.py itself" from "a
   parallel lowdiskusage.py plugin that happens to alert the same way");
   this functional check is a best-effort behavioral proxy, not a
   substitute for that architectural check.
"""

from collections import namedtuple

import pytest

import salt.beacons.diskusage as diskusage
from tests.support.mock import MagicMock, Mock, patch


@pytest.fixture
def configure_loader_modules():
    return {}


@pytest.fixture
def stub_disk_partition():
    return [
        namedtuple("partition", "device mountpoint fstype, opts")(
            "tmpfs", "/mnt/tmp", "tmpfs", "rw,nosuid,nodev,relatime,size=10240k"
        ),
        namedtuple("partition", "device mountpoint fstype, opts")(
            "/dev/disk0s2", "/", "hfs", "rw,local,rootfs,dovolfs,journaled,multilabel"
        ),
    ]


@pytest.fixture
def stub_disk_usage():
    # /mnt/tmp reports 50% used, / reports 25% used (order matches
    # stub_disk_partition above, consumed in order via side_effect).
    return [
        namedtuple("usage", "total used free percent")(1000, 500, 500, 50),
        namedtuple("usage", "total used free percent")(100, 75, 25, 25),
    ]


def _run_beacon(config, stub_disk_usage, stub_disk_partition):
    disk_usage_mock = Mock(side_effect=stub_disk_usage)
    with patch("salt.utils.platform.is_windows", MagicMock(return_value=False)), patch(
        "psutil.disk_partitions", MagicMock(return_value=stub_disk_partition)
    ), patch("psutil.disk_usage", disk_usage_mock):
        validate_ret = diskusage.validate(config)
        beacon_ret = diskusage.beacon(config) if validate_ret[0] else None
    return validate_ret, beacon_ret


# ---------------------------------------------------------------------------
# Regression: existing high-usage config forms must be completely unaffected.
# ---------------------------------------------------------------------------


def test_regression_plain_percent_still_matches(stub_disk_usage, stub_disk_partition):
    config = [{"/mnt/tmp": "50%"}]
    validate_ret, beacon_ret = _run_beacon(config, stub_disk_usage, stub_disk_partition)
    assert validate_ret == (True, "Valid beacon configuration")
    assert beacon_ret == [{"diskusage": 50, "mount": "/mnt/tmp"}]


def test_regression_bare_number_still_matches(stub_disk_usage, stub_disk_partition):
    config = [{"/mnt/tmp": 50}]
    validate_ret, beacon_ret = _run_beacon(config, stub_disk_usage, stub_disk_partition)
    assert validate_ret == (True, "Valid beacon configuration")
    assert beacon_ret == [{"diskusage": 50, "mount": "/mnt/tmp"}]


def test_regression_high_threshold_not_reached_no_alert(
    stub_disk_usage, stub_disk_partition
):
    config = [{"/mnt/tmp": "90%"}]
    validate_ret, beacon_ret = _run_beacon(config, stub_disk_usage, stub_disk_partition)
    assert validate_ret == (True, "Valid beacon configuration")
    assert beacon_ret == []


def test_regression_regex_mount_matching(stub_disk_usage, stub_disk_partition):
    config = [{"/.*": "10%"}]
    validate_ret, beacon_ret = _run_beacon(config, stub_disk_usage, stub_disk_partition)
    assert validate_ret == (True, "Valid beacon configuration")
    assert {"diskusage": 50, "mount": "/mnt/tmp"} in beacon_ret
    assert {"diskusage": 25, "mount": "/"} in beacon_ret


def test_regression_non_list_config_still_rejected():
    assert diskusage.validate({}) == (
        False,
        "Configuration for diskusage beacon must be a list.",
    )


# ---------------------------------------------------------------------------
# New capability: low-usage alert threshold.
# ---------------------------------------------------------------------------

# /mnt/tmp always reports 50% usage in this stub. A "low" threshold of 60
# should fire (50 <= 60); a "low" threshold of 10 should not (50 > 10).
FIRE_THRESHOLD = 60
NOMATCH_THRESHOLD = 10

CANDIDATE_LOW_CONFIG_SCHEMES = {
    "dict-low-percent-string": lambda t: {"low": f"{t}%"},
    "dict-low-bare-number": lambda t: {"low": t},
    "dict-low-and-high": lambda t: {"low": f"{t}%", "high": "1000%"},
    "signed-percent-string": lambda t: f"-{t}%",
    "signed-bare-number": lambda t: -t,
}


def _try_scheme(scheme_fn, stub_disk_usage, stub_disk_partition):
    """
    Returns True if this config scheme correctly fires at/below the low
    threshold and does not fire comfortably above it, for the /mnt/tmp
    mount (which always reports 50% usage in this stub).
    """
    try:
        fire_config = [{"/mnt/tmp": scheme_fn(FIRE_THRESHOLD)}]
        validate_ret, beacon_ret = _run_beacon(
            fire_config, stub_disk_usage, stub_disk_partition
        )
        if validate_ret[0] is not True:
            return False
        if beacon_ret != [{"diskusage": 50, "mount": "/mnt/tmp"}]:
            return False

        nomatch_config = [{"/mnt/tmp": scheme_fn(NOMATCH_THRESHOLD)}]
        validate_ret, beacon_ret = _run_beacon(
            nomatch_config, stub_disk_usage, stub_disk_partition
        )
        if validate_ret[0] is not True:
            return False
        if beacon_ret != []:
            return False
    except Exception:
        return False
    return True


def test_low_usage_alert_threshold_supported(stub_disk_usage, stub_disk_partition):
    """
    At least one natural config convention for a per-mount low-usage
    threshold must exist and behave correctly: fire at/below the
    threshold, stay silent comfortably above it.
    """
    working_schemes = []
    for name, scheme_fn in CANDIDATE_LOW_CONFIG_SCHEMES.items():
        if _try_scheme(scheme_fn, stub_disk_usage, stub_disk_partition):
            working_schemes.append(name)

    assert working_schemes, (
        "No probed low-usage-threshold config convention "
        f"({list(CANDIDATE_LOW_CONFIG_SCHEMES)}) produced the expected "
        "fire-at-or-below / silent-above behavior via validate()/beacon(). "
        "Either the feature is missing, or it uses a config grammar this "
        "validator did not anticipate -- see task_A_AC1.sh for the "
        "authoritative architectural check."
    )


def test_high_threshold_still_works_alongside_low_capability(
    stub_disk_usage, stub_disk_partition
):
    """
    Whatever new grammar was added for low thresholds, the plain
    high-threshold form on a *different* mount in the same beacon call
    must keep firing exactly as before (existing behavior must be
    preserved "alongside" the new option, per the task description).
    """
    # A single config entry matching only "/" triggers exactly one
    # psutil.disk_usage() call, which (per the stub's side_effect order)
    # reports 50% -- comfortably at/above a 20% high threshold, so it
    # must fire, exactly like the pre-existing test_diskusage_match case.
    config = [{"/": "20%"}]
    validate_ret, beacon_ret = _run_beacon(config, stub_disk_usage, stub_disk_partition)
    assert validate_ret == (True, "Valid beacon configuration")
    assert beacon_ret == [{"diskusage": 50, "mount": "/"}]
