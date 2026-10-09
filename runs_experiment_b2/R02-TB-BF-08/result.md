# R02-TB-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.4938545
Duration: 170116ms, turns: 39

## Agent's own summary

## Investigation Report

### Task Summary
Add an on-demand, minion-side query that reports each configured beacon's last-execution timestamp and whether that execution errored, sourced from live in-memory state captured while `Beacon.process()` actually fires beacons — not from logs, not requiring a new probe cycle, and surviving `Beacon` instance replacement during a live refresh. Beacons that have never fired must be reported as such, not defaulted to a fabricated value.

### Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `salt` (root) | `minion.py` owns `Minion.manage_beacons` (dispatch table) and `Minion.process_beacons`/`tune_in` (where `Beacon.process()` runs each loop) | High |
| `salt/modules` | `beacons.py` (undocumented file in this cell) owns the CLI-facing round-trip pattern (`list_`, `list_available`) to replicate | High |
| out-of-forest | `salt/beacons/__init__.py` — no cell; primary implementation site (`Beacon` class) | High (implementation), untracked by CODEMANIFEST |

### Tracing Summary
Confirmed end-to-end for the existing pattern, and for the closest precedent (`schedule.job_status`), which is a near-exact analog of the requested feature (per-item status query with an explicit "not found" case):

1. **CLI-facing call** — `salt/modules/beacons.py:list_()`/`list_available()` (and precedent `salt/modules/schedule.py:1535 job_status()`) each:
   - `__salt__["event.fire"]({"func": "<name>", ...}, "manage_beacons"/"manage_schedule")`
   - block on `event_bus.get_event(tag="/salt/minion/minion_<x>_complete", wait=timeout)`
   - `schedule.job_status` additionally converts any `datetime` values in the returned dict to strings via `time_fmt` before returning to the CLI (`salt/modules/schedule.py:1547-1569`) — directly reusable for a "last fired at" timestamp.

2. **Dispatch** — `salt/minion.py:handle_event()` routes `tag.startswith("manage_beacons")` → `Minion.manage_beacons(tag, data)` (`salt/minion.py:4149-4187`). This method is gated by `if not self.beacons_leader: return` (line 4153), then builds a `funcs = {...}` dict mapping `func` name → `(Beacon method name, kwargs dict)` and calls `getattr(self.beacons, alias)(**params)`. The precedent `Minion.manage_schedule` (`salt/minion.py:4113-4147`) has an exactly parallel `"job_status": ("job_status", (name, fire_event))` entry (line 4139) forwarding to `Schedule.job_status(name, fire_event=True)`.

3. **Beacon-side handler** — `salt/beacons/__init__.py:Beacon.list_beacons()`/`list_available_beacons()` build a payload and fire it via `salt.utils.event.get_event("minion", opts=self.opts).fire_event({...}, tag="/salt/minion/minion_beacons_list_complete")`.

4. **Actual execution loop** — `Beacon.process(config, grains)` (`salt/beacons/__init__.py:78-218`) iterates configured beacon modules `mod`. For each: resolves `beacon_name`, validates, then at line 188-203:
   ```python
   error = None
   try:
       raw = self.beacons[fun_str](b_config[mod])
   except:  # pylint: disable=bare-except
       error = f"{sys.exc_info()[1]}"
       log.error("Unable to start %s beacon, %s", mod, error)
       tag = "salt/beacon/{}/{}/".format(self.opts["id"], mod)
       ret.append({"tag": tag, "error": error, "data": {}, "beacon_name": beacon_name})
   if not error:
       for data in raw:
           ...
           ret.append({"tag": tag, "data": data, "beacon_name": beacon_name})
   ```
   This is exactly where a per-`mod` in-memory record (`last_fired` timestamp + `last_error`) can be written — both the success and exception branches converge here with `mod` and `error` (or `None`) already in scope, and neither `ret`'s shape nor `process()`'s call signature needs to change. A beacon skipped by interval-throttling (`continue` at line 159-160) or config-invalid (`continue` at line 137) or disabled (`continue` at line 110) correctly leaves its record untouched — it did not fire, so its last-known status must not be overwritten.

### Data Flow Analysis
- `Minion.process_beacons()` (`salt/minion.py:726-739`) calls `self.beacons.process(b_conf, self.opts["grains"])` once per `loop_interval`, discarding nothing but the return value today — internal state on `self.beacons` is otherwise unobserved by the caller. A dict attribute on the `Beacon` instance (analogous to the existing `self.interval_map`) is a safe, additive place to accumulate `{mod_name: {"time": <float epoch>, "error": <str|None>}}`.
- **Persistence across `Beacon` recreation is the key risk, and there is a direct precedent for handling it.** `self.beacons` (the `Beacon` instance) is reconstructed, not mutated, in three places:
  - `salt/minion.py:4013` (`beacons_refresh()`) — explicitly preserves `interval_map` across recreation:
    ```python
    prev_interval_map = {}
    if hasattr(self, "beacons") and hasattr(self.beacons, "interval_map"):
        prev_interval_map = self.beacons.interval_map
    if hasattr(self, "beacons"):
        self.beacons.close_beacons()
    self.beacons = salt.beacons.Beacon(self.opts, self.functions, interval_map=prev_interval_map)
    ```
  - `salt/minion.py:4586` and `:4604` (`_setup_core()` / `setup_beacons()`) — both are first-time construction (`if not self.ready` / `if "beacons" not in self.periodic_callbacks`), so there is no prior state to lose; a fresh "never fired" map is correct there.
  - Conclusion: a new constructor kwarg on `Beacon.__init__` (e.g. `status_map=None`, mirroring `interval_map`) plus the identical preserve-and-pass-through treatment in `beacons_refresh()` keeps status data alive across the one code path that recreates the instance mid-lifetime, exactly as `interval_map` already does for interval throttling. No other code path replaces `self.beacons`.

