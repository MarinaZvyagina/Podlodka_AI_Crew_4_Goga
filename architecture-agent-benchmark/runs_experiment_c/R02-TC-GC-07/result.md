# R02-TC-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r02-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.4573031
Duration: 230924ms, turns: 37

## Agent's own summary

# Investigation Report

## Task Summary
Add a new SQLite-backed cache driver module to `salt/cache` that persists bank/key/data to a single on-disk file via Python's stdlib `sqlite3`, selectable through the existing generic `cache` master-config option, so operators avoid running Redis/MySQL/etcd just for durable minion-data caching on small single-node masters. Must be purely additive.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `salt/cache` | Owns the `Cache` facade and every driver module; new driver is a sibling of `localfs.py`/`mysql_cache.py`/`etcd_cache.py` | High |
| `salt/loader` (read-only reference) | Generic dynamic module discovery that will load the new driver without modification | Reference only |
| `salt/config` (read-only reference) | Confirmed no enum/validation restricts `cache` to a fixed set of driver names | Reference only |

## Tracing Summary
- `Cache.__init__` (`salt/cache/__init__.py:62-74`) reads `opts.get("cache", DEFAULT_MASTER_OPTS["cache"])` → `self.driver`; `DEFAULT_MASTER_OPTS["cache"]` = `"localfs"` (`salt/config/__init__.py:1429`, also 1846/2048/2078 for other opt dicts) — a plain string default, not an enum.
- `Cache.modules` (`__init__.py:76-78`) lazily builds `salt.loader.cache(self.opts)` → a `LazyLoader` that scans `salt/cache/*.py` for functions and indexes them as `"<modname_or_virtualname>.<funcname>"`. No per-driver registration list exists anywhere — dropping a new file in `salt/cache/` with the right function names makes `f"{driver}.store"` etc. resolvable automatically. Confirmed via `salt/loader` schema (generic `cache` factory, same mechanism used by `salt/modules`, `salt/states`, etc.).
- `Cache.kwargs` (`__init__.py:80-85`) calls `self.modules[f"{self.driver}.init_kwargs"](self._kwargs)` if present, else `{}`. `init_kwargs` is optional — used by `localfs.py:37`, `localfs_key.py:59`, `mmap_key.py:85`, `mmap_cache.py:126`, `redis_cache.py:203`, `etcd3_cache.py:172`. **`mysql_cache.py` and `etcd_cache.py` do NOT implement `init_kwargs`** — they read all config directly from `__opts__` inside their own `_init_client()`. This is the pattern to follow for sqlite3 (no `cachedir` kwarg threading needed unless we want the default db path to live under `cachedir`, in which case reading `__opts__["cachedir"]` directly, like `localfs.py:31-34`, works without `init_kwargs`).
- `Cache.store` (`__init__.py:131-169`): calls `self.modules[f"{driver}.store"](bank, key, data, expires=expires, **self.kwargs)`; if the driver's `store` doesn't accept `expires` (raises `TypeError`), it falls back to wrapping `data` in `{"data": ..., "_expires": ts}` and calling `store` again without `expires`. **Conclusion: the sqlite3 driver's `store(bank, key, data, **kwargs)` signature must NOT declare a `expires` parameter** (mirroring `mysql_cache.store(bank, key, data)` at `mysql_cache.py:267`) so the facade's fallback wrapping activates — native TTL support is out of scope and undesired, since no other driver implements it either.
- `Cache.fetch`/`updated`/`flush`/`list`/`contains` (`__init__.py:171-322`) dispatch identically to `f"{driver}.<name>"` with `**self.kwargs`; `list` dispatches to `f"{driver}.list"`, which is why every driver defines `__func_alias__ = {"<internal_name>": "list"}` (`localfs.py:28`, `mysql_cache.py:98` aliases `ls`, `etcd_cache.py:91` aliases `ls`) since `list` is a Python builtin and can't be a plain function name in the module without shadowing it awkwardly — but `localfs.py` uses `list_` as the actual name aliased to `list`. Either convention (`list_` or `ls`) works; `list_` matches the task's request literally.
- `Cache.list_all`/`clean_expired` (`__init__.py:269-297`, `324-366`) check `if fun in self.modules` before calling — **fully optional**. Grep confirms `list_all` exists only in `localfs_key.py:370`, `mmap_key.py:309`, `mmap_cache.py:284` — **not** in `mysql_cache.py`, `etcd_cache.py`, `redis_cache.py`, or `consul.py`, i.e. the "fuller" relational/KV drivers deliberately omit it and rely on the facade fallback. Same for `clean_expired` — no driver implements it natively; the facade fallback (`__init__.py:342-366`) uses `list`/`fetch`/`flush` against the `_expires` envelope. **Correction to original scope-resolution assumption: `list_all`/`clean_expired`/`get_storage_id` are NOT required for parity — the closest-shape reference drivers (mysql, etcd) omit all three.**

## Data Flow Analysis
`bank`/`key` strings + a Python object (`data`) flow from `Cache.store` → driver `store(bank, key, data, **kwargs)`. Every existing DB-backed driver serializes `data` via `salt.payload.dumps`/`.loads` (msgpack) before writing the blob (`mysql_cache.py:272`, `etcd_cache.py:147`) and deserializes symmetrically on `fetch`. The sqlite3 driver must do the same — write `salt.payload.dumps(data)` into a BLOB column, read back with `salt.payload.loads`. `updated()` must return an epoch **int** (`mysql_cache.py` uses `UNIX_TIMESTAMP(last_update)`; `etcd_cache.py` stores a separate `.tstamp` key); sqlite3 can store an epoch integer column set via `int(time.time())` on every `INSERT OR REPLACE`, avoiding SQLite's less convenient native datetime functions.

