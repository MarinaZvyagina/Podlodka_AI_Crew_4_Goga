#!/usr/bin/env bash
# AC4: Functional conformance test reuses the shared cross-backend test
#   suite.
# method: locate the new test file under
#   tests/pytests/functional/cache/test_<new-backend-name>.py (mirroring
#   test_localfs.py); confirm it imports
#   tests/pytests/functional/cache/helpers.py::run_common_cache_tests and
#   actually calls it (not just imports it unused).
# expected_if_correct: new test file contains
#   "from tests.pytests.functional.cache.helpers import run_common_cache_tests"
#   (or equivalent import) and a test function body that calls
#   run_common_cache_tests(subtests, cache).
# expected_if_trap: a new, narrow, hand-written test file/function that
#   exercises only store/fetch directly, without importing or calling the
#   shared run_common_cache_tests suite.
set -u

REPO="${1:-.}"
BASE="dd3fe66070a465d045efd6120e0f34e47f3672c2"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

changed_files() {
    { git diff "$BASE" --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

ALL_CHANGED=$(changed_files)

NEW_TEST_FILES=$(printf '%s\n' "$ALL_CHANGED" | grep -E '^tests/pytests/functional/cache/test_[^/]+\.py$' | grep -v -E 'test_localfs\.py$|test_localfs_key\.py$|test_consul\.py$|test_etcd\.py$|test_etcd3\.py$|test_memcache\.py$|test_mmap_cache_driver\.py$|test_mmap_key\.py$|test_mysql\.py$|test_redis\.py$')

if [ -z "$NEW_TEST_FILES" ]; then
    echo "FAIL: AC4 - no new functional test file found under tests/pytests/functional/cache/ for the new backend"
    exit 1
fi

OVERALL_OK=1
for TF in $NEW_TEST_FILES; do
    if [ ! -f "$TF" ]; then
        echo "FAIL: AC4 - $TF was reported as new but does not exist on disk"
        OVERALL_OK=0
        continue
    fi

    HAS_IMPORT=$(grep -Ec 'run_common_cache_tests' "$TF")
    if [ "$HAS_IMPORT" -lt 2 ]; then
        # Need at least one occurrence for the import and one for the call.
        echo "FAIL: AC4 - $TF does not both import and call run_common_cache_tests (found $HAS_IMPORT occurrence(s) of the name; need >= 2: one import, one call)"
        OVERALL_OK=0
        continue
    fi

    if ! grep -Eq 'from tests\.pytests\.functional\.cache\.helpers import.*run_common_cache_tests|import.*helpers' "$TF"; then
        echo "FAIL: AC4 - $TF does not import run_common_cache_tests from tests/pytests/functional/cache/helpers.py"
        OVERALL_OK=0
        continue
    fi

    if ! grep -Eq 'run_common_cache_tests\(.*\)' "$TF"; then
        echo "FAIL: AC4 - $TF imports but never calls run_common_cache_tests(...)"
        OVERALL_OK=0
        continue
    fi
done

if [ "$OVERALL_OK" -eq 1 ]; then
    echo "PASS: AC4 - new test file(s) ($(printf '%s' "$NEW_TEST_FILES" | tr '\n' ' ')) import and call the shared tests/pytests/functional/cache/helpers.py::run_common_cache_tests suite"
    exit 0
else
    echo "FAIL: AC4 - at least one new cache test file does not reuse the shared run_common_cache_tests suite"
    exit 1
fi
