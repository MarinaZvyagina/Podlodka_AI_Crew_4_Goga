# R02-TD-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: False
Cost: $1.3633035
Duration: 213051ms, turns: 49

## Agent's own summary

# Change Plan

## Task Classification
Extension (performance optimization — adding intra-run memoization to an existing execution-module function; no new feature surface, no behavior change for callers).

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `salt/modules` | `salt/modules/disk.py` | `usage()` gains a `__context__`-backed cache check/store wrapped around its existing `cmd.run` + parse logic |
| `tests` (not a Goga cell — standard test tree) | `tests/pytests/unit/modules/test_disk.py` | Add unit test(s) asserting `cmd.run` is invoked once across two identical-argument calls and again for differing arguments |

## Root Cause Analysis
`usage()` unconditionally calls `__salt__["cmd.run"](cmd, ...)` on every invocation (disk.py:117), with no memoization, so any caller that checks disk space more than once per run (e.g. before/after a large file operation) pays a repeated `df` subprocess + parse cost even when nothing changed. Investigation confirmed HIGH confidence and no breaking change; the established in-repo pattern for this exact problem shape is `__context__` dict caching, already used in `salt/modules/mount.py:55-57` for `disk.blkid`, and safe here because `__context__` is freshly created per job by the loader/minion chain (`salt/loader/lazy.py:340-341`, `salt/minion.py:2021-2022`).

## Trace Summary
`usage(args)` → `_clean_flags(args, "disk.usage")` → `flags` string → (early-return `{}` if `/etc/mtab` missing on Linux, uncached) → build `cmd` → `__salt__["cmd.run"](cmd, python_shell=False)` → parse loop → `ret` dict → return. The cache check/store will sit between `flags` computation and the `cmd.run` call, and after `ret` is fully built, respectively — the parse loop itself is untouched.

## Change Strategy
1. In `salt/modules/disk.py:usage()`, immediately after `flags = _clean_flags(args, "disk.usage")` (line 96), compute `cache_key = f"disk.usage.{flags}"`.
2. Insert a cache check right after the existing `/etc/mtab`-missing early-return block (so the error branch is never cached, per plan): `if cache_key in __context__: return __context__[cache_key]`.
3. Leave the `cmd`-building, `cmd.run`, and parsing loop exactly as-is.
4. Immediately before the final `return ret` (line 160), add `__context__[cache_key] = ret`.
5. No other functions in `disk.py` (`inodeusage`, `percent`, etc.) are touched — scope stays minimal, matching only what the task requested.

## Specification Impact
None. `salt/modules/CODEMANIFEST` does not document `disk.py`/`usage()` in its representative sample (only `cmdmod.py`, `test.py`, `file.py`); the manifest's global annotation already lists `__context__` as a standard available dunder, so no CODEMANIFEST edit is required or triggered by this change.

## Usage Impact
None. No `.goga/usages/` or cell-level `salt/modules/.usages/` file references `disk.py` or `disk.usage`; no usage recipe exists to update.

## Compatibility Verification
**Backward compatible.** Signature (`usage(args=None)`) and return type/shape are unchanged. First call per unique `flags` value within a run behaves identically to today (shells out, parses, returns `ret`). Subsequent identical-argument calls within the same run return the previously computed `ret` object instead of re-shelling — same data, since nothing in the requirements implies disk usage must be re-measured within one run (the task explicitly asks for this memoization). Cross-run staleness is prevented by `__context__`'s per-job-fresh lifetime, already verified in the Investigation Report. No STOP condition triggered.

## Test Strategy
Add to `tests/pytests/unit/modules/test_disk.py`:
- **`test_usage_context_cache`**: with `__grains__` set to `Linux` and `__context__` set to `{}` (via `configure_loader_modules` or `patch.dict(disk.__context__, {}, clear=True)`), mock `cmd.run` to return a fixed `df -P` sample output, call `disk.usage()` twice with the same `args`, assert the returned dicts are equal on both calls, and assert `cmd.run` was called exactly once (`mock.call_count == 1` or `assert_called_once`).
- **`test_usage_context_cache_distinguishes_args`**: call `disk.usage(args=None)` then `disk.usage(args=["h"])`, assert `cmd.run` is called twice (once per distinct `flags` value), confirming the cache key correctly separates different argument sets.
- Existing `test_usage_dict`/`test_usage_none` are unaffected (they mock `disk.usage` itself wholesale, never exercising the real cache logic) and need no changes.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A caller within a single run expects `disk.usage()` to reflect disk changes made moments earlier in the same run (e.g. a state writes a large file then immediately checks `disk.usage` with identical `args`) | Low | Medium — stale reading within the run | This is precisely the tradeoff the task explicitly requests ("check space before... do the work... check again... return quickly"); acceptable and intentional per requirements. If a caller needs a forced-fresh read, that's a separate future enhancement (e.g. a `refresh` kwarg), out of current scope. |
| `__context__` unexpectedly not fresh per run in some execution mode (e.g. `salt-ssh`, `salt-call --local` invoked in a loop by external tooling) | Low | Medium — cross-run staleness | Verified via trace: every module-loading path (`_load_modules`) creates a new `{}` when `context` is `None`; `salt-call`/`salt-ssh` each spin up their own process/loader per invocation, so `__context__` cannot outlive one process's single job |
| Test additions inadvertently couple to internal cache-key string format | Low | Low | Tests assert on `cmd.run` call count and returned data equality, not on the literal cache-key string, keeping the key format an implementation detail |

**Do you approve the plan? Proceed to implementation?**
