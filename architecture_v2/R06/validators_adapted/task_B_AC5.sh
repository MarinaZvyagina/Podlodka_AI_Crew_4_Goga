#!/usr/bin/env bash
# AC5 (task B / R06-TB): the change genuinely crosses config, domain, and
# request-validation boundaries (cross-module, not a single-file patch).
#
# Method (per metadata_B.yaml AC5): git diff --stat / list of changed files,
# checked against required directories.
#
# PASS: diff touches at least one of {server/etcdmain, server/embed,
#       server/config}, AND something under server/lease/*, AND something
#       under server/etcdserver/txn/* (or the apply layer, e.g.
#       server/etcdserver/apply/*).
# FAIL: diff is confined to a single file/package (e.g. only
#       server/lease/lessor.go), with the limit either hardcoded or checked
#       only inside Attach.

set -uo pipefail

REPO="${1:-.}"
BASE="abe967acfac35ba278795c42e0a8968637594cef"

changed_files="$(git -C "$REPO" diff --name-only "$BASE" 2>/dev/null)"
if [ -z "$changed_files" ]; then
  echo "FAIL: no changes found relative to base commit $BASE (git diff --name-only is empty)."
  exit 1
fi

n_changed="$(echo "$changed_files" | grep -c .)"

config_hit=0
lease_hit=0
apply_hit=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    server/etcdmain/*|server/embed/*|server/config/*)
      config_hit=1
      ;;
  esac
  case "$f" in
    server/lease/*)
      lease_hit=1
      ;;
  esac
  case "$f" in
    server/etcdserver/txn/*|server/etcdserver/apply/*)
      apply_hit=1
      ;;
  esac
done <<< "$changed_files"

echo "Changed files (vs $BASE):"
echo "$changed_files" | sed 's/^/  /'
echo "Total changed files: $n_changed"

if [ "$n_changed" -le 1 ]; then
  echo "FAIL: diff touches only $n_changed file(s) - confined to a single file, not a cross-module change."
  exit 1
fi

missing=""
[ "$config_hit" -eq 0 ] && missing="$missing server/etcdmain|server/embed|server/config"
[ "$lease_hit" -eq 0 ] && missing="$missing server/lease/*"
[ "$apply_hit" -eq 0 ] && missing="$missing server/etcdserver/txn/*|server/etcdserver/apply/*"

if [ -n "$missing" ]; then
  echo "FAIL: diff is missing changes in required area(s):$missing"
  exit 1
fi

echo "PASS: diff touches the config layer (server/etcdmain|server/embed|server/config), the lease domain (server/lease/*), and the request-validation/apply layer (server/etcdserver/txn/* or server/etcdserver/apply/*) - a genuine cross-module change."
exit 0
