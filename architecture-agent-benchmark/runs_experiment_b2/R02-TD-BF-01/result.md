# R02-TD-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: False
Cost: $1.5053454000000004
Duration: 283616ms, turns: 47

## Agent's own summary

# Change Plan

## Task Classification
**Type:** Enhancement (performance) — non-breaking behavioral addition to an existing, undocumented (in CODEMANIFEST) execution-module function.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| salt/modules | `salt/modules/disk.py` | `usage()` gains a `__context__`-backed cache keyed by resolved `df` flags; cache is only populated on a successful parse, and checked before doing any work |
| salt/modules | `tests/pytests/unit/modules/test_disk.py` | New/extended unit test asserting `cmd.run` is invoked once across two identical-args calls, and again for a differently-flagged call |

No `salt/loader` files are modified — it is relied upon only for the existing `__context__` injection.

## Root Cause Analysis
`usage()` unconditionally shells out to `df` and re-parses its output on every invocation, even when called repeatedly with identical arguments within the same loader/run lifetime. `__context__` is a dict injected fresh into every execution module by `salt.loader.minion_mods`/`salt.minion._load_modules`, recreated at process start and at each module-refresh cycle — never persisted to disk — and the codebase already uses it for exactly this "avoid re-shelling within a run" purpose in `salt/modules/mount.py:55-57` (`__context__["disk.blkid"]`).

## Trace Summary
`usage(args=None)` → `_clean_flags(args, "disk.usage")` → build `df` command string per `__grains__["kernel"]` → `__salt__["cmd.run"](cmd, python_shell=False)` → line-by-line parse into `ret` → `return ret`. The cache intercepts at the very top (before `_clean_flags` even runs, since flags validation is cheap but running `df` and parsing is the expensive part) and again just before the final successful `return ret`.

## Change Strategy
1. At the top of `usage()`, compute the cache key from `args` (reuse `_clean_flags` output, since that's what actually determines the `df` invocation) — call `_clean_flags` first (cheap, also preserves existing `CommandExecutionError` validation behavior on invalid flags on every call), then check `__context__.get(("disk.usage", flags))`; if present, return a copy of the cached dict immediately.
2. Leave the existing command-building, `cmd.run` invocation, and line-parsing logic untouched.
3. Leave the two early/failure paths untouched and **uncached**:
   - the `/etc/mtab` missing branch (`return {}`) — a transient host misconfiguration, not something to freeze into the cache for the rest of the run
   - the `except IndexError` branch that resets `ret = {}` — a parse failure should not poison subsequent calls in the same run
4. Only store into `__context__` right before the final `return ret`, and only do so with the successfully parsed, non-exceptional `ret`.
5. Return a shallow copy of the cached dict on a hit (not the live cached object) so that a caller mutating the returned dict cannot corrupt the cache for subsequent callers in the same run — matches the "existing return format must not change" requirement (callers already receive a plain dict either way).

## Specification Impact
None. `disk.py`/`usage()` is not one of the 3 documented representative files in `salt/modules/CODEMANIFEST`; no manifest entry exists to update. The cell's header Annotations already document `__context__` as available to every module — this change is a concrete application of that already-stated convention, not a change to it.

## Usage Impact
None. No `.usages/*.md` practice file exists for `salt/modules` or references `disk.py`; no usage file needs updating.

## Compatibility Verification
**Backward compatible.** Signature (`usage(args=None)`), return type/shape (`dict` keyed by mountpoint with the same fields), and both error paths are unchanged. The only observable behavior addition is that repeated calls with identical resolved flags within the same run/loader lifetime skip re-executing `df` — the explicit goal of the task, not a regression. Invalid-flag validation (`CommandExecutionError` from `_clean_flags`) still runs on every call since flags are cleaned before the cache check.

## Test Strategy
Add to `tests/pytests/unit/modules/test_disk.py`:
- `test_usage_caches_df_call`: patch `disk.__grains__` to `{"kernel": "Linux"}`, patch `disk.__context__` to a real `{}` (or rely on `configure_loader_modules`'s injected `__context__`), mock `__salt__["cmd.run"]` to return a canned `df -P` output, call `disk.usage()` twice with the same `args`, assert `cmd.run` was called exactly once and both calls return equal (but not the identical object) dicts.
- `test_usage_cache_keyed_by_args`: with the same setup, call `disk.usage()` then `disk.usage(args=["h"])`, assert `cmd.run` was called twice (once per distinct flag set), proving the cache differentiates by resolved flags.
- Keep existing `test_usage_dict`/`test_usage_none` as-is — they mock `disk.usage` wholesale and remain valid regardless of internal caching.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Caller mutates the returned dict, corrupting the cached value for later callers in the same run | Medium (dicts are mutable and `ret` is returned directly today) | Medium — later same-run callers would see corrupted disk data | Return a shallow copy (`dict(cached)`, with fresh per-mountpoint dict copies) on cache hits, not the stored reference |
| A state relies on `disk.usage()` reflecting disk changes made *within* the same run (e.g., check-before/do-work/check-after) | Low–Medium — inherent tradeoff explicitly requested by the task | Low — task explicitly asks for this caching; existing `mount.py` precedent accepts the same tradeoff for `blkid` | None needed beyond documenting the tradeoff in a code comment; task explicitly authorizes this behavior |
| Caching an error/empty result poisons the rest of the run | Low | Medium | Only cache on the successful final `return ret` path, never on the `/etc/mtab`-missing or `IndexError` branches |
| Test flakiness from relying on real `__context__` fixture wiring | Low | Low | Use the existing `configure_loader_modules` fixture pattern already present in the test file, consistent with other tests in the same file |

Do you approve the plan? Proceed to implementation?
