# R02-TD-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: False
Cost: $1.5044226
Duration: 237175ms, turns: 40

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (performance optimization / caching) — additive behavior, no existing contract altered.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| salt/modules | `salt/modules/disk.py` | `usage()` gains a per-run cache lookup/store against `__context__["disk.usage"]`, keyed by the normalized `flags` string |
| salt/modules (tests) | `tests/pytests/unit/modules/test_disk.py` | New test(s) exercising the real `usage()` body (not mocked) to verify cache-hit/cache-miss/no-cross-run-leak behavior |

No other cell is modified. No CODEMANIFEST is modified (see Specification Impact).

## Root Cause Analysis
`usage()` unconditionally shells out to `df` via `__salt__["cmd.run"]` on every call, with no memoization, even when called repeatedly with identical `args` in the same job. The codebase already has a proven idiom for exactly this class of problem: `salt/modules/mount.py:55-57` caches `__salt__['disk.blkid']()` in the loader-injected `__context__` dict, which is confirmed (by trace through `Minion._thread_return` → `gen_modules()` → `salt.loader.minion_mods()`) to be rebuilt fresh on every single job/run. Applying the same idiom to `usage()`, extended to be keyed by `args` (since `disk.blkid()` takes no variable input but `usage()` does), satisfies the requirement with no new invalidation machinery.

## Trace Summary
- `salt/states/disk.py:218` → `__salt__["disk.usage"]()` — single call per state invocation, unaffected by caching.
- `Minion._thread_return` (`salt/minion.py:2879`, and `SMinion`/`SProxyMinion` variant `salt/minion.py:6182`) → `gen_modules()` → `salt.loader.minion_mods(..., context=None)` → fresh `context = {}` — confirms `__context__` lifetime = one job/run, never carried to the next job or process.
- No other in-tree call site exists.

## Change Strategy
1. In `usage()`, immediately after computing `flags = _clean_flags(args, "disk.usage")` (existing line), look up a cache bucket: `usage_cache = __context__.setdefault("disk.usage", {})`.
2. If `flags` is already a key in `usage_cache`, return `usage_cache[flags]` immediately — skips the `/etc/mtab` check, `cmd.run`, and parsing entirely.
3. On a cache miss, let the existing logic run unmodified up to each of its two current exit points:
   - The early `return {}` (missing `/etc/mtab` on Linux) → store `{}` into `usage_cache[flags]` before returning it.
   - The final `return ret` → store `ret` into `usage_cache[flags]` before returning it.
4. Use `flags` (the already-deterministic, hashable, canonicalized string produced by `_clean_flags`) as the cache key rather than raw `args`, since `args` may be `None`, a string, or a list/tuple and lists are unhashable.
5. No change to `_clean_flags`, error handling, parsing logic, or the function signature `usage(args=None)`.

## Specification Impact
None. `disk.py` is confirmed absent from `salt/modules/CODEMANIFEST`'s curated sample (grep-verified, no matches), so `usage()` carries no documented contract to update. `__context__` is already documented in the manifest header as a standard loader-injected dunder available to every file in the cell — this change is a normal application of an already-documented convention, not a new architectural surface. No CODEMANIFEST edit is required or appropriate.

## Usage Impact
None. No `.usages/*.md` file documents `disk.py` or `usage()`; none require updates.

## Compatibility Verification
**Backward compatible.** Same `args` on the first call in a run: identical behavior (real `df` execution, identical parsing, identical return value/shape). Same `args` on a later call in the *same* run: same return value, retrieved without a redundant `df` call (the explicitly requested change, not a semantic break). Different, independent runs: `__context__` is proven fresh per job, so no cross-run staleness is possible. Existing tests (`test_usage_dict`, `test_usage_none`) mock `disk.usage` wholesale and don't touch `__context__`, so they are unaffected.

One minor, non-breaking side effect: if `/etc/mtab` is transiently missing, the `log.error` calls on that path will now fire only once per distinct `flags` value per run instead of on every call within that run (since the cached `{}` short-circuits before reaching the log calls on subsequent hits). The returned value (`{}`) is identical either way, so this is a log-volume reduction, not a behavior change to the contract.

## Test Strategy
Add new tests to `tests/pytests/unit/modules/test_disk.py` that call the real `disk.usage()` (unlike the existing mocked tests) via `patch.dict(disk.__salt__, {"cmd.run": mock})` and `patch.dict(disk.__grains__, {"kernel": "Linux"})`, with `disk.__context__` cleared/fresh per test (consistent with `configure_loader_modules` already returning `{disk: {}}`):
1. **Cache hit**: call `disk.usage()` twice with the same `args` (e.g. both `None`); assert the mocked `cmd.run` was called exactly once and both calls return equal, correctly-parsed dicts.
2. **Cache miss on different args**: call `disk.usage(args=None)` then `disk.usage(args="h")` (or another allowed flag); assert `cmd.run` was called twice (once per distinct `flags` key).
3. **No cross-run leakage**: simulate a new run by resetting `disk.__context__` to `{}` between two calls with identical `args`; assert `cmd.run` is called again (cache does not survive a context reset), confirming the "must not go stale between separate runs" requirement.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cache key collision between distinct `args` inputs that normalize to the same `flags` string (e.g. `"h"` vs `["h"]`) | Low | Low — this is *correct*, not a bug: `_clean_flags` already treats them as equivalent, so identical `df` behavior is expected and desired | None needed; this is the intended normalization `_clean_flags` already provides |
| `__context__` not actually reset in some untraced execution path (e.g. custom/older orchestration wrapper), causing stale data within what the caller considers a "new run" | Low | Medium | Mitigated by the direct trace evidence (`gen_modules()` called unconditionally per job in both `_thread_return` implementations) and by mirroring the exact same trusted mechanism `mount.py` already relies on for `disk.blkid()`; not a new risk introduced by this change |
| Reduced repeated error-log verbosity on the missing-`/etc/mtab` path (noted above) | Low | Low | Acceptable per Compatibility Verification — return value unchanged; document in PR description if requested |
| Existing tests broken by refactor | Very Low | Medium | Existing tests mock `usage()` entirely and don't exercise `__context__`; verified unaffected in Investigation Report Breaking Change Assessment |

---

Do you approve the plan? Proceed to implementation?
