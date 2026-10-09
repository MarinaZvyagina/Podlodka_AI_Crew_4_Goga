# R02-TB-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r02-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.7421488
Duration: 388485ms, turns: 66

## Agent's own summary

## Change Plan

### Task Classification
**Feature** (net-new, additive capability; no existing behavior modified).

### Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `salt/modules` | `salt/modules/beacons.py`, `salt/modules/CODEMANIFEST` | New `status()` function + matching CODEMANIFEST entry |
| `salt` (root) | `salt/minion.py` | `Minion.manage_beacons` gains a `"status"` dispatch entry; `Minion.beacons_refresh()` preserves the new tracking dict across `Beacon` recreation. **No CODEMANIFEST change** (see Specification Impact). |
| non-cell `salt/beacons/` | `salt/beacons/__init__.py` | `Beacon.__init__` gains optional `beacon_status` param; `Beacon.process()` records last-fired time + error per beacon; new `Beacon.get_beacon_status()` method |

### Root Cause Analysis
Not a defect — a missing capability. `Beacon.process()` already computes, per beacon, whether the fire succeeded or raised (the `error` local), but discards it once the per-fire event is queued. No code path anywhere records firing history; operators are left with log-scraping as the only recourse.

### Trace Summary
`beacons.status()` (new) → `event.fire("manage_beacons", {"func": "status", ...})` → `Minion.manage_beacons` (existing dispatcher, new table entry) → `Beacon.get_beacon_status()` (new) → reads `Beacon.beacon_status` (new dict, written by `Beacon.process()` on every real fire) → fires `/salt/minion/minion_beacons_status_complete` → `status()` receives it via `event_bus.get_event(...)`. This is structurally identical to the existing `list`/`list_available` round trip.

### Change Strategy
1. **`salt/beacons/__init__.py`**
   - `Beacon.__init__(self, opts, functions, interval_map=None, beacon_status=None)`: add `self.beacon_status = beacon_status or {}`.
   - `Beacon.process()`: in the existing fire block, after the try/except that sets `error`, add:
     - on the error branch: `self.beacon_status[mod] = {"last_fired": <utc-iso-now>, "error": error}`
     - on the success branch (no error): `self.beacon_status[mod] = {"last_fired": <utc-iso-now>, "error": None}`
     - Timestamp: `datetime.datetime.now(datetime.timezone.utc).isoformat()` — stdlib only, no new dependency, unambiguous and directly comparable/sortable as a string.
   - New method `get_beacon_status(self, name=None)`: build `ret` over currently-configured beacons (via existing `_get_beacons()`), each entry = `self.beacon_status.get(beacon_name, {"last_fired": None, "error": None})` — an absent `beacon_status` entry (i.e. `last_fired is None`) *is* the explicit "never fired" signal, never a stale/fabricated value. If `name` given, restrict to that single beacon (empty `ret` if not configured — mirrors how `list_beacons`/other methods let the caller detect "not found" from an empty/missing key rather than raising). Fire `{"complete": True, "beacons": ret}` on tag `/salt/minion/minion_beacons_status_complete`, matching `list_beacons()`'s pattern exactly. Return `True`.
2. **`salt/minion.py`**
   - `Minion.manage_beacons`: add `"status": ("get_beacon_status", {"name": name}),` to the `funcs` dict (uses the `name` var already extracted at the top of the method — no new extraction needed).
   - `Minion.beacons_refresh()`: mirror the existing `prev_interval_map` preservation — read `prev_beacon_status = self.beacons.beacon_status` (if present) before closing/replacing, and pass `beacon_status=prev_beacon_status` into the new `Beacon(...)` construction, so a routine module/pillar refresh does not wipe firing history back to "never fired."
