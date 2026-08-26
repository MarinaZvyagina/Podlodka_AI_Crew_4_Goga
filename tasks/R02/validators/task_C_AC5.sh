#!/usr/bin/env bash
# AC5: Opting in is purely additive/configuration-driven; default behavior
#   unaffected.
# method: run the existing cache test suite without the new option
#   enabled: `python -m pytest tests/pytests/functional/cache/test_localfs.py
#   tests/pytests/unit/cache -q` from within the repo. PASS if it exits 0.
# expected_if_correct: the pre-existing localfs functional tests and the
#   whole unit/cache test tree still pass unmodified, since the new backend
#   is purely opt-in via the `cache` config option and touches no shared
#   code path used by default.
# expected_if_trap: a hardcoded branch added to shared code (e.g.
#   salt/cache/__init__.py's Cache class) risks breaking or altering
#   default-path behavior, which this suite is positioned to catch if it
#   does; even if it doesn't, AC1/AC3/AC4 above should already fail such a
#   trap.
set -u

REPO="${1:-.}"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

# Activate a venv if one is present at $REPO/.venv, otherwise assume
# pytest/python are already on PATH.
if [ -f "$REPO/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$REPO/.venv/bin/activate"
fi

PYTEST_BIN="python -m pytest"
if ! command -v python >/dev/null 2>&1; then
    if command -v pytest >/dev/null 2>&1; then
        PYTEST_BIN="pytest"
    else
        echo "FAIL: AC5 - neither python nor pytest found on PATH"
        exit 1
    fi
fi

OUTPUT=$($PYTEST_BIN tests/pytests/functional/cache/test_localfs.py tests/pytests/unit/cache -q 2>&1)
STATUS=$?

echo "$OUTPUT" | tail -20

if [ "$STATUS" -eq 0 ]; then
    echo "PASS: AC5 - existing cache test suite (test_localfs.py + tests/pytests/unit/cache) passes unmodified with the new backend added; default (non-opted-in) behavior is unaffected"
    exit 0
else
    echo "FAIL: AC5 - existing cache test suite failed (exit code $STATUS) after the new backend was added; default behavior appears to have regressed"
    exit 1
fi
