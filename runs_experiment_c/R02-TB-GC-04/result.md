# R02-TB-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r02-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $2.5621585500000004
Duration: 284097ms, turns: 45

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new capability; no existing behavior is being fixed or altered).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| *(ungoverned)* | `salt/beacons/__init__.py` | Add `import time`; add a `status_map` attribute on `Beacon` (preserved across refresh, mirroring `interval_map`); record `{"last_run": <epoch float>, "last_error": <str \| None>}` into it on every real beacon invocation inside `process()`; add new method `list_beacons_status()` mirroring `list_beacons()`'s enumerate/fire-reply shape |
| `salt` | `salt/minion.py`, `salt/CODEMANIFEST` | `Minion.beacons_refresh()`: preserve `status_map` the same way `interval_map` is preserved; `Minion.manage_beacons()`: add `"status": ("list_beacons_status", {})` to the `funcs` dispatch table; CODEMANIFEST: confirm no existing `Minion` manifest claim becomes false (no new manifest entity needed — `manage_beacons`/`beacons_refresh` aren't individually documented at manifest granularity today) |
| `salt/modules` | `salt/modules/beacons.py`, `salt/modules/CODEMANIFEST` | Add new function `status(return_yaml=True, **kwargs)` mirroring `list_()`'s fire/await/timeout/KeyError/return-yaml pattern exactly, targeting the new `/salt/minion/minion_beacons_status_complete` reply tag; CODEMANIFEST: add one new signature entry alongside the existing `beacons.py` entries (lines 1539–1629) |

## Root Cause Analysis
There is currently no in-memory record of "did this beacon run, and did it error." `Beacon.process()` (`salt/beacons/__init__.py:78-218`) computes success/failure per beacon on every invocation (the `try/except` around line 190) but only appends the result to a transient `ret` list returned to `Minion.process_beacons()`, which forwards it to the *master* as `__beacons_return` (per the research agent's finding at `minion.py:4606-4619`) — it is never fired back to a local listener and never persisted on `self`. No `manage_beacons` `func` value or `Beacon` method exists to answer "what's each beacon's last run/error," so today the only way to find out is grepping minion logs.

## Trace Summary
- **Write path (new)**: `Beacon.process()` try/except (`salt/beacons/__init__.py:188-203`) → new `self.status_map[mod] = {...}` write, added immediately after `error` is determined (success or exception), for beacons that reach this point only (post validation/interval/`disable_during_state_run` gating).
- **Read path (new)**: execution module `beacons.status()` (new, `salt/modules/beacons.py`) → `__salt__["event.fire"]({"func": "status"}, "manage_beacons")` → `Minion.manage_beacons()` dispatch table (`salt/minion.py:4162-4180`, new `"status"` entry) → `Beacon.list_beacons_status()` (new) → reads `self._get_beacons(...)` (existing, `salt/beacons/__init__.py:296-311`) merged with `self.status_map` → fires `/salt/minion/minion_beacons_status_complete` reply → execution module's `event_bus.get_event(...)` receives it and returns.
- **Refresh-survival path**: `Minion.beacons_refresh()` (`salt/minion.py:3998-4015`) already preserves `interval_map` across `Beacon` instance recreation (triggered by `beacons.add`/`modify`/`delete`/`saltutil.refresh_beacons`); `status_map` must follow the identical preserve-and-reconstruct pattern so a config edit doesn't erase real "last ran at X" history and falsely report a previously-run beacon as never-run.

## Change Strategy
1. **`salt/beacons/__init__.py`**
   - Add `import time` near the top (alongside existing `import re`, `import sys`).
   - `Beacon.__init__(self, opts, functions, interval_map=None, status_map=None)`: add `self.status_map = status_map or dict()`, mirroring the existing `self.interval_map = interval_map or dict()` line exactly.
   - Inside `process()`, immediately after the `try/except` block that sets `error` (lines 188-203), before the `if not error:` branch, add: `self.status_map[mod] = {"last_run": time.time(), "last_error": error}`. This fires for every beacon that reaches the "Fire the beacon!" step, whether it succeeded (`error is None`) or raised (`error` is the stringified exception) — but *not* for beacons skipped earlier by validation failure, unmet interval, or an in-progress state run, since those `continue` before reaching this line.
   - Add `list_beacons_status(self, include_pillar=True, include_opts=True)`: build `beacons = self._get_beacons(include_pillar=include_pillar, include_opts=include_opts)` (same call `list_beacons` already makes), then build a result dict keyed by beacon name where each value is either the recorded `self.status_map[name]` dict (with an added `"never_ran": False` key) or, if absent, an explicit `{"last_run": None, "last_error": None, "never_ran": True}` marker — never a fabricated timestamp. Fire the reply via `salt.utils.event.get_event("minion", opts=self.opts)` with tag `/salt/minion/minion_beacons_status_complete` and payload `{"complete": True, "beacons": <result dict>}`, matching `list_beacons`'s shape exactly. Return `True`.

2. **`salt/minion.py`**
   - `Minion.beacons_refresh()` (lines 3998-4015): capture `prev_status_map` the same way `prev_interval_map` is captured (guarded by `hasattr`), and pass `status_map=prev_status_map` into the new `Beacon(...)` construction call.
   - `Minion.manage_beacons()` `funcs` dict (lines 4162-4180): add `"status": ("list_beacons_status", {"include_opts": include_opts, "include_pillar": include_pillar})`, reusing the already-extracted `include_opts`/`include_pillar` locals (lines 4159-4160) exactly as `"list"` does.

3. **`salt/modules/beacons.py`**
   - Add `status(return_yaml=True, include_pillar=True, include_opts=True, **kwargs)`, copying `list_()`'s body structure verbatim except: `func` value is `"status"`, event payload also carries `include_pillar`/`include_opts` (matching `list_`'s call shape), awaited tag is `/salt/minion/minion_beacons_status_complete`, and the returned dict is under the key the reply provides (`beacons`). Same `KeyError` fallback (`{"result": False, "comment": "Event module not available. Beacon status failed."}`) and same `return_yaml` YAML-wrap-or-raw behavior.
   - No `__func_alias__` entry needed — `status` has no trailing-underscore/keyword collision.

4. **Manifest reconciliation** (Step 7 of the outer pipeline, not this step): add one `salt/modules/CODEMANIFEST` signature entry for `status` beside the existing `beacons.py` block; confirm `salt/CODEMANIFEST`'s `Minion` entity needs no edit (verified in Investigation — `manage_beacons`/`beacons_refresh` are not manifest-enumerated methods today, so extending their bodies doesn't invalidate any documented claim).

