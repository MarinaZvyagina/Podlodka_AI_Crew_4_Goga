#!/usr/bin/env bash
# Functional validator for R02 Task C (saltstack/salt):
# "SQLite-backed master cache option."
#
# Usage: task_C_functional.sh [repo_path]
#   repo_path defaults to "."
#
# Injects a standalone pytest file that selects the new backend purely
# through salt.cache.factory(opts) with opts['cache'] set (trying
# "sqlite" first, then any newly-appeared salt/cache/*.py filename), and
# checks:
#   1. Full cross-backend conformance suite
#      (tests/pytests/functional/cache/helpers.py::run_common_cache_tests)
#      -- the same suite localfs/redis/consul already reuse verbatim.
#   2. Durability across a simulated master restart (fresh Cache object,
#      same on-disk location, no shared Python state).
#
# Exits 0 and prints "PASS: ..." on success, exits 1 and prints
# "FAIL: ..." otherwise. Cleans up the injected fixture file afterward.

set -u

REPO_PATH="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="${SCRIPT_DIR}/fixtures/task_C_test.py"
TARGET_REL="tests/pytests/functional/cache/task_C_functional_test.py"

if [[ ! -f "${FIXTURE_SRC}" ]]; then
    echo "FAIL: fixture not found at ${FIXTURE_SRC}"
    exit 1
fi

REPO_PATH="$(cd "${REPO_PATH}" && pwd)"
TARGET_PATH="${REPO_PATH}/${TARGET_REL}"

if [[ ! -d "${REPO_PATH}/tests/pytests/functional/cache" ]]; then
    echo "FAIL: ${REPO_PATH} does not look like a salt checkout (missing tests/pytests/functional/cache)"
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

echo "${OUTPUT}" | tail -60

if [[ ${STATUS} -eq 0 ]]; then
    echo "PASS: a sqlite-backed cache option is selectable via normal master config (opts['cache']), passes the full shared cache conformance suite, and survives a simulated master restart (task_C_functional)."
    exit 0
else
    echo "FAIL: task_C functional check failed (see pytest output above)."
    exit 1
fi
