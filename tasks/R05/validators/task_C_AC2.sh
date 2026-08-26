#!/usr/bin/env bash
# AC2: ScrapeConfig struct in lib/promscrape/config.go gains a ScaleWaySDConfigs field
# alongside the other *SDConfigs fields, and a matching getScaleWaySDScrapeWork function
# uses cfg.getScrapeWorkGeneric.
set -u

REPO="${1:-.}"
CONFIG_GO="$REPO/lib/promscrape/config.go"

if [ ! -f "$CONFIG_GO" ]; then
  echo "FAIL: $CONFIG_GO not found"
  exit 1
fi

FIELD_HIT="$(grep -n 'SDConfigs ' "$CONFIG_GO" | grep -i scaleway)"
if [ -z "$FIELD_HIT" ]; then
  echo "FAIL: no *SDConfigs struct field matching 'scaleway' found in $CONFIG_GO"
  exit 1
fi

FUNC_HIT="$(grep -n 'func (cfg \*Config) getScaleWaySDScrapeWork' "$CONFIG_GO")"
if [ -z "$FUNC_HIT" ]; then
  echo "FAIL: no 'func (cfg *Config) getScaleWaySDScrapeWork' function found in $CONFIG_GO"
  exit 1
fi

# Verify the function body actually calls the shared getScrapeWorkGeneric helper,
# following the exact pattern of the other 22 backends (not some ad hoc mechanism).
FUNC_BODY="$(awk '/func \(cfg \*Config\) getScaleWaySDScrapeWork/{flag=1} flag{print; if (/^}/ && NR>1 && flag) c++} c==1{exit}' "$CONFIG_GO")"
if ! echo "$FUNC_BODY" | grep -q 'cfg.getScrapeWorkGeneric'; then
  echo "FAIL: getScaleWaySDScrapeWork does not call cfg.getScrapeWorkGeneric"
  exit 1
fi

echo "PASS: found field ($FIELD_HIT) and function ($FUNC_HIT) calling getScrapeWorkGeneric"
exit 0
