# R02-TB-GC-10

Condition: goga_native_architecture
Base tag: condition-c-r02-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.8984652499999999
Duration: 197386ms, turns: 33

## Agent's own summary

## Investigation Report

## Task Summary
Add a live, in-memory, per-beacon "last execution timestamp + last error" query to a Salt minion's beacon system, following the same in-process event-bus RPC shape already used by `beacons.list`/`beacons.list_available`. State must persist across pillar/module refresh (no restart/config-change requirement) and must not fabricate a value for a beacon that has never fired.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| salt/modules | `beacons.py` needs a new client-facing function (`status`) using the existing event.fire/get_event RPC pattern | High |
| salt (root) | `minion.py`'s `MinionBase.beacons_refresh` and `Minion.manage_beacons` need new state-preservation and dispatch wiring | High |
| (non-cell) salt/beacons/__init__.py | `Beacon.process()`/`Beacon` class needs the actual state dict and a new query method — implementation site, no manifest governance | High |

## Tracing Summary
1. `Minion.handle_beacons()` (minion.py, periodic loop callback set up in `setup_beacons`) calls `self.beacons.process(config, grains)` every `loop_interval`.
2. `Beacon.process(self, config, grains)` (salt/beacons/__init__.py:78-218) iterates each configured beacon key `mod` in `config`. It resolves `beacon_name` (defaults to `mod`, overridden via `beacon_module` key — confirmed by `tests/pytests/unit/test_beacons.py::test_beacon_process`, which configures `mod="watch_apache"`, `beacon_module="ps"`, and asserts the returned event's `beacon_name` is `"ps"` while the tag embeds `mod`, i.e. `salt/beacon/minion/watch_apache/`). Validation, interval-skip, and disable-during-state-run checks can `continue` before the beacon function is ever invoked — in those cases `process()` produces no outcome for that beacon this cycle (status must remain whatever it already was, not overwritten).
3. Inside the `fun_str in self.beacons` branch (line 149 onward), the beacon function is called at line 190 (`raw = self.beacons[fun_str](b_config[mod])`) inside `try/except`. On exception, `error = f"{sys.exc_info()[1]}"` and an error event dict is appended (lines 191-203). On success, `raw` events are appended and, if `runonce` is set, `self.disable_beacon(mod)` is called (line 215) — `disable_beacon` only flips the `enabled` flag in `self.opts["beacons"][mod]`; it does not touch `interval_map` or any new status dict, so runonce beacons still need their one-time firing recorded before being disabled.
4. `self.interval_map` (dict, keyed by `mod`) is the only existing precedent for cross-cycle, cross-refresh in-memory state on `Beacon`. It's constructed in `__init__` (`interval_map=None` → `dict()`) and explicitly threaded through `MinionBase.beacons_refresh` (minion.py:3998-4015) when the `Beacon` instance is rebuilt after a pillar/module refresh.
5. `Beacon.list_beacons()` (salt/beacons/__init__.py:313-334) is the closest existing query shape: no args required beyond include flags, opens its own `salt.utils.event.get_event("minion", opts=self.opts)` and fires a completion event on a fixed tag, returns `True` (the real payload travels via the event, not the return value).
6. `Minion.manage_beacons(self, tag, data)` (minion.py:4149-4187) is the single RPC dispatch point: `func = data.get("func")`, looks up `funcs[func] = (method_name, kwargs)`, calls `getattr(self.beacons, method_name)(**kwargs)`. This is reached via the minion's own local event bus when tag starts with `"manage_beacons"` (minion.py ~4342-4343).
7. `salt/modules/beacons.py::list_()` (lines 22-77) is the client-side mirror: opens a listener on the minion event bus, fires `{"func": "list", ...}` on tag `"manage_beacons"`, blocks on `event_bus.get_event(tag="/salt/minion/minion_beacons_list_complete", wait=...)`, unpacks `event_ret["beacons"]`.

## Data Flow Analysis
`beacon function return/exception` → `Beacon.process()` (per-`mod` outcome known here, transiently) → **[new]** written into `Beacon.<state_dict>[mod]` → survives across `Beacon` re-instantiation via **[new]** carry-forward in `MinionBase.beacons_refresh` (same treatment as `interval_map`) → on-demand read by **[new]** `Beacon.<query_method>()`, fired as an event on the minion's local bus → received by `Minion.manage_beacons`'s **[new]** `funcs["status"]` entry dispatching to `Beacon.<query_method>` → **[new]** `salt/modules/beacons.py::status()` fires the request event and blocks on the completion event tag → returns the per-beacon dict to the caller (CLI/API), keyed by `mod` (the same key `list_beacons` uses, e.g. `"watch_apache"`), so results correlate 1:1 with `beacons.list` output. Beacons present in config but never yet fired (skipped by validation/interval/disable-during-state-run every cycle so far, or simply not yet reached) have no entry in the state dict — the query method must represent that explicitly (e.g. `None`/absent + a marker) rather than synthesizing a timestamp.

## Manifest Algorithm Analysis
- `salt/CODEMANIFEST` documents `MinionBase.process_beacons(functions) -> beacon_data:list[object]` (line ~111) — annotation: "Run configured beacon checks ... and return any events they fired." This describes `Minion.process_beacons`, a thin wrapper around `self.beacons.process(...)`; its documented return contract (`list[object]` of fired events) is unaffected by adding internal bookkeeping inside `process()` — no signature or return-shape change there.
- `manage_beacons`, `beacons_refresh`, `setup_beacons` are **not present** anywhere in `salt/CODEMANIFEST` today — confirmed by grep (no matches). There is no existing manifest text describing their `funcs` dict contents or refresh behavior, so adding a new dispatch case and a new state-preservation block does not contradict any documented algorithm; it does mean the manifest reconciler must decide whether/how to add first-time documentation for these, consistent with the cell's existing curated-subset granularity (this cell was not one of the 5 expanded-to-full-completeness cells per the restructuring commit).
- `salt/modules/CODEMANIFEST` documents `list_`, `list_available`, `enable_beacon`, `disable_beacon`, `reset`, etc. with annotations naming their exact event tags and reply shapes (e.g. `list_available`'s annotation explicitly names `minion_beacons_list_available_complete`). The new `status` function must get an equivalent entry naming its new event tag and reply shape — this is a net-new declaration, not a modification of an existing one.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| (none found) | salt, salt/modules | N/A | Neither cell's CODEMANIFEST declares any `Usages`/`Imports.Usages` entries referencing beacon RPC conventions; `goga config codemanifest.usages` returned "Option not found" (no project-level base usages either) |

## Rejected Hypotheses
- **"Reuse `interval_map` itself to store status"** — rejected: `interval_map` holds a loop-count integer with different lifecycle semantics (reset to `1` when the interval elapses); overloading it with timestamp/error data would corrupt `_process_interval`'s counting logic. A separate dict is required.
- **"Compute status by re-deriving from `salt/beacon/...` events already fired onto the event bus, without new in-memory state"** — rejected: fired events are transient pub/sub messages with no minion-side retention; nothing currently persists them, and reading historical events would require log/cache access, which the task explicitly excludes ("not require reading log files").
- **"Only track errors, since success is implied by absence of error"** — rejected: task explicitly requires the *last execution timestamp* regardless of outcome, and requires distinguishing "ran successfully with no error" from "never ran at all" — a boolean/absent-error alone can't do that.

## Confirmed Root Cause
The beacon subsystem has no mechanism for external observation of per-beacon runtime health short of grepping minion logs, because `Beacon.process()` discards the success/failure outcome the moment it's turned into a fired event — no component retains it. The fix requires: (1) minimal state capture at the single point `process()` learns the outcome (salt/beacons/__init__.py:188-215), (2) lifecycle preservation identical to the existing `interval_map` pattern so refreshes don't erase it (minion.py:3998-4015), and (3) exposure through the established request/response event-bus RPC pattern already used for every other beacon-management operation (`manage_beacons` dispatch + `salt/modules/beacons.py` client function). Evidence chain: direct reading of `salt/beacons/__init__.py` (process/list_beacons/interval_map), `salt/minion.py` (manage_beacons/beacons_refresh), `salt/modules/beacons.py` (list_/list_available), and `tests/pytests/unit/test_beacons.py::test_beacon_process` (confirms `mod` vs `beacon_name` key semantics).

## Confidence Level
**HIGH** — every insertion point is directly observed in current source (not inferred), the existing `interval_map` precedent gives an exact structural template for the new state, and the existing `list_beacons`/`list_` RPC pair gives an exact structural template for the new query. No ambiguity remains about where behavior must change.

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — `process()`'s existing return value (`ret`, the list of fired-event dicts) is unchanged; new state recording is a side effect written to a new attribute, not a change to any existing return path.
2. Will existing file paths change? **NO** — all changes are additive edits to `salt/beacons/__init__.py`, `salt/minion.py`, `salt/modules/beacons.py`.
3. Will output format change? **NO** — no existing function's output shape changes; only a new function/event tag is added.
4. Will return value semantics change? **NO** — `Beacon.__init__`'s new parameter (if added, e.g. `last_run=None`) will be optional with a default, preserving the existing `Beacon(opts, functions)` and `Beacon(opts, functions, interval_map=...)` call sites unchanged.
5. Will manifest-defined guarantees be altered? **NO** — `process_beacons(functions) -> beacon_data:list[object]`'s documented contract is untouched; no other documented method's contract changes.
6. Will existing tests break? **NO** — `test_beacon_process`/`test_beacon_process_invalid` assert on `ret` (the returned event list) and `log.error` calls only, neither of which changes; new tests will be additive.

No breaking change detected. Proceeding is safe per this analysis.