3. **`salt/modules/beacons.py`**
   - New `status(name=None, **kwargs)`: fires `{"func": "status", "name": name}` on `"manage_beacons"`, waits on `/salt/minion/minion_beacons_status_complete` (default 60s / `kwargs["timeout"]`), returns the `beacons` dict from the completion event, or the standard `{"result": False, "comment": "Event module not available. ..."}` fallback on `KeyError` — same shape as `list_`/`list_available` minus the `return_yaml` option (not requested; status output is a dict of structured data, not a config blob, so YAML round-tripping doesn't apply the way it does to beacon *configuration*).

### Specification Impact
- `salt/modules/CODEMANIFEST`: **add** one new entry `"status(name: str | None, ...kwargs: object) -> beacons:dict"` under `location: beacons.py`, placed after `list_available` (logical grouping: query operations before mutating ones), annotation describing the manage_beacons event round trip and the never-fired semantics — matching the exact prose style of the 10 sibling entries already in that file.
- `salt/CODEMANIFEST`: **no change.** The `Minion` entity in this manifest already documents only a curated subset of methods (`_load_modules`, `sync_connect_master`, three properties) and its own annotation states it documents the composition-root role, not an exhaustive method list. `manage_beacons` and `beacons_refresh` are pre-existing, already-undocumented methods; adding one dispatch-table line and one preserved variable to each does not change any documented contract. Adding these methods to the manifest now would be scope creep unrelated to this change (it would newly document ~15 other undocumented `Minion` methods' worth of precedent-setting, which is out of scope).

### Usage Impact
No `.usages/` files reference the beacon RPC pattern today (all 10 existing `beacons.py` entries document the pattern inline in their own CODEMANIFEST annotations, with no dedicated practice file). Following that established precedent, **no usage file is added or modified** — a new one would duplicate what the CODEMANIFEST annotation already says, which `goga-cookbook` explicitly discourages ("Practices must not duplicate annotations").

### Compatibility Verification
**Backward compatible.** No existing function signature, return shape, or behavior changes:
- `Beacon.__init__(opts, functions)` (2-arg call sites, e.g. every existing test) remains valid — `interval_map` and `beacon_status` are both optional kwargs.
- `Beacon.process()`'s return value (`ret`, the list of fired-beacon event dicts) is unchanged; the new recording is a pure side effect on a new attribute.
- `Minion.manage_beacons`'s existing `funcs` entries and behavior for `add`/`modify`/`delete`/`list`/etc. are untouched — only a new key is added to the dict.
- `Minion.beacons_refresh()`'s existing behavior (interval preservation, closing old beacon modules) is unchanged; only an additional preserved value is threaded through.

### Test Strategy
- `tests/pytests/unit/test_beacons.py`:
  - Extend/add a test asserting that after a successful `beacon.process(...)` call, `beacon.beacon_status[mod]` has `error is None` and a non-`None` `last_fired` (reuses the existing `test_beacon_module` fixture scenario).
  - Extend/add a test reusing the existing `test_beacon_process` error-mock scenario, asserting `beacon.beacon_status["watch_apache"]["error"] == "Global Thermonuclear War"` and `last_fired` is set.
  - New test for `get_beacon_status()`: configure a beacon, call it *without* ever calling `process()` first, assert the returned (via `patch("salt.utils.event.get_event")`, inspecting the `fire_event` call args — same mocking style as `test_delete_beacon_calls_close`) status dict shows `last_fired is None` for that beacon (never-fired case).
  - New test: call `process()` once, then `get_beacon_status()`, assert the recorded `last_fired`/`error` surface unchanged through the method.
  - New test for `beacons_refresh()` (in the minion-focused test file, likely `tests/pytests/unit/test_minion.py` if one exists with `beacons_refresh` coverage — otherwise add alongside existing interval_map-preservation assertions if such a test exists) confirming `beacon_status` survives a refresh cycle, mirroring however `interval_map` preservation is currently tested (need to check for an existing `interval_map` preservation test during implementation to mirror its exact fixture).
- `tests/pytests/unit/modules/test_beacons.py`: new `test_status()` mirroring `test_delete()`'s shape — mock `SaltEvent.get_event` to return one event dict with `tag="/salt/minion/minion_beacons_status_complete"` and a sample `beacons` payload, mock `event.fire`, assert `beacons.status()` returns that payload unchanged.

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `beacons_refresh()` still resets history despite the plan (if an existing `interval_map`-preservation test doesn't actually exist to mirror) | Low | Medium (feature silently "forgets" history on routine refreshes, contradicting the "as it happens" requirement) | Verify the preservation logic manually during implementation by writing a direct unit test that calls `beacons_refresh()` twice and asserts `beacon_status` survives, independent of whether an `interval_map` precedent test exists |
| Event system unavailable (`KeyError` path) leaves operators with an unhelpful response for the new `status()` call | Low | Low | Reuse the exact existing fallback shape (`{"result": False, "comment": "..."}`) already used by every sibling function, so behavior here is consistent with the rest of the module |
| `beacon_status` dict grows unbounded if beacon names change frequently (add/delete churn) | Low | Low | Out of scope for this task (not requested); `get_beacon_status()` only ever *reads* entries for currently-configured beacon names, so stale entries for deleted beacons are simply never surfaced, not actively pruned — acceptable, matches how `interval_map` already behaves (also never pruned on delete) |

---

Do you approve the plan? Proceed to implementation?
