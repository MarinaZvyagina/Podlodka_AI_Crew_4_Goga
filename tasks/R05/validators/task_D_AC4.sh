#!/usr/bin/env bash
# AC4: No new dependency edge from app/vminsert or app/vmselect straight into the
# new tracking package, bypassing Storage's own API.
#
# Method (per metadata_D.yaml): grep -rn '<new-package-import-path>' app/ to
# confirm zero matches outside of, at most, a thin flag-registration/HTTP-
# exposition call that still goes through a Storage method. The new package's
# import path is detected dynamically: find any newly added lib/storage/<name>/
# directory, then derive its import path from go.mod's module line + the
# directory path.
set -u

REPO="${1:-.}"

if [ ! -d "$REPO/lib/storage" ] || [ ! -d "$REPO/app" ]; then
  echo "FAIL: $REPO does not look like the VictoriaMetrics repo root (missing lib/storage or app/)"
  exit 1
fi

GOMOD="$REPO/go.mod"
if [ ! -f "$GOMOD" ]; then
  echo "FAIL: $GOMOD not found"
  exit 1
fi

MODULE_LINE="$(grep -m1 '^module ' "$GOMOD")"
MODULE_PATH="$(echo "$MODULE_LINE" | awk '{print $2}')"
if [ -z "$MODULE_PATH" ]; then
  echo "FAIL: could not parse module path from $GOMOD"
  exit 1
fi

KNOWN_DIRS_RE='^(metricnamestats|metricsmetadata)$'

NEW_PKG_DIRS=""
for d in "$REPO"/lib/storage/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if echo "$name" | grep -Eq "$KNOWN_DIRS_RE"; then
    continue
  fi
  if ls "$d"*.go >/dev/null 2>&1; then
    NEW_PKG_DIRS="$NEW_PKG_DIRS $name"
  fi
done
NEW_PKG_DIRS="$(echo "$NEW_PKG_DIRS" | xargs)"

if [ -z "$NEW_PKG_DIRS" ]; then
  echo "PASS: no new lib/storage/ subpackage detected, so there is no new import path for app/ to depend on (vacuous pass - expected on baseline / trap-without-subpackage states)"
  exit 0
fi

ANY_HIT=""
for name in $NEW_PKG_DIRS; do
  IMPORT_PATH="${MODULE_PATH}/lib/storage/${name}"
  HIT="$(grep -rn "$IMPORT_PATH" "$REPO/app/" 2>/dev/null)"
  if [ -n "$HIT" ]; then
    ANY_HIT="${ANY_HIT}
--- direct import of ${IMPORT_PATH} found in app/ ---
${HIT}"
  fi
done

if [ -n "$ANY_HIT" ]; then
  echo "FAIL: app/ directly imports the new lib/storage subpackage, bypassing Storage's own API:$ANY_HIT"
  exit 1
fi

echo "PASS: no direct app/ import of new lib/storage subpackage(s) [$NEW_PKG_DIRS] found (checked import path(s): $(for n in $NEW_PKG_DIRS; do echo -n "${MODULE_PATH}/lib/storage/${n} "; done))"
exit 0