## Manifest Algorithm Analysis
The `salt/cache` CODEMANIFEST models the driver relationship via **mutation notation**: `"Cache::LocalFSBackend()"` (CODEMANIFEST:82-97), explicitly because "the driver is a plain module of same-named functions dynamically dispatched through a LazyLoader, not a Python subclass of Cache" (CODEMANIFEST:9-14, Annotations). Per goga-cookbook's mutation-usage rule ("the agent needs to understand the type relationship to select the correct implementation strategy") and the cell's own established precedent, the new driver must be documented the same way: a new mutation-notation entry, e.g. `"Cache::SQLite3Backend()"`, with `location: sqlite3_cache.py`, listing `store`/`fetch`/`updated`/`flush`/`list_`/`contains` methods analogous to the `LocalFSBackend` entry's `store`/`fetch`/`flush`. No existing CODEMANIFEST algorithm text needs to change — `Cache`/`MemCache` entries stay untouched since their dispatch behavior is generic and driver-agnostic.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| *(none exist)* | `salt/cache` | N/A | `usages: []` in schema; no cell-level `.usages/*.md` currently exists for `salt/cache`, so there is nothing to reconcile. A new practice file is optional/additive only, not a reconciliation of an existing one. |

## Rejected Hypotheses
- **"list_all/clean_expired/get_storage_id are mandatory for parity with 'fuller' drivers."** Rejected — grep evidence shows the two closest analogs by storage shape (mysql_cache.py, etcd_cache.py) implement neither; only the in-process/mmap-family drivers do. Implementing them would be unrequested scope creep beyond what "same free-function contract" requires, and goga-change's "minimize scope" invariant argues against it. `list_all` and `clean_expired` will be skipped (Cache facade already has working generic fallbacks for both).
- **"The db-path config key should follow `sqlite3.file` matching `mysql.host`-style flat namespacing."** Considered but no rejection needed — this matches the established per-driver `<drivername>.<option>` convention (`mysql.*`, `etcd.*`) exactly, e.g. `sqlite3.driver_file` (or similar) plus `sqlite3.table_name`, confirmed as the naming convention every existing full-featured driver uses.
- **"`__virtual__()` is required even for a stdlib-only driver."** Rejected as a hard requirement — `localfs.py` (stdlib-only, `os`/`shutil`/`tempfile`) defines **no** `__virtual__()` at all, proving its absence means "always available," which is exactly the desired behavior for a driver with a zero-dependency stdlib backend (`sqlite3` ships with a standard Python install). `__virtual__` will be omitted, matching `localfs.py`'s precedent rather than `mysql_cache.py`'s import-gated pattern (which exists there only because `MySQLdb`/`pymysql` are optional third-party imports).
- **"Adding a new driver requires touching salt/loader or salt/config."** Rejected — confirmed generic, filename-based discovery with no registration list, and no enum/validation on the `cache` config value.

## Confirmed Root Cause
Not a bug investigation — this is a net-new capability. Root finding: the `Cache` facade's dispatch contract is fully satisfied by a plain module exposing `store(bank, key, data, **kwargs)`, `fetch(bank, key, **kwargs) -> data`, `updated(bank, key, **kwargs) -> int|None`, `flush(bank, key=None, **kwargs)`, `list_(bank, **kwargs) -> list[str]` (aliased to `list` via `__func_alias__`), and `contains(bank, key, **kwargs) -> bool`, reading its own config from `__opts__` (module-injected global) and caching its connection in `__context__` (also module-injected, per-process global) exactly like `mysql_cache.py`. No facade or loader code needs to change; the entire change is additive within `salt/cache/` plus its manifest/tests.

## Confidence Level
**HIGH** — every claim above is backed by direct file:line evidence from `salt/cache/__init__.py`, `salt/cache/localfs.py`, `salt/cache/mysql_cache.py`, `salt/cache/etcd_cache.py`, `salt/config/__init__.py`, existing test files, and the CODEMANIFEST. No ambiguity remains that blocks planning; the only open design choices (exact driver name `sqlite3` vs `sqlite`, exact config-key names, default db filename) are implementation-detail decisions, not risk-bearing unknowns, and will be fixed by the Planning step.

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — no existing driver module, `Cache`, or `MemCache` code is modified; only a new file is added.
2. Will existing file paths change? **NO** — no files are moved or renamed.
3. Will output format change? **NO** — existing drivers' serialization/return formats are untouched.
4. Will return value semantics change? **NO** — the new driver only introduces new return paths under a config value (`cache: sqlite3`) nobody currently sets by default (`DEFAULT_MASTER_OPTS["cache"] == "localfs"` unchanged).
5. Will manifest-defined guarantees be altered? **NO** — `Cache`/`MemCache`/`LocalFSBackend` CODEMANIFEST entries are unchanged; only a new type entry is appended.
6. Will existing tests break? **NO** — no existing test file is modified in a way that changes assertions; `test_cache_backends.py`'s parametrized `backend` fixture may gain a new `"sqlite3"` param (additive parametrization, existing `localfs`/`mmap_cache` params and assertions unchanged).

**No breaking change detected. Safe to proceed to Planning.**