## Specification Impact
- **`salt/modules/CODEMANIFEST`**: one new Routine-style entry added after `disable_beacon`/before `reset`, or after `reset` — exact position doesn't matter since YAML mapping keys aren't order-sensitive for lookup, but will be placed adjacent to the other beacon entries for readability:
  ```yaml
  "status(return_yaml: bool, include_pillar: bool, include_opts: bool, ...kwargs: object) -> beacons:dict | str":
    location: beacons.py
    annotations: |
      Report each configured beacon's last-execution status (exposed as __salt__['beacons.status']).
      Fires a "status" manage_beacons event and waits for the minion_beacons_status_complete reply.
      Each beacon entry reports last_run (epoch timestamp) and last_error (string or None) if it has
      executed at least once since the minion's Beacon instance was created, or {"never_ran": True,
      "last_run": None, "last_error": None} if it has not yet fired. Returns YAML text by default or a
      raw dict; returns `{"result": False, "comment": ...}` if the event system isn't available.
  ```
  This is purely additive — no existing entry's text changes.
- **`salt/CODEMANIFEST`**: no textual change anticipated; Drift Analysis (pipeline Step 9) will confirm the `Minion` entity's existing annotations don't implicitly claim an exhaustive `manage_beacons`/`beacons_refresh` behavior set that this addition would falsify.

## Usage Impact
Neither `salt` nor `salt/modules` has any `.usages/` files today (`usages: []` in `goga schema` for both). No usage file changes are required; none will be created unless the manifest-reconciliation step determines the new `beacons.py` entry needs consumer-facing guidance beyond its annotation (unlikely, since no sibling beacon function has a usage file either).

