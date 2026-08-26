"""
Standalone, implementation-agnostic functional test for R02 Task D
(saltstack/salt): "disk.usage() per-run caching".

This file is injected by validators/task_D_functional.sh into a target
checkout at tests/pytests/unit/modules/task_D_functional_test.py and run
with pytest, then removed. It does NOT assume anything about *how* the
candidate implementation caches results (module global, __context__, an
lru_cache decorator, etc.) -- it only calls the real public entry point,
``salt.modules.disk.usage(args=None)``, with the same dunder-mocking
pattern (``configure_loader_modules`` / ``patch.dict(disk.__salt__, ...)``)
used throughout the rest of Salt's own test suite, and observes:

1. Two calls to usage() with identical args, within the *same* test/run,
   must not re-invoke the mocked ``cmd.run`` a second time (the caching
   requirement).
2. A *second, independent* test function -- using a fresh
   ``configure_loader_modules`` fixture instantiation, the same way two
   independent Salt runs/loader instantiations would each get a fresh
   per-run context -- must see its own freshly mocked ``df`` output, not
   a value left over from the first test. This is the specific behavior
   a module-level-global cache fails (the module object, and any global
   it defines, persists across test functions/runs sharing the same
   Python process), and it is exactly the observable, black-box symptom
   the task describes: "a later, unrelated run must still see up-to-date
   disk usage, not a number left over from an earlier run."
3. Return shape/format and call signature are unchanged (dict keyed by
   mount point with the expected sub-keys), matching pre-existing
   ``test_usage_dict``-style expectations.

No internal helpers, module-scope globals, or cache dict names specific
to any one candidate implementation are referenced anywhere below.
"""

import pytest

import salt.modules.disk as disk
from tests.support.mock import MagicMock, patch

FIRST_DF_OUTPUT = (
    "Filesystem     1K-blocks     Used Available Use% Mounted on\n"
    "/dev/sda1        1000000   400000    600000  40% /\n"
)

SECOND_DF_OUTPUT = (
    "Filesystem     1K-blocks     Used Available Use% Mounted on\n"
    "/dev/sda1        2000000  1000000   1000000  50% /\n"
)


@pytest.fixture
def configure_loader_modules():
    # Fresh __opts__/__salt__/__grains__/__context__ dunders for every test
    # function, exactly like Salt's own tests/pytests/unit/modules/test_disk.py.
    return {disk: {}}


def test_usage_cached_within_same_run(configure_loader_modules):
    """
    Calling disk.usage() twice in a row, with the same args and nothing
    relevant changed on the system in between, must not shell out to df
    a second time.
    """
    mock_cmd = MagicMock(return_value=FIRST_DF_OUTPUT)
    # A kernel other than "Linux" sidesteps the /etc/mtab existence check,
    # which is irrelevant to the caching behavior under test and would
    # otherwise depend on whatever host happens to run this validator.
    with patch.dict(disk.__grains__, {"kernel": "SunOS"}), patch.dict(
        disk.__salt__, {"cmd.run": mock_cmd}
    ):
        first = disk.usage(args=None)
        second = disk.usage(args=None)

    assert first == second, "second call within the same run returned different data"
    assert isinstance(first, dict) and "/" in first, "unexpected return shape"
    assert first["/"]["available"] == "600000"
    mock_cmd.assert_called_once()


def test_usage_not_stale_across_independent_run(configure_loader_modules):
    """
    A second, independently-fixtured test function/run must observe its
    own freshly mocked df output, not a value cached by the previous
    test/run. This is what a bare module-level cache dict gets wrong,
    since it survives across test functions/runs sharing the same
    Python process, while a real per-run cache (__context__ or
    equivalent) must not.
    """
    mock_cmd = MagicMock(return_value=SECOND_DF_OUTPUT)
    with patch.dict(disk.__grains__, {"kernel": "SunOS"}), patch.dict(
        disk.__salt__, {"cmd.run": mock_cmd}
    ):
        result = disk.usage(args=None)

    assert result["/"]["available"] == "1000000", (
        "disk.usage() returned data left over from an earlier, unrelated "
        "run/test instead of this run's freshly mocked df output -- this "
        "is the cross-run staleness the task explicitly forbids."
    )
    assert result["/"]["available"] != "600000"
    mock_cmd.assert_called_once()


def test_usage_signature_and_call_style_unchanged():
    """
    usage(args=None) must still be callable exactly as before, with no new
    required arguments.
    """
    import inspect

    sig = inspect.signature(disk.usage)
    params = list(sig.parameters.values())
    assert len(params) == 1, f"unexpected new required parameter(s): {params}"
    assert params[0].name == "args"
    assert params[0].default is None
