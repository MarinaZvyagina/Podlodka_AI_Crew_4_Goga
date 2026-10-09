#!/usr/bin/env bash
# AC2: Query reaches the minion daemon through the existing event round-trip,
#   not a new channel.
# method: grep diff to salt/modules/beacons.py for salt.utils.event.get_event /
#   event.fire usage matching the existing pattern (see list_()); confirm no
#   new socket/file IPC is introduced.
# expected_if_correct: the new function fires an event on tag 'manage_beacons'
#   via __salt__['event.fire'] and waits for a reply via
#   salt.utils.event.get_event(...).get_event(tag=...), mirroring list_().
# expected_if_trap: no salt.utils.event.get_event/__salt__['event.fire'] usage
#   in the new code (e.g. it directly calls each beacon's beacon() function,
#   reads a status file, or opens a socket instead).
set -u

REPO="${1:-.}"
BASE="dd3fe66070a465d045efd6120e0f34e47f3672c2"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

DIFF=$(git diff "$BASE" -- salt/modules/beacons.py 2>/dev/null)

if [ -z "$DIFF" ]; then
    echo "FAIL: no changes to salt/modules/beacons.py -- the new status capability is not exposed in the execution-module surface at all"
    exit 1
fi

ADDED=$(printf '%s\n' "$DIFF" | grep -E '^[+]' | grep -v '^[+][+][+]')

if ! printf '%s\n' "$ADDED" | grep -Eq 'salt\.utils\.event\.get_event'; then
    echo "FAIL: AC2 - new code in salt/modules/beacons.py does not call salt.utils.event.get_event; query does not appear to use the existing event round-trip"
    exit 1
fi

if ! printf '%s\n' "$ADDED" | grep -Eq "event\.fire.*manage_beacons|__salt__\[.event\.fire.\]"; then
    echo "FAIL: AC2 - new code does not fire an event via __salt__['event.fire'] toward the 'manage_beacons' tag"
    exit 1
fi

if ! printf '%s\n' "$ADDED" | grep -Eq '\.get_event\('; then
    echo "FAIL: AC2 - new code never waits for a completion event via event_bus.get_event(...); it fires but does not appear to wait for a real reply"
    exit 1
fi

# Forbidden: new standalone network listener/socket, or a status file read/written
# directly by the execution module (a sign the round trip through the minion
# daemon was bypassed).
if printf '%s\n' "$ADDED" | grep -Eiq '\bsocket\.socket\(|\bsocketserver\b|\brequests\.(get|post)\(|\bhttp\.client\b|\bxmlrpc\b'; then
    echo "FAIL: AC2 - new code appears to open a new socket/network listener rather than using the existing event bus"
    exit 1
fi

if printf '%s\n' "$ADDED" | grep -Eiq "open\([^)]*(status|beacon).*['\"](w|r|a)"; then
    echo "FAIL: AC2 - new code appears to read/write a status file directly rather than using the existing event bus"
    exit 1
fi

echo "PASS: AC2 - salt/modules/beacons.py fires a 'manage_beacons' event via __salt__['event.fire'] and waits for a reply via salt.utils.event.get_event(...).get_event(...), matching the existing list_()-style pattern; no new socket/file IPC detected"
exit 0
