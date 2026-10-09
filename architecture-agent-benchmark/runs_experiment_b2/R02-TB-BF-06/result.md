# R02-TB-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: True
Cost: $2.0635239
Duration: 348877ms, turns: 54

## Agent's own summary

## Summary

Added a `beacons.status` execution-module function that lets an operator ask a minion, via the same RPC-style pattern as `beacons.list`, when each configured beacon last actually fired and whether that run errored — live, in-memory data updated as beacons run, with no log reads, no waiting for the next probe cycle, and no restart/reconfig required.

**Investigation:** Ran `goga schema`/`goga lint` first — the touched code (`salt/beacons/__init__.py`'s `Beacon` class, `salt/modules/beacons.py`, `salt/minion.py`'s beacon plumbing) isn't part of the 9 documented cells (which explicitly scope themselves to curated samples, e.g. 3-of-267 `salt/modules` functions), so this was a normal extension of an undocumented subsystem rather than a goga-governed contract change. `goga lint` stayed clean (9 cells, 0 errors) after the change.

**Changes:**
- `salt/beacons/__init__.py`: `Beacon` now tracks `self.status[beacon_name] = {"last_fired": <epoch time>, "last_error": <str or None>}`, updated in `process()` only when a beacon actually fires (not when skipped for interval/disabled/state-run reasons). New `beacon_status(name=None)` method mirrors `list_beacons()`'s event-fire pattern, returning `last_fired: None` for beacons that haven't fired yet, and `complete: False` for an unknown beacon name.
- `salt/minion.py`: wired `"status"` into `manage_beacons()`'s dispatch table, and — like the existing `interval_map` — carries the status dict across `beacons_refresh()` so it survives module/pillar refreshes without resetting.
- `salt/modules/beacons.py`: new `status(name=None, **kwargs)` function, following the same `event.fire`/`get_event` request-response pattern as `list_`, `enable_beacon`, etc.
- Tests added at all three layers (`Beacon.process`/`beacon_status`, `Minion.manage_beacons`/`beacons_refresh`, `beacons.status` module function), all passing. Also added `changelog/69890.added.md`.

One pre-existing, unrelated test failure (`test_minion_manager_async_stop`, an `AF_UNIX path too long` issue from this deeply-nested working directory) was confirmed present on `main` before my changes too.
