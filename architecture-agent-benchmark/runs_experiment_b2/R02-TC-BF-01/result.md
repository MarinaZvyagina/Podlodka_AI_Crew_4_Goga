# R02-TC-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $2.3482787999999992
Duration: 369078ms, turns: 70

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — additive, opt-in new cache backend driver.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `salt/cache` | `sqlite3_cache.py` (new), `CODEMANIFEST` (add entry) | New driver module + new `Cache::Sqlite3Backend()` manifest entry |

Non-cell repository artifacts touched in the same pass (docs/changelog/tests — outside the Goga cell forest but required for acceptance):
- `doc/ref/cache/all/salt.cache.sqlite3_cache.rst` (new)
- `doc/ref/cache/all/index.rst` (add one line)
- `doc/ref/configuration/master.rst` (add one bullet)
- `changelog/<n>.added.md` (new)
- `tests/pytests/unit/cache/test_sqlite3_cache.py` (new)
- `tests/pytests/functional/cache/test_sqlite3.py` (new)

## Root Cause Analysis
Not a defect — greenfield addition. Investigation confirmed the `Cache` facade dispatches to driver modules purely by `f"{self.driver}.<method>"` against a `LazyLoader` that globs `salt/cache/*.py`, with `self.kwargs` defaulting to `{}` for any driver lacking `init_kwargs` (the pattern already used by `mysql_cache.py`/`consul.py`/`etcd_cache.py`). No loader or config-schema change is required; `VALID_OPTS["cache"]` is a bare `str` type check with no enum.

## Trace Summary
`Cache.store/fetch/updated/flush/list/contains` → `self.modules[f"{self.driver}.<method>"](..., **self.kwargs)` → `LazyLoader(tag="cache")` resolves `sqlite3.<method>` to `sqlite3_cache.py`'s function via `__virtualname__ = "sqlite3"`. `Cache.store`'s `TypeError` fallback and `Cache.fetch`'s envelope-unwrap require no driver-side support. `Cache.clean_expired` falls back generically via `list`/`fetch`/`flush` since the driver won't define `clean_expired`.

## Change Strategy
1. **Implement `salt/cache/sqlite3_cache.py`** first (the concretization must exist before the manifest documents it, and before tests/docs reference it).
   - Module docstring explaining purpose, `cache: sqlite3` selection, `sqlite3.database`/`sqlite3.timeout` opts, versionadded marker.
   - `__virtualname__ = "sqlite3"`, `__func_alias__ = {"list_": "list"}`.
   - `_get_conn()`: lazily open+cache a `sqlite3.connect()` in `__context__`, `PRAGMA journal_mode=WAL`, `PRAGMA synchronous=NORMAL`, `CREATE TABLE IF NOT EXISTS cache(bank TEXT NOT NULL, cache_key TEXT NOT NULL, data BLOB NOT NULL, last_update INTEGER NOT NULL, PRIMARY KEY(bank, cache_key))`, creating the parent directory of the db path if missing.
   - `store/fetch/updated/flush/list_/contains`: same shape as `mysql_cache.py`'s functions, using `salt.payload.dumps/loads` for the `data` blob, wrapping `sqlite3.Error` into `SaltCacheError`.
2. **Update `salt/cache/CODEMANIFEST`**: add `"Cache::Sqlite3Backend()"` entry directly after `Cache::LocalFSBackend()`, `location: sqlite3_cache.py`, `store(bank, key, data)` / `fetch(bank, key) -> data:object` / `flush(bank, key, ...)` methods — no `cachedir` parameter, annotation stating it persists to a single on-disk SQLite file whose path is derived from `cachedir` by default.
3. **Docs**: add the automodule stub + index entry + one `cache` option bullet.
4. **Changelog**: one new `.added.md` fragment.
5. **Tests**: unit test hitting the driver module functions directly against a `tmp_path` db file (store/fetch/updated/flush/list/contains, `SaltCacheError` path, default-path derivation from `cachedir`, override via `sqlite3.database`); functional test reusing `run_common_cache_tests` plus an explicit "close driver `__context__` connection, open a fresh one, data is still there" persistence test.
6. Run `goga lint`, then run the new + adjacent existing cache tests.

## Specification Impact
`salt/cache/CODEMANIFEST` body gains exactly one new mutation entry, `"Cache::Sqlite3Backend()"`, modeled identically in style to the existing `"Cache::LocalFSBackend()"` entry (same annotation structure: purpose + per-method one-liners), differing only in omitting the `cachedir` parameter (matching the driver's actual signature, per investigation). No existing entry (`Cache`, `Cache::MemCache`, `Cache::LocalFSBackend`) is altered. Header `Imports`/`Annotations`/`Usages` are unchanged — no new cross-cell dependency is introduced (the module uses only stdlib `sqlite3` plus `salt.payload`/`salt.syspaths`, neither of which is a modeled type in this or any other cell).

## Usage Impact
None. `salt/cache/CODEMANIFEST` declares `usages: []` and no `.usages/` directory exists for this cell; nothing to reconcile.

## Compatibility Verification
**Backward compatible.** No existing file, function, signature, or default config value changes. The new driver is reachable only when an operator explicitly sets `cache: sqlite3`; every other configuration (the default `cache: localfs` and all other existing driver values) is byte-for-byte unaffected. This matches the Investigation Report's Breaking Change Assessment (all NO).

## Test Strategy
- **Unit** (`tests/pytests/unit/cache/test_sqlite3_cache.py`): call driver functions directly against a `tmp_path`-scoped db file with `configure_loader_modules` supplying `__opts__`/`__context__`; cover round-trip store/fetch, overwrite, missing key/bank, `updated()` int/None, `flush` with/without key, `list_`, `contains`, default db path = `<cachedir>/cache.sqlite3`, override via `sqlite3.database`, and a forced-error path (e.g. malformed table) raising `SaltCacheError`. This is the layer that proves the stdlib-only, no-mocking claim.
- **Functional** (`tests/pytests/functional/cache/test_sqlite3.py`): `cache` fixture via `salt.cache.factory({"cache": "sqlite3", ...})`, `run_common_cache_tests(subtests, cache)` for behavioral parity with `localfs`/`mysql`/`redis`, plus a dedicated `test_data_survives_restart` that stores through one `Cache` instance, drops the driver's cached `__context__` connection (simulating process exit), constructs a brand-new `Cache` instance, and asserts the previously stored data is still fetchable — this is the direct proof of the task's core durability requirement.
- Existing tests are unmodified and must continue to pass unchanged (regression guard for "deployments that don't opt in are unaffected").

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| SQLite file locking/concurrency issues under concurrent master worker processes | Medium | Medium (perf/contention, not correctness) | WAL journal mode + configurable busy-timeout (`sqlite3.timeout`, default 5s) so concurrent writers block-and-retry instead of failing; acceptable for the stated single-node use case, documented as such |
| `sqlite3` unavailable in a minimal/embedded Python build | Low | Low | `__virtual__()` returns `False` with a clear message if `import sqlite3` fails, exactly like `mysql_cache.py`'s `HAS_*` guard pattern — driver simply won't load, no crash |
| Column name `key` colliding with SQL keyword | Low (avoided by design) | Low | Column named `cache_key`, mirroring `mysql_cache.py`'s `etcd_key` naming choice for the same reason |
| Manifest drift if a future method (e.g. `list_all`) is added to the driver without updating CODEMANIFEST | Low | Low | Plan intentionally limits driver scope to the methods documented for `LocalFSBackend`/`mysql_cache`-style drivers only (no `list_all`), keeping manifest and code in lockstep |

---

Do you approve this plan? Proceed to implementation?
