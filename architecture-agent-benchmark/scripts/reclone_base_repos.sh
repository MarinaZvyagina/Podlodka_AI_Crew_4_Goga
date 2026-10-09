#!/usr/bin/env bash
# Re-creates all 10 base clones at their exact pinned commits (shallow fetch --
# only the single pinned commit's tree is needed, no history). Idempotent: skips
# any repo whose base clone already exists at the correct commit.
#
# Context: the previous base clones lived under /tmp/benchmark-repos/, which macOS's
# periodic daily cleanup silently strips of files older than ~3 days -- this destroyed
# every .git object database (HEAD/config/refs/most objects gone) partway through the
# unattended 800-run batch, cascading into ~650 INVALID rows. New location is outside
# /tmp entirely so it is never subject to that cleanup.
#
# No associative arrays: macOS ships bash 3.2 (no declare -A support), so the repo
# table is a plain list of "id|url|commit" lines instead.
set -euo pipefail

ROOT="/Users/marinaoreshina/UK_Talant_Visa/Highload/benchmark-scratch/repos"
mkdir -p "$ROOT"

REPOS='
R01|https://github.com/freqtrade/freqtrade|936f28e28cbcd4e9e146cbc076c54933517a92eb
R02|https://github.com/saltstack/salt|dd3fe66070a465d045efd6120e0f34e47f3672c2
R03|https://github.com/nestjs/nest|f94e9eb15ba2a22f69aef234cb81333764d0b298
R04|https://github.com/excalidraw/excalidraw|e160ff7ba0641fba729c528482de5277ffb19c58
R05|https://github.com/VictoriaMetrics/VictoriaMetrics|f65ae841ace8f686ddc0dc17fe936d0bf38e568c
R06|https://github.com/etcd-io/etcd|23a4e406a2e70a807486b4c40a9e24da493886bf
R07|https://github.com/mihonapp/mihon|ac249e3668a57f24782a49218834064459ba2d09
R08|https://github.com/signalapp/Signal-Android|441ba42c3f3175476a1f54eba8e72d8d6d304db7
R09|https://github.com/mozilla-mobile/firefox-ios|de940072da700c2af7d74348b5775674d106d503
R10|https://github.com/signalapp/Signal-iOS|6e3a059f752785b349d5938dfa4c36f216fb0ae3
'

echo "$REPOS" | while IFS='|' read -r r url commit; do
  [ -z "$r" ] && continue
  dest="$ROOT/$r"
  if [ "$r" = "R03" ]; then dest="$ROOT/R03/base"; fi

  if git -C "$dest" rev-parse HEAD 2>/dev/null | grep -qx "$commit"; then
    echo "=== $r already present at correct commit, skipping ==="
    continue
  fi

  echo "=== $r: cloning $url @ $commit -> $dest ==="
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$url"
  git -C "$dest" fetch --depth 1 origin "$commit"
  git -C "$dest" checkout -q FETCH_HEAD
  actual=$(git -C "$dest" rev-parse HEAD)
  if [ "$actual" != "$commit" ]; then
    echo "!!! $r: commit mismatch after checkout (got $actual, want $commit)" >&2
    exit 1
  fi
  echo "=== $r: OK at $actual ==="
done

echo "=== All base clones verified ==="
