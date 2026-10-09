#!/usr/bin/env bash
# AC1: A new lib/promscrape/discovery/scaleway package exists with an SDConfig type
# implementing GetLabels(baseDir string) ([]*promutil.Labels, error).
set -u

REPO="${1:-.}"

if [ ! -d "$REPO/lib/promscrape/discovery" ]; then
  echo "FAIL: $REPO/lib/promscrape/discovery directory not found"
  exit 1
fi

PKG_HIT="$(ls "$REPO/lib/promscrape/discovery" 2>/dev/null | grep -i scaleway)"
if [ -z "$PKG_HIT" ]; then
  echo "FAIL: no scaleway package found under $REPO/lib/promscrape/discovery/"
  exit 1
fi

SCALEWAY_DIR="$REPO/lib/promscrape/discovery/$PKG_HIT"
if [ ! -d "$SCALEWAY_DIR" ]; then
  echo "FAIL: $PKG_HIT found in discovery/ listing but is not a directory ($SCALEWAY_DIR)"
  exit 1
fi

GETLABELS_HIT="$(grep -n 'func (sdc \*SDConfig) GetLabels' "$SCALEWAY_DIR"/*.go 2>/dev/null)"
if [ -z "$GETLABELS_HIT" ]; then
  echo "FAIL: no 'func (sdc *SDConfig) GetLabels' method found in $SCALEWAY_DIR/*.go"
  exit 1
fi

echo "PASS: found $SCALEWAY_DIR with SDConfig.GetLabels method: $GETLABELS_HIT"
exit 0
