#!/usr/bin/env bash
# Task C functional validator: ticket R05-TC ("Automatically find scrape targets running on
# Scaleway").
#
# This injects a black-box Go test (fixtures/task_C_test.go, package promscrape_test) into
# the target repo's lib/promscrape package and runs it. The test only uses promscrape's
# public API (the -promscrape.config flag plus promscrape.CheckConfig(), the same
# config-loading path used by -promscrape.config.dryRun in every binary that imports
# lib/promscrape), and checks that a `scaleway_sd_configs` block inside `scrape_configs` is
# accepted as a first-class, strictly-parsed config key - per the ticket's explicit
# requirement that Scaleway discovery be configured "the same way" as the other supported
# cloud providers, rather than via some workaround (e.g. a sidecar poller + file_sd_configs).
#
# Usage: task_C_functional.sh [repo_path]   (repo_path defaults to ".")
set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_C_test.go"

if [ ! -d "$REPO" ]; then
  echo "FAIL: repo path '$REPO' does not exist"
  exit 1
fi
if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

REPO_ABS="$(cd "$REPO" && pwd)"
TARGET_DIR="$REPO_ABS/lib/promscrape"
TARGET_FILE="$TARGET_DIR/zzz_task_C_functional_test.go"

if [ ! -d "$TARGET_DIR" ]; then
  echo "FAIL: $TARGET_DIR not found in repo '$REPO_ABS' (has lib/promscrape been moved/removed?)"
  exit 1
fi

cleanup() {
  rm -f "$TARGET_FILE"
}
trap cleanup EXIT

cp "$FIXTURE" "$TARGET_FILE"

cd "$REPO_ABS" || { echo "FAIL: cannot cd to '$REPO_ABS'"; exit 1; }

OUTPUT="$(go test ./lib/promscrape/ -run '^TestFunctional_ScalewaySDConfigsIsFirstClass$' -v 2>&1)"
STATUS=$?

if [ $STATUS -ne 0 ]; then
  echo "FAIL: task C functional check failed (a scrape_configs entry with a scaleway_sd_configs block is not accepted by promscrape.CheckConfig - Scaleway discovery is missing or not implemented as a first-class scrape_configs key)"
  echo "----- go test output -----"
  echo "$OUTPUT"
  exit 1
fi

echo "PASS: scaleway_sd_configs is accepted as a first-class scrape_configs key by promscrape.CheckConfig (the same config-loading path used by -promscrape.config.dryRun in every VictoriaMetrics binary)"
echo "----- go test output -----"
echo "$OUTPUT"
exit 0
