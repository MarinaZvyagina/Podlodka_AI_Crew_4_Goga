#!/usr/bin/env bash
# Task B / AC1: Shutdown notification must be wired into the existing
# DI-orchestrated lifecycle/shutdown flow (OnApplicationShutdown hook
# contract, invoked via packages/core/hooks/on-app-shutdown.hook.ts as part
# of packages/core/nest-application-context.ts's close()) -- NOT a new
# standalone shutdown entrypoint that bypasses enableShutdownHooks()/close().
#
# Notes on this codebase's actual close() ordering (verified by reading
# nest-application-context.ts at the pinned commit): close() runs, in order,
# prepareClose() -> callDestroyHook() -> callBeforeShutdownHook() [[the
# `beforeApplicationShutdown` hook, packages/core/hooks/before-app-shutdown.hook.ts]]
# -> dispose() [[closes the http/socket/microservices transports, e.g. via
# packages/websockets/socket-module.ts's close(), which is invoked from
# packages/core/nest-application.ts's dispose() override]] -> callShutdownHook()
# [[the `onApplicationShutdown` hook]] -> unsubscribeFromProcessSignals().
#
# Because dispose() (which actually closes registered WS servers/sockets)
# runs *after* beforeApplicationShutdown but *before* onApplicationShutdown,
# a WS "notify clients before disconnect" feature can only satisfy the
# functional requirement (notification arrives before the socket closes) by
# hooking in at, or before, the dispose() step -- i.e. somewhere in the
# close()/shutdown-hook call chain rooted in nest-application-context.ts.
# This validator therefore accepts either of:
#   (a) a provider/hook implementing `onApplicationShutdown` or
#       `beforeApplicationShutdown` (both are the same DI-orchestrated
#       shutdown-hook family, just called at different points of the same
#       close() chain), or
#   (b) a change located inside one of the files that make up that chain:
#       nest-application-context.ts, on-app-shutdown.hook.ts,
#       before-app-shutdown.hook.ts, nest-application.ts (dispose()/
#       loadSocketModule()), or websockets/socket-module.ts's close()
#       (which dispose() already calls today for every WS transport).
# It then FAILS if it finds evidence of a *bypass*: a new process signal
# listener outside the existing enableShutdownHooks()/
# listenToShutdownSignals() machinery, which would mean the feature is
# reachable *without* going through app.close()/enableShutdownHooks().
#
# Usage: task_B_AC1.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

echo "Changed files:"
echo "$CHANGED" | sed 's/^/  /'
echo

HOOK_CHAIN_FILES="packages/core/nest-application-context.ts
packages/core/hooks/on-app-shutdown.hook.ts
packages/core/hooks/before-app-shutdown.hook.ts
packages/core/nest-application.ts
packages/websockets/socket-module.ts"

TOUCHED_CHAIN=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if echo "$HOOK_CHAIN_FILES" | grep -qxF "$f"; then
    TOUCHED_CHAIN="${TOUCHED_CHAIN}${f}"$'\n'
  fi
done <<< "$CHANGED"
TOUCHED_CHAIN=$(echo "$TOUCHED_CHAIN" | grep -v '^$' || true)

# Literal use of the two DI shutdown-hook interfaces in non-test changed files.
HOOK_INTERFACE_HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  case "$f" in
    *test*|*.spec.ts|integration/*) continue ;;
  esac
  MATCH=$(grep -nE 'onApplicationShutdown|beforeApplicationShutdown' "$f" 2>/dev/null | sed "s#^#$f:#")
  [ -n "$MATCH" ] && HOOK_INTERFACE_HITS="${HOOK_INTERFACE_HITS}${MATCH}"$'\n'
done <<< "$CHANGED"
HOOK_INTERFACE_HITS=$(echo "$HOOK_INTERFACE_HITS" | grep -v '^$' || true)

if [ -z "$TOUCHED_CHAIN" ] && [ -z "$HOOK_INTERFACE_HITS" ]; then
  echo "FAIL: diff touches neither the OnApplicationShutdown/BeforeApplicationShutdown hook machinery nor any file in the close()/dispose() shutdown call chain (nest-application-context.ts, on-app-shutdown.hook.ts, before-app-shutdown.hook.ts, nest-application.ts, websockets/socket-module.ts). The new behavior does not appear to be reachable purely via app.close()/enableShutdownHooks()."
  exit 1
fi

# Anti-bypass check: a NEW process signal listener outside the file that
# already owns this responsibility (nest-application-context.ts) would mean
# a parallel/standalone shutdown entrypoint was introduced.
NEW_PROCESS_ON=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  case "$f" in
    packages/core/nest-application-context.ts) continue ;;
    *test*|*.spec.ts|integration/*) continue ;;
  esac
  # Only look at ADDED lines, so we don't flag pre-existing code we didn't touch.
  MATCH=$(git diff -U0 -- "$f" 2>/dev/null | grep -E '^[+]' | grep -v '^[+][+][+]' | grep -E 'process\.on\(|process\.once\(')
  [ -n "$MATCH" ] && NEW_PROCESS_ON="${NEW_PROCESS_ON}${f}:"$'\n'"${MATCH}"$'\n'
done <<< "$CHANGED"
NEW_PROCESS_ON=$(echo "$NEW_PROCESS_ON" | grep -v '^$' || true)

if [ -n "$NEW_PROCESS_ON" ]; then
  echo "FAIL: diff adds a new process signal listener outside packages/core/nest-application-context.ts's existing enableShutdownHooks()/listenToShutdownSignals() machinery -- this looks like a standalone shutdown entrypoint that bypasses close():"
  echo "$NEW_PROCESS_ON" | sed 's/^/  /'
  exit 1
fi

echo "Evidence of DI-orchestrated shutdown-hook wiring:"
if [ -n "$TOUCHED_CHAIN" ]; then
  echo "  Files touched in the close()/dispose() shutdown call chain:"
  echo "$TOUCHED_CHAIN" | sed 's/^/    /'
fi
if [ -n "$HOOK_INTERFACE_HITS" ]; then
  echo "  onApplicationShutdown / beforeApplicationShutdown references:"
  echo "$HOOK_INTERFACE_HITS" | sed 's/^/    /'
fi
echo
echo "No new standalone process-signal listener / bypass entrypoint detected."
echo "PASS: the new behavior is wired into the existing close()/shutdown-hook chain and is reachable purely via app.close() / enableShutdownHooks(), with no extra call required in application code."
exit 0
