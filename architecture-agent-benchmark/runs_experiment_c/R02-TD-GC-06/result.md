# R02-TD-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r02-v1
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: False
Cost: $1.1132402999999997
Duration: 152082ms, turns: 37

## Agent's own summary

# Scope Resolution Report

## Task Summary
Make `disk.usage()` in `salt/modules/disk.py` cache its parsed `df` output for the remainder of the current Salt run, keyed by the `args` it was called with, so repeated calls with identical `args` avoid re-shelling to `df`. The cache must not persist across independent Salt runs. The function's signature (`usage(args=None)`) and return shape (dict keyed by mount point/filesystem) must be preserved. The codebase already has an established convention for this (`__context__`-based run-scoped caching, e.g. `pkg.list_pkgs`, `user.getent`, `winrepo.data`), which is documented in `salt/modules/CODEMANIFEST` and should be followed for consistency.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `salt/modules` | Owns `disk.py` and its CODEMANIFEST contract entry for `usage()` — the direct target of the change | High |
| `salt/loader` | Provides `LazyLoader`/`NamedLoaderContext`, the mechanism that supplies and scopes the `__context__` dunder to a single run | Medium (reference only) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `salt/loader` | `__context__` is injected by `LazyLoader` and its lifetime is what makes the cache run-scoped and non-stale across independent runs. No code change needed here — behavior already exists and is exercised as-is by `disk.usage`. Included only as supporting fact for the Investigation step, not as a modification target. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `salt/utils/decorators` (has `memoize`) | A generic memoization decorator exists there, but it is not run-scoped (persists for process lifetime) and is not the established convention this task explicitly asks to follow (`__context__`); using it would deviate from the codebase's own precedent and risks the cross-run staleness the task forbids. |
| Any other `salt/modules/*.py` file | No behavioral participation — task is scoped to the single `usage()` routine in `disk.py`; `inodeusage`/`percent` in the same file also call `df` but are out of scope since the task only names `usage()`. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared in `salt/modules/CODEMANIFEST` header (no `Usages:` section applicable to this entry) | `disk.usage`'s CODEMANIFEST entry carries only an inline `annotations:` block, no named practice/usage file is referenced or needs to be created — the caching convention is precedent (seen in sibling annotations like `pkg.list_pkgs`), not a formal Usage. |

## Semantic Participation Summary
Only `salt/modules` (specifically `disk.py` and its `CODEMANIFEST` entry for `usage`) participates behaviorally in this change: it is the sole place where the shell-out happens and where the caching logic must be added. `salt/loader` participates only as background fact — its `__context__` dunder is what bounds cache lifetime to one run — but requires no modification since this behavior already exists and is already relied upon by other modules in the same cell.

## Final Investigation Scope
- `salt/modules` cell:
  - `salt/modules/disk.py` — `usage()` function (implementation change)
  - `salt/modules/CODEMANIFEST` — `"usage(args: str | None) -> volumes:dict"` entry located at `disk.py` (contract update)
  - Reference-only, for precedent confirmation: existing `__context__`-cached entries in the same manifest (e.g. `pkg.list_pkgs`, `user.getent`, `winrepo.data`)

## Scope Risks
- **Under-scoping risk**: none identified — `inodeusage`/`percent` also shell out to `df` but are explicitly not named in the task; leaving them untouched is correct, not a gap.
- **Over-scoping risk**: could be tempted to also "fix" `inodeusage`/`percent` for consistency — must resist, since the task and Breaking Change Policy require minimal, targeted scope; touching unrelated routines would violate "minimize scope" and "never modify unrelated cells/usages."
- **Convention risk**: must confirm exact `__context__` key-naming pattern used by sibling entries (e.g. `pkg.list_pkgs` uses `__context__["pkg.list_pkgs"]`) during Investigation, to keep naming idiomatic and collision-free across different `args` values.

## Notes
- `salt/modules` per the schema depends only on `salt/loader` (`LazyLoader`, `NamedLoaderContext`) — confirming `__context__` is the only cross-cutting mechanism available and appropriate here; no new `Imports` are required in `CODEMANIFEST` since `__context__` is a dunder injected by the loader into every module's namespace, not a type consumed via explicit import.
- No `.goga/config.yml` `codemanifest.usages`/`codemanifest.annotations` base practices exist for this project, so no global convention file needs to be consulted beyond what's already visible in the manifest itself.
