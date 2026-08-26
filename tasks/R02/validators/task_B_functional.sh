#!/usr/bin/env bash
# Functional validator for R02 Task B (saltstack/salt):
# "minion beacon last-fired/error status query."
#
# Usage: task_B_functional.sh [repo_path]
#   repo_path defaults to "."
#
# Injects a standalone pytest file that:
#   1. Drives the real salt.beacons.Beacon.process() evaluation loop with
#      a successful, an erroring, and a never-invoked stub beacon, then
#      auto-discovers whatever new public attribute/method the candidate
#      added and checks it reflects real recent fire/error/never-fired
#      status (no beacon-name/attribute-name assumptions baked in).
#   2. Auto-discovers whatever new function the candidate added to
#      salt/modules/beacons.py and calls it with the event round-trip
#      mocked the same way Salt's own list_/add/delete tests do.
#
# NOTE: per R02/CONTROL_RESULTS.md, this task is architecture-sensitive:
# a trap that re-invokes each beacon's beacon() function directly from
# salt/modules/beacons.py (bypassing the real daemon loop and event
# round-trip) can still satisfy a shallow, single-process functional
# check like this one. Pair with validators/task_B_AC1.sh..AC5.sh for the
# authoritative architectural verdict on *how* the data got there.
#
# Exits 0 and prints "PASS: ..." on success, exits 1 and prints
# "FAIL: ..." otherwise. Cleans up the injected fixture file afterward.

set -u

REPO_PATH="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="${SCRIPT_DIR}/fixtures/task_B_test.py"
TARGET_REL="tests/pytests/unit/task_B_functional_test.py"

if [[ ! -f "${FIXTURE_SRC}" ]]; then
    echo "FAIL: fixture not found at ${FIXTURE_SRC}"
    exit 1
fi

REPO_PATH="$(cd "${REPO_PATH}" && pwd)"
TARGET_PATH="${REPO_PATH}/${TARGET_REL}"

if [[ ! -d "${REPO_PATH}/tests/pytests/unit" ]]; then
    echo "FAIL: ${REPO_PATH} does not look like a salt checkout (missing tests/pytests/unit)"
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

echo "${OUTPUT}" | tail -50

if [[ ${STATUS} -eq 0 ]]; then
    echo "PASS: minion beacon status (last-fired/error, incl. never-fired) is queryable via the real Beacon.process() loop and the modules.beacons execution-module surface (task_B_functional)."
    exit 0
else
    echo "FAIL: task_B functional check failed (see pytest output above)."
    exit 1
fi
