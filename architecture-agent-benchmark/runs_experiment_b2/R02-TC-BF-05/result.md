# R02-TC-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.4149524000000002
Duration: 209816ms, turns: 37

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new `sqlite3` minion-data-cache backend driver to Salt's `salt/cache` plugin category, so operators who set `cache: sqlite3` in the master config get a durable, single-file SQLite-backed cache (grains, mine data, job returns) that survives a master restart, built entirely on the Python stdlib `sqlite3` module. It must plug into the existing dynamically-dispatched backend-driver mechanism (the same one `localfs` and `mysql_cache` use) without touching the mechanism itself, and must leave `cache: localfs` (default) deployments byte-for-byte unaffected.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `salt/cache` | New backend driver module is added directly inside this cell; `Cache` facade dispatch and the `LocalFSBackend` mutation pattern this new driver must mirror are both defined here | High |
| `salt/loader` | Supplies the `LazyLoader`/`salt.loader.cache` mechanism that discovers and dispatches to any `.py` file dropped in `salt/cache/`, including the new driver | Medium (dependency only, already wired) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `salt/loader` | `Cache.modules` (in `salt/cache/__init__.py`) is a `LazyLoader` built by `salt.loader.cache(opts)`, tag `"cache"`, which scans `salt/cache/*.py` for functions and namespaces them by `__virtualname__`. The new driver is picked up automatically once the file exists — no change to `salt/loader` itself is required. Its contract (function-name dispatch, `__virtualname__` convention) constrains how the new module must be written. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `salt` (root: `Minion`/`Master`/`MWorker`/`SMinion`) | Backend selection is entirely config-driven (`opts["cache"]`) through the existing `Cache.__init__`/`factory`; the composition root never references backend modules by name. No change needed. |
| `salt/utils` | No helper in the curated sample is used differently by this change; `salt.payload`/`salt.utils.path`, used by `localfs.py`, are called the same way any other cache driver would call them — infrastructural-only, not modeled behavior. |
| `salt/states`, `salt/grains`, `salt/runners`, `salt/returners`, `salt/modules` | No data flow or manifest participation — these consume the `Cache` facade only through `__salt__`/opts plumbing already stable; none reference cache backend modules directly. Speculative to include. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| *(none declared)* | `salt/cache` CODEMANIFEST has an empty `usages: []` and no project-level `codemanifest.usages`/`codemanifest.annotations` are configured (`goga config codemanifest.usages` → "Option not found"). No practice files to connect. |

## Semantic Participation Summary
Only `salt/cache` carries real behavioral change: it gains one new type — a `Cache::SQLite3Backend` mutation, structurally the same concretization-without-inheritance relationship the manifest already documents for `Cache::LocalFSBackend` — implemented as a same-shape driver module (`store`/`fetch`/`flush`/`list`/`contains`/`updated`) dispatched through `Cache.modules`. `salt/loader` participates only as the pre-existing, unmodified discovery mechanism that makes the new file reachable; it requires no code or contract change. All other cells in the modeled forest are behaviorally inert with respect to this task.

Non-cell artifacts (docs under `doc/`, tests under `tests/`, changelog fragment under `changelog/`) sit outside the goga cell forest entirely (not present in `goga schema` output) — they are implementation/documentation deliverables handled directly, not subject to CODEMANIFEST/`.usages` reconciliation.

## Final Investigation Scope
- `salt/cache` (primary — new driver module + possible CODEMANIFEST annotation)
- `salt/loader` (read-only investigation — confirm dispatch/discovery contract is satisfied, no modification expected)

## Scope Risks
- **Under-scoping risk:** if the new driver needed a new *shared* mechanism (e.g., a new loader tag or a new `Cache` facade method), `salt/loader` or `salt/cache`'s `Cache` class would need real changes — investigation must explicitly confirm the existing `store/fetch/flush/list/contains/updated` + `__virtualname__` contract is sufficient (it is, per `mysql_cache.py` precedent) before ruling out deeper changes.
- **Over-scoping risk:** being tempted to add manifest entries for *all* undocumented backends (`mysql`, `redis`, `consul`, `etcd`) for "consistency" — out of scope; the manifest explicitly documents only a representative sample (`LocalFSBackend`), and those four backends were added without manifest entries, establishing precedent that new backends don't require one either.

## Notes
- The manifest-vs-precedent tension (should `SQLite3Backend` get a CODEMANIFEST mutation entry like `LocalFSBackend`, or stay undocumented like `mysql`/`redis`/`consul`/`etcd`?) is a planning decision, not a scoping one — flagged for the Planning step (Step 3) to resolve explicitly rather than defaulting silently either way.
- Config default (`opts["cache"] = "localfs"` in `salt/config/__init__.py`, outside the modeled forest) is unaffected — the new driver is opt-in only via explicit `cache: sqlite3`.
