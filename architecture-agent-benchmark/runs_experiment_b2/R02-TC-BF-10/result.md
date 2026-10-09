# R02-TC-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.9790505
Duration: 298681ms, turns: 52

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new pluggable cache backend driver (`sqlite3`) to the `salt/cache` cell: a same-shape concretization of `Cache` (like `Cache::LocalFSBackend`) that persists bank/key/data/timestamp rows in a single on-disk SQLite file via Python's stdlib `sqlite3` module, selectable via the existing `cache` master config option, with no change to default (`localfs`) behavior. Includes a CODEMANIFEST update, tests, docs, and a changelog fragment.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| salt/cache | Direct target — new backend driver module + CODEMANIFEST mutation entry | High |
| salt/loader | `Cache.modules` dispatches to the new driver through `salt.loader.cache` (`LazyLoader`, tag `"cache"`); no code change needed, but dispatch mechanism is load-bearing context | Medium (context only) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| salt/loader | The `LazyLoader` returned by `salt.loader.cache(opts)` is what makes `opts["cache"] = "sqlite3"` resolve to `salt/cache/sqlite3_cache.py` at runtime — the new driver's functions must match the naming/aliasing conventions (`__func_alias__`, module-level functions) this loader expects, exactly as `LocalFSBackend` already does. No modification to `salt/loader` itself is required. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| salt/utils | Foundational grab-bag helpers (e.g. `salt.utils.files`, `salt.utils.path`) may be referenced for parity but no behavioral change or manifest involvement in that cell |
| salt/modules | No execution-module participation in cache backend selection |
| salt/states | No behavioral relevance to a cache driver addition |
| salt/grains | Grains are a *consumer* of the cache (data gets stored under bank `grains`), but the grains cell itself has no code change and no manifest involvement |
| salt/runners | `salt/runners/cache.py` (`cache.migrate`) consumes cache drivers generically via the same `Cache` facade; no runner-specific change is in scope, and it isn't documented as its own cell in schema (it's the runners cell generically) |
| salt/returners | Unrelated cache subsystem (job-returner storage), no manifest/behavioral overlap |
| salt (root) | `Master`/`MWorker` composition root instantiates `Cache` via existing factory path; no change needed there since driver selection is purely config-driven (`opts["cache"]`) |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared in salt/cache CODEMANIFEST currently (`usages: []`) | The cell has no `.usages/` consumer file yet; this task does not require adding one — `Cache`'s facade contract (store/fetch/flush/list/contains) is unchanged for consumers. The new driver is an internal concretization, invisible to `Cache` API consumers except via the `cache` config value. |

## Semantic Participation Summary
Only `salt/cache` participates behaviorally: it gains a new dynamically-dispatched backend module (`sqlite3_cache.py`) alongside `localfs.py`, `mysql_cache.py`, `redis_cache.py`, `consul.py`, `etcd_cache.py`, `etcd3_cache.py`. The `Cache`/`MemCache` facade classes in `__init__.py` require zero changes — they already dispatch generically via `self.driver` + `self.modules[f"{self.driver}.<fn>"]`. `salt/loader` is relevant only as fixed, unmodified infrastructure that the new module must conform to (function-naming conventions), not as a cell requiring its own change.

## Final Investigation Scope
- salt/cache (primary and only cell requiring CODEMANIFEST/implementation changes)

## Scope Risks
- **Under-scoping risk**: none significant — the `Cache` facade's dispatch contract is stable and does not require touching `salt/loader` or `salt/master.py`/`salt/daemons/masterapi.py` composition-root wiring, since driver selection is already a runtime config lookup (`opts["cache"]`), not a static registration list.
- **Over-scoping risk**: pulling in `salt/loader` for edits would be incorrect — it is unmodified; any temptation to "register" the new driver there must be resisted, since `LazyLoader` auto-discovers all modules under `salt/cache/`.

## Notes
Tests, docs, and the changelog fragment live outside the Goga cell forest (`tests/`, `doc/`, `changelog/` are not modeled as cells) and are handled as standard repository housekeeping alongside the cell-scoped implementation change, not as manifest-governed artifacts.