### Manifest Algorithm Analysis
- `salt` cell's `CODEMANIFEST` documents `Minion`'s constructor, `functions`/`returners`/`states` properties, and three methods (`_load_modules`, `sync_connect_master`, `tune_in`). `manage_beacons` and `process_beacons` are **not** documented entities/methods in this manifest — the cell's own annotation states it is scoped to the composition-root responsibility (loading every `LazyLoader` at startup), not full daemon behavior. Adding a dispatch-table entry to `manage_beacons` does not alter any documented signature, property, or algorithm.
- `salt/modules` cell's `CODEMANIFEST` documents exactly 3 representative functions (`__virtual__`, `run`/`cmdmod.py`, `ping`/`test.py`, `get_hash`/`file.py`) "as a representative sample; it is not an exhaustive catalog." `beacons.py` and any function added to it fall outside the documented contract entirely — no algorithm text governs it.
- No cell documents `salt/beacons/__init__.py` at all.
- **Conclusion: no CODEMANIFEST algorithm, signature, or guarantee is affected by this change in any of the three touched files.**

### Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| none | — | — | `codemanifest.usages`/`codemanifest.annotations` absent from `.goga/config.yml`; neither `salt`'s nor `salt/modules`'s `CODEMANIFEST` declares a `Usages` section |

### Rejected Hypotheses
- **"Track status via a log-scraping or on-demand probe cycle."** Rejected — explicit task requirement forbids reading logs or waiting for a new probe cycle; also no existing mechanism reads minion logs from a module function.
- **"Store status in `self.opts['beacons']` config dict directly."** Rejected — `opts["beacons"]` is the beacon *configuration*, round-tripped through `save()`/YAML dump (`beacons.py:425-461`) and diffed in `modify()` (`beacons.py:309-327`); polluting it with runtime status would corrupt config persistence and diffing. A separate in-memory map (mirroring `interval_map`) avoids this entirely.
- **"Recreate `Beacon.process()`'s call signature to accept/return a status dict."** Rejected — unnecessary and would touch the one call site (`Minion.process_beacons`) for no benefit; instance-attribute mutation inside `process()` (like `self.interval_map` mutation already happening in `_process_interval`) is sufficient and keeps the return contract untouched.
- **"Fabricate a default timestamp (e.g. `None`→`0` or epoch) for never-fired beacons."** Rejected — task explicitly requires a clear "never fired" signal, not a stale/made-up value; precedent `schedule.job_status` already models "absent key" as the natural sentinel (`schedule.get(name, {})` returns `{}` for unknown jobs).

### Confirmed Root Cause
Not a bug fix — a net-new capability. Root implementation point: `Beacon.process()` (`salt/beacons/__init__.py:78-218`), specifically the `try/except`/`raw` handling at lines 188-204, is the single place where every per-beacon fire outcome (success or exception) is already determined with `mod` and `error` in scope. Recording `{mod: {"time": time.time(), "error": error}}` there, into a `self.status_map` (or similarly named) dict, satisfies "reflects live activity as it happens" with zero polling and zero log access. Persistence across the one instance-recreation path (`beacons_refresh`) is solved by following the exact `interval_map` precedent already in that method. Exposure to operators follows the exact `schedule.job_status` precedent: a new `func` in `Minion.manage_beacons`'s dispatch table → new `Beacon` method that fires a `/salt/minion/minion_beacons_status_complete` completion event → new `salt/modules/beacons.py` function that fires `manage_beacons` and blocks on that tag, converting any timestamp to a formatted string before returning.

### Confidence Level
**HIGH** — every claim above is backed by a direct code read (line numbers cited) of `salt/beacons/__init__.py`, `salt/minion.py`, `salt/modules/beacons.py`, `salt/utils/schedule.py`, and `salt/modules/schedule.py`, including confirmation of the one instance-recreation path and its existing `interval_map`-preservation precedent, and a structurally identical precedent (`schedule.job_status`) for the exact "per-item on-demand status, explicit absent-case" semantics required here.

### Breaking Change Assessment
1. **Will existing function call with same arguments produce different behavior?** NO — all existing `manage_beacons` dispatch entries, `Beacon` methods, and `beacons.py` functions are unmodified; only new entries/functions are added. `Beacon.process()`'s existing control flow and `ret` construction are untouched; only an additional bookkeeping write is inserted alongside the existing `error`/`raw` handling.
2. **Will existing file paths change?** NO.
3. **Will output format change?** NO — `process()`'s return shape, `list_`/`list_available`'s return shape, and all existing completion-event payloads are unchanged.
4. **Will return value semantics change?** NO.
5. **Will manifest-defined guarantees be altered?** NO — confirmed above; none of the touched functions/methods are documented in any CODEMANIFEST.
6. **Will existing tests break?** NO — change is purely additive (new dict attribute defaulting to `{}`, new optional constructor kwarg defaulting to `None`/mirroring `interval_map`, new dispatch entry, new module function); no existing call site, signature, or return value is altered.

**No breaking change detected.**
