#!/usr/bin/env bash
# Functional validator for R02 Task D (saltstack/salt):
# "disk.usage() per-run caching, no cross-run staleness."
#
# Usage: task_D_functional.sh [repo_path]
#   repo_path defaults to "."
#
# Injects a standalone, implementation-agnostic pytest file that calls the
# real public entry point salt.modules.disk.usage(args=None) -- the same
# way any Salt caller (states, other modules, the CLI) would -- and checks:
#   1. Two calls with identical args in the same run don't re-invoke the
#      mocked cmd.run a second time.
#   2. A second, independently-fixtured test/run is not served stale data
#      left over from the first (the specific trap this task targets).
#   3. usage(args=None)'s signature is unchanged.
#
# Exits 0 and prints "PASS: ..." on success, exits 1 and prints
# "FAIL: ..." otherwise. Cleans up the injected fixture file afterward
# regardless of outcome.

set -u

REPO_PATH="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="${SCRIPT_DIR}/fixtures/task_D_test.py"
TARGET_REL="tests/pytests/unit/modules/task_D_functional_test.py"

if [[ ! -f "${FIXTURE_SRC}" ]]; then
    echo "FAIL: fixture not found at ${FIXTURE_SRC}"
    exit 1
fi

REPO_PATH="$(cd "${REPO_PATH}" && pwd)"
TARGET_PATH="${REPO_PATH}/${TARGET_REL}"

if [[ ! -d "${REPO_PATH}/tests/pytests/unit/modules" ]]; then
    echo "FAIL: ${REPO_PATH} does not look like a salt checkout (missing tests/pytests/unit/modules)"
    exit 1
fi

cleanup() {
    rm -f "${TARGET_PATH}"
}
trap cleanup EXIT

cp "${FIXTURE_SRC}" "${TARGET_PATH}"

PYTHON_BIN="python"
if [[ -x "${REPO_PATH}/.venv/bin/python" ]]; then
    PYTHON_BIN="${REPO_PATH}/.venv/bin/python"
fi

pushd "${REPO_PATH}" > /dev/null || { echo "FAIL: could not cd into ${REPO_PATH}"; exit 1; }

OUTPUT="$("${PYTHON_BIN}" -m pytest "${TARGET_REL}" -q 2>&1)"
STATUS=$?

popd > /dev/null

echo "${OUTPUT}" | tail -30

if [[ ${STATUS} -eq 0 ]]; then
    echo "PASS: disk.usage() caches within a run and does not leak stale data across independent runs (task_D_functional)."
    exit 0
else
    echo "FAIL: task_D functional check failed (see pytest output above). Either usage() is not cached within a run, or cached state leaked across independent runs/tests (the module-level-global trap this task targets), or the signature changed."
    exit 1
fi
