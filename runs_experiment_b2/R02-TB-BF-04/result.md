# R02-TB-BF-04

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: True
Cost: $2.6267031000000003
Duration: 453484ms, turns: 72

## Agent's own summary

All tests pass and `goga lint` stays clean. Summary of the change:

## What was added

A new `beacons.status` capability that lets an operator ask a minion, the same way `beacons.list` works, when each configured beacon last actually executed and whether that run errored:

- **`salt/beacons/__init__.py`** — `Beacon` now keeps an in-memory `beacon_status` map (`{name: {"last_run": epoch, "last_error": str|None}}`), updated live inside `process()` every time a beacon actually fires (success or exception) — no log reads, no waiting for a new cycle. A new `status_beacons(name=None)` method reports it over the minion event bus (`/salt/minion/minion_beacons_status_complete`), same pattern as `list_beacons`/`list_available_beacons`. Beacons that haven't fired yet report `last_run: None, last_error: None` — explicit rather than stale/fabricated.
- **`salt/minion.py`** — wired `"status"` into the `manage_beacons` dispatch table, and made `beacons_refresh()` thread the `beacon_status` map into the replacement `Beacon` instance (mirroring how `interval_map` is already preserved), so a config/pillar refresh doesn't wipe out history.
- **`salt/modules/beacons.py`** — new `beacons.status(name=None)` execution-module function, following the exact request/event round-trip pattern used by `beacons.list`/`beacons.list_available`. Usable as `salt '*' beacons.status` or `salt '*' beacons.status ps`.
- Unit tests in `tests/pytests/unit/test_beacons.py` and `tests/pytests/unit/modules/test_beacons.py`, plus a changelog fragment.

I checked `goga schema`/`goga lint` first: `salt/beacons` isn't part of the documented cell forest, and the touched `salt/minion.py`/`salt/modules/beacons.py` surfaces aren't part of their cells' documented representative sample, so no CODEMANIFEST update was needed — confirmed by `goga lint` staying at `errors: 0` before and after.
