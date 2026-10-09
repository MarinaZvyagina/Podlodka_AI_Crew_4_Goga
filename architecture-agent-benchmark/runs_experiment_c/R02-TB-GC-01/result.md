# R02-TB-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r02-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.4443229999999998
Duration: 237455ms, turns: 42

## Agent's own summary

# Change Plan

## Task Classification
Feature (additive extension) — new minion-side beacon status query, no modification of existing behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| *(out-of-cell)* | `salt/beacons/__init__.py` | New `import time`; new `beacon_status` constructor param + attribute; status recorded in `process()`; new `list_beacon_status()` method. |
| `salt` | `salt/minion.py` | `beacons_refresh()` threads `beacon_status` through instance replacement like `interval_map`; `manage_beacons()`'s `funcs` dict gains one entry. |
| `salt/modules` | `salt/modules/beacons.py`, `salt/modules/CODEMANIFEST` | New `status()` routine + new CODEMANIFEST entry. |

## Root Cause Analysis
Not a defect — net-new capability. Investigation confirmed (HIGH confidence): the only beacon-invocation site is `Beacon.process()`'s try/except at `salt/beacons/__init__.py:187-203`, which already isolates success/error per mod but discards that outcome after firing the event; `interval_map` is the established, already-shipped precedent for per-beacon runtime state that must survive `beacons_refresh`'s instance replacement; `list_beacons`/`list_available_beacons` establish the manager-method → event-tag → module-function contract shape to replicate verbatim.

## Trace Summary
`salt '*' beacons.status` → `beacons.py:status()` fires `manage_beacons{func:"status"}` → `minion.py:manage_beacons` dispatch (`funcs["status"]`) → `Beacon.list_beacon_status()` fires `/salt/minion/minion_beacons_status_complete` → `beacons.py:status()`'s `event_bus.get_event(...)` returns the dict.
Write side: `Beacon.process()` → per-mod gates (`enabled`, `validate`, interval, `disable_during_state_run`) → only mods that reach the invocation try/except get a `self.beacon_status[mod]` write.
Refresh side: `minion.py:beacons_refresh()` → reads `self.beacons.beacon_status` off the outgoing instance → passes into the new `Beacon(...)` constructor, same shape as `interval_map`.

## Change Strategy

**1. `salt/beacons/__init__.py`**
- Add `import time` alongside existing `import sys` (line 8).
- `__init__` (line 21): add `beacon_status=None` parameter; add `self.beacon_status = beacon_status or dict()` (line 27, after `self.interval_map` assignment).
- `process()` (after line 203, once `error` is finalized for both the except and non-except path — i.e. right before `if not error:` at line 204): add
  ```python
  self.beacon_status[mod] = {"last_fired": time.time(), "last_error": error}
  ```
  Placed here (not inside the `try` block) so it runs exactly once per actual invocation regardless of outcome, and never runs for `continue`d mods (disabled, invalid, interval-not-reached, state-run-skipped) — those paths `continue` before line 187 or at line 183, never reaching this line.
- New method `list_beacon_status(self)`, placed after `list_available_beacons` (after line 353), mirroring its structure exactly:
  ```python
  def list_beacon_status(self):
      """
      Return the last-fired time and last error for each currently configured beacon
      """
      configured = self._get_beacons()
      status = {}
      for name in configured:
          if name == "enabled":
              continue
          status[name] = self.beacon_status.get(name, {"last_fired": None, "last_error": None})

      with salt.utils.event.get_event("minion", opts=self.opts) as evt:
          evt.fire_event(
              {"complete": True, "beacon_status": status},
              tag="/salt/minion/minion_beacons_status_complete",
          )

      return True
  ```
  This guarantees every currently-configured beacon appears in the response — beacons absent from `self.beacon_status` (never fired) get an explicit `{"last_fired": None, "last_error": None}` rather than being omitted, so "never fired" is unambiguous and never fabricated.

**2. `salt/minion.py`**
- `beacons_refresh()` (lines 3998-4015): add, alongside the existing `prev_interval_map` block:
  ```python
  prev_beacon_status = {}
  if hasattr(self, "beacons") and hasattr(self.beacons, "beacon_status"):
      prev_beacon_status = self.beacons.beacon_status
  ```
  and extend the `salt.beacons.Beacon(...)` call (line 4013) with `beacon_status=prev_beacon_status`.
- `manage_beacons()`'s `funcs` dict (lines 4162-4180): add `"status": ("list_beacon_status", {})`.