## Compatibility Verification
**Backward compatible.** No existing function signature, event tag, reply payload shape, or file path changes. `Beacon.__init__` gains a new *optional* keyword parameter (`status_map=None`) with a default that preserves current behavior for every existing caller (`salt.beacons.Beacon(opts, functions)` and `salt.beacons.Beacon(opts, functions, interval_map=...)` both continue to work unchanged). `process()` gains a new side-effect write but its return value and control flow are untouched, so `test_beacon_process`'s `ret == _expected` assertion (`tests/pytests/unit/test_beacons.py:44`) is unaffected. `beacons_refresh()` gains an additional preserved attribute using the same guarded `hasattr` pattern already in place. No STOP condition triggered.

## Test Strategy
- **`tests/pytests/unit/test_beacons.py`**:
  - Extend/add a test alongside `test_beacon_process` asserting that after a successful `beacon.process(...)` call, `beacon.status_map[mod]` contains a `last_run` float timestamp and `last_error is None`.
  - Extend/add a test alongside `test_beacon_process` (or a variant of the existing exception-path test) asserting that after a beacon raises, `beacon.status_map[mod]["last_error"] == "Global Thermonuclear War"` (matching the existing mock in that test) and `last_run` is set.
  - New test confirming `test_beacon_process_invalid`-style skipped beacons (failed validation, or beacon module not found) do **not** get a `status_map` entry — i.e., they remain reported as never-run.
  - New test for `Beacon.list_beacons_status()`: configure one beacon that has run (asserts real `last_run`/`last_error`) and one that hasn't (asserts the explicit `never_ran: True` / `last_run: None` marker), mock `salt.utils.event.get_event` the same way other handler tests do, assert the fired payload shape.
- **`tests/pytests/unit/modules/test_beacons.py`**: new `test_status()` mirroring `test_add`/`test_delete`'s `SaltEvent.get_event` `side_effect` list mocking (lines 27-52), asserting `beacons.status()` returns the dict from the mocked `/salt/minion/minion_beacons_status_complete` reply, and a variant asserting `return_yaml=False` returns the raw dict.
- **`tests/pytests/integration/modules/test_beacons.py`** (optional but recommended per the research agent's finding of existing fixtures like `beacon_instance`): end-to-end test that configures a real beacon, lets it fire at least once via the existing `salt_call_cli` fixture pattern, then calls `beacons.status` and asserts a real `last_run` appears — this is the only test tier that can prove the "reflects real beacon activity as it happens" requirement against an actual running minion process rather than a mocked one.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `status_map` not preserved across `beacons_refresh()`, silently resetting real history to "never run" on every config edit | Medium (easy to forget — it's a manual mirror of the `interval_map` pattern, not automatic) | Medium — misleading operator-facing data, though not a crash | Explicitly implement the same guarded `hasattr`/constructor-passthrough preservation as `interval_map` (Change Strategy step 2); cover with a unit test that calls `beacons_refresh()` and asserts `status_map` survives |
| New `status_map` write placed on the wrong side of a `continue` in `process()`, causing skipped/invalid beacons to get a fabricated entry | Low (single well-understood insertion point identified in Investigation) | Medium — violates the explicit "never-run must not be fabricated" requirement | Unit test `test_beacon_process_invalid`-style case asserting no `status_map` entry is created for skipped beacons |
| Multimaster / `beacons_leader=False` processes never populate `status_map` since `manage_beacons` and `process()` both early-return for non-leader processes | Low — this matches existing behavior for all other beacon control operations (`list`, `enable`, etc. are also leader-only) | Low — consistent with existing multimaster design, not a regression | No mitigation needed; document as consistent with existing `beacons_leader` semantics, not a new limitation |
| Manifest drift: `salt/CODEMANIFEST`'s `Minion` annotations turn out to implicitly describe `manage_beacons`/`beacons_refresh` behavior that the addition would invalidate | Low (Investigation found no such claim) | Low | Confirmed explicitly in pipeline Step 9 (Drift Analysis) before finalizing |

---

Do you approve this plan? Proceed to implementation?
