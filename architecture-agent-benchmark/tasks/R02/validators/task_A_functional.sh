#!/usr/bin/env bash
# Functional validator for R02 Task A (saltstack/salt):
# "diskusage beacon low-usage threshold alert."
#
# Usage: task_A_functional.sh [repo_path]
#   repo_path defaults to "."
#
# Injects a standalone pytest file exercising the real public
# validate()/beacon() entry points of salt/beacons/diskusage.py:
#   - regression: existing high-threshold config forms unaffected
#   - new capability: at least one natural low-usage-threshold config
#     convention fires at/below the threshold and stays silent above it
#
# NOTE: per R02/CONTROL_RESULTS.md this task's functional behavior alone
# does not reliably discriminate a correct implementation from the
# documented trap (a parallel lowdiskusage.py beacon can produce the same
# observable alerts). Pair this with validators/task_A_AC1.sh..AC4.sh for
# the authoritative architectural verdict; this script only answers "does
# the low-usage-alert capability work at all, without regressing the
# existing high-usage behavior".
#
# Exits 0 and prints "PASS: ..." on success, exits 1 and prints
# "FAIL: ..." otherwise. Cleans up the injected fixture file afterward.

set -u

REPO_PATH="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="${SCRIPT_DIR}/fixtures/task_A_test.py"
TARGET_REL="tests/pytests/unit/beacons/task_A_functional_test.py"

if [[ ! -f "${FIXTURE_SRC}" ]]; then
    echo "FAIL: fixture not found at ${FIXTURE_SRC}"
    exit 1
fi

REPO_PATH="$(cd "${REPO_PATH}" && pwd)"
TARGET_PATH="${REPO_PATH}/${TARGET_REL}"

if [[ ! -d "${REPO_PATH}/tests/pytests/unit/beacons" ]]; then
    echo "FAIL: ${REPO_PATH} does not look like a salt checkout (missing tests/pytests/unit/beacons)"
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

echo "${OUTPUT}" | tail -40

if [[ ${STATUS} -eq 0 ]]; then
    echo "PASS: diskusage beacon supports a working low-usage alert threshold without regressing existing high-usage behavior (task_A_functional)."
    exit 0
else
    echo "FAIL: task_A functional check failed (see pytest output above) -- either a pre-existing high-usage config form regressed, or no probed low-usage-threshold config convention behaved correctly."
    exit 1
fi
