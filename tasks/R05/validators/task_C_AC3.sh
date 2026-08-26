#!/usr/bin/env bash
# AC3: New backend registered in the scs.add(...) dispatch list in
# lib/promscrape/scraper.go.
set -u

REPO="${1:-.}"
SCRAPER_GO="$REPO/lib/promscrape/scraper.go"

if [ ! -f "$SCRAPER_GO" ]; then
  echo "FAIL: $SCRAPER_GO not found"
  exit 1
fi

HIT="$(grep -n 'scs.add("scaleway_sd_configs"' "$SCRAPER_GO")"
if [ -z "$HIT" ]; then
  echo "FAIL: no scs.add(\"scaleway_sd_configs\" ...) registration found in $SCRAPER_GO"
  exit 1
fi

echo "PASS: found registration: $HIT"
exit 0