**3. `salt/modules/beacons.py`**
- New function `status(return_yaml=True, **kwargs)`, inserted after `list_available` (after line 123, before `def add`), following `list_`/`list_available`'s structure: event-fire `{"func": "status"}` on `"manage_beacons"`, wait on `/salt/minion/minion_beacons_status_complete` (`kwargs.get("timeout", default_event_wait)`), same `try/except KeyError` fallback (`{"result": False, "comment": "Event module not available. Beacon status failed."}`), `return_yaml` toggle wrapping `{"beacon_status": ...}` via `salt.utils.yaml.safe_dump` or raw dict passthrough. No `__func_alias__` needed.

## Specification Impact
`salt/modules/CODEMANIFEST` gains one new Routine entry for `status`, inserted after the existing `list_available` entry, in the same annotation style (purpose sentence + fired event tag + wait/timeout behavior + return shape + `return_yaml` toggle), e.g.:
```yaml
"status(return_yaml: bool, ...kwargs: object) -> beacon_status:dict | str":
  location: beacons.py
  annotations: |
    Report, for every currently configured beacon, the timestamp of its last actual execution
    and the error (if any) from that execution (exposed as __salt__['beacons.status']). Fires a
    "status" manage_beacons event and waits (default 60s, override via kwargs['timeout']) for
    the minion_beacons_status_complete reply. Each beacon that has never fired is reported with
    `last_fired: None, last_error: None` rather than being omitted. Returns YAML text by default
    (return_yaml=True) or a raw dict; returns `{"result": False, "comment": ...}` if the event
    system isn't available.
```
No existing CODEMANIFEST entry is modified. `salt/CODEMANIFEST` (the `salt` cell) is unaffected at the manifest level — `manage_beacons`/`beacons_refresh` are pre-existing undocumented dispatch plumbing (same tier as the current `add`/`modify`/`delete`/`enable` funcs-dict entries, none of which are separately documented), so adding one dict entry and threading one extra constructor kwarg does not introduce a new documented contract element requiring reconciliation.

## Usage Impact
No `.usages/` files exist for either `salt` or `salt/modules` referencing beacon event conventions (confirmed in Investigation Report — Affected Usages: none declared). No usage file changes required.

## Compatibility Verification
**Backward compatible.** `Beacon.__init__`'s new `beacon_status` parameter is keyword-only-by-convention with a default of `None` (matching the existing `interval_map=None` precedent) — all existing call sites (`salt.beacons.Beacon(opts, functions)`, `salt.beacons.Beacon(opts, self.functions)`, and test constructions) are unaffected. `process()`'s new line only appends to a new dict; it doesn't alter `ret`, control flow, or timing. `manage_beacons`'s `funcs` dict gains a key; existing keys/values are untouched. `beacons.py` gains a new top-level function; no existing function body changes. No return shape, file path, or manifest guarantee for any existing entry is altered.

## Test Strategy
- `tests/pytests/unit/test_beacons.py`: extend/add a test alongside `test_beacon_process` asserting that after `process()` runs a beacon successfully, `beacon_status[mod]` has a `last_fired` float and `last_error is None`; add a case mirroring `test_beacon_process_invalid` (or a forced-exception variant) asserting `last_error` captures the exception string; add a case where a beacon is skipped via interval-not-reached and assert no `beacon_status` entry is created; add a direct test of `list_beacon_status()` asserting it fires the `minion_beacons_status_complete` event with an entry for every configured beacon, including `{"last_fired": None, "last_error": None}` for one that was configured but never invoked.
- `tests/pytests/unit/modules/test_beacons.py`: add a test for `beacons.status()` mirroring the existing `list_`/`list_available` tests — mock the event round-trip, assert the fired event dict (`{"func": "status"}`), assert `return_yaml` toggling, and assert the `KeyError`/event-unavailable fallback path.
- No changes to existing tests required (nothing existing changes behavior).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `self.beacon_status` grows unbounded if beacon names change frequently (e.g. add/delete churn) leaving stale entries keyed by deleted beacon names | Low | Low | `list_beacon_status()` only surfaces entries whose key is in `_get_beacons()` today, so stale entries for deleted beacons are never returned even if retained internally; acceptable given `interval_map` has the identical unbounded-retention characteristic already in production. |
| Timestamp clock skew/non-monotonic `time.time()` across NTP adjustments | Low | Low | Matches existing codebase convention (no monotonic-clock usage elsewhere in this file); out of scope to change. |
| A future beacon rename via `beacon_module` override could reuse `mod` as key inconsistently with `beacon_name` | Low | Low | Status is keyed by `mod` (the configured name), consistent with how `self.opts["beacons"]` and `_get_beacons()` are already keyed — matches existing addressing scheme used throughout the file. |

---

Do you approve the plan? Proceed to implementation?
