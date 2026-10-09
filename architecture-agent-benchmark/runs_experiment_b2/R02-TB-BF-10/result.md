# R02-TB-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.7788497
Duration: 210724ms, turns: 48

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a live, in-memory way to query a Salt minion for per-beacon execution health: for each currently configured beacon, when it last actually ran and whether that run raised an error. The answer must reflect real-time state — no waiting for a new probe cycle, no log parsing, no minion restart, no config changes — and must explicitly distinguish "never fired" from a real (possibly error-free) run.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `salt/beacons` (undocumented) | Owns `Beacon.process()`, the only place a beacon actually executes; must record last-run/error state here | High |
| `salt` (root, documented) | `Minion.manage_beacons()` is the event-driven dispatch table that routes a request from the execution-module layer to a `Beacon` method; `Minion.beacons_refresh()` is the precedent for carrying in-memory per-beacon state across `Beacon` object recreation | High |
| `salt/modules` (documented) | `salt/modules/beacons.py` is the user-facing execution-module surface (`beacons.list`, `beacons.list_available`, etc.) — the natural place for a new `beacons.status` entry point, following the exact `list_()` request/response pattern | High |
| `salt/loader` | Loads beacon plugin modules (`salt.loader.beacons`) that `Beacon.__init__` consumes | Low |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `salt/beacons` | Source of truth for "did this beacon run, and did it error" — the new status dict is written exactly where `process()` invokes a beacon's `.beacon()` function |
| `salt` | Owns the live `Minion.beacons` instance and the event-tag dispatch (`manage_beacons`) that a CLI-facing module call must go through to reach it; owns `beacons_refresh()`, which must not silently discard status history |
| `salt/modules` | Owns the public `beacons.*` execution-module namespace a user actually calls from `salt-call`/`salt` CLI |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `salt/loader` | Only supplies the `LazyLoader` of beacon plugin callables; no behavioral participation in tracking execution status — pure infrastructural pass-through already used unmodified by `Beacon.__init__` |
| `salt/utils` | `salt/utils/beacons.py` (list/dict config helpers) and `salt/utils/minion.py` (`running()`, on-disk proc-file based) are structurally adjacent but not applicable: the task explicitly rules out a file-based model, and no config-shape helper is needed for a status dict keyed by beacon name |
| `salt/cache`, `salt/states`, `salt/grains`, `salt/runners`, `salt/returners` | No data flow or behavioral participation in beacon execution or status reporting |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared | `.goga/config.yml` has no `codemanifest.usages`/`codemanifest.annotations`, and none of the three candidate cells (`salt`, `salt/modules`, and the undocumented `salt/beacons`) declare cell-level `.usages/` practices relevant to beacon status tracking. No practice file needs to be read or written for this change. |

## Semantic Participation Summary
Three cells participate, forming one straight-line data path: `salt/beacons` (`Beacon.process`) is where execution truth is generated and must be recorded; `salt` (`Minion.manage_beacons`, `Minion.beacons_refresh`) is the transport/lifecycle layer that routes the query event to the `Beacon` instance and must preserve status history across in-memory `Beacon` recreation; `salt/modules` (`salt/modules/beacons.py`) is the CLI-facing contract the operator actually invokes, following the established `list_()` fire-event/block-on-reply idiom. All three are necessary; none is sufficient alone — omitting `salt` would leave no way to route the request from CLI to the live `Beacon` object, and omitting `salt/modules` would leave no operator-facing entry point.

## Final Investigation Scope
- `salt/beacons/__init__.py` (`Beacon.__init__`, `Beacon.process`, and the `list_beacons`/`list_available_beacons` sibling methods as the pattern to mirror)
- `salt/minion.py` (`Minion.manage_beacons`, `Minion.beacons_refresh`)
- `salt/modules/beacons.py` (`list_`, `list_available` as the pattern to mirror)
- `tests/pytests/unit/test_beacons.py` (existing `Beacon.process()` test conventions)

## Scope Risks
- **Under-scoping risk**: if `beacons_refresh()` is missed, a routine pillar/config refresh (common in production) would silently wipe all beacon execution history, contradicting "reflect real beacon activity as it happens" — this is the single highest-risk omission and is included above specifically to avoid it.
- **Over-scoping risk**: pulling in `salt/utils/minion.py`'s `running()`/proc-file model would violate the explicit "not require reading log files" / live-only constraint; it is excluded deliberately even though it is the closest existing "check on a running job" precedent named in the task.
- Because `salt/beacons` is not a documented Goga cell and the touched methods in `salt` / `salt/modules` fall outside their cells' curated documented subsets, no CODEMANIFEST/.usages reconciliation is expected to be required — this must still be re-confirmed at Drift Analysis (Step 9), not assumed final here.

## Notes
- `goga schema` and `goga lint` were both run against the unmodified tree prior to this report; lint reports 0 errors across all 9 cells, establishing a clean baseline to diff against after implementation.
- The task's own "check on a running job" analogy (`saltutil.running`) was evaluated and excluded from scope as a *model* to copy (it's file-based), while still being useful context for why `list_beacons`'s in-memory event-bus pattern is the correct one to follow instead.
