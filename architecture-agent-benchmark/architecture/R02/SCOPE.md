# SCOPE.md — R02 (saltstack/salt)

## Method

Scope was decided from salt's own module layout — directories at depth ≤ 3 under `salt/` (per
`TREATMENT_DESIGN.md` §4) — verified by directly reading source files (`salt/loader/lazy.py`,
`salt/loader/__init__.py`, `salt/loader/context.py`, `salt/loader/dunder.py`, representative
files in each plugin-category directory, `salt/minion.py`, `salt/master.py`) and by `grep`-ing
for real usage patterns (`__salt__[...]` delegation from state modules, `salt.loader.*` calls
from the daemon classes) to confirm which directories are genuinely load-bearing rather than
merely present. This was done **before** reading `tasks/R02/task_A.md`–`task_D.md` (see
`PLAUSIBILITY_CHECK.md` for the post-hoc self-check, performed only after this scoping and
authoring work was complete).

The candidate list from prior reconnaissance (`salt/loader`, `salt/modules`, `salt/states`,
`salt/runners`, `salt/grains`, `salt/beacons`, `salt/engines`, `salt/returners`, `salt/cache`,
`salt/utils`, `salt/minion.py`/`salt/master.py`) was verified against `ls salt/` (47 top-level
entries) and file counts (`modules`: 267, `states`: 133, `utils`: 173, `runners`: 31, `beacons`:
20, `grains`: 13, `returners`: 11, `cache`: 10, `engines`: 6). Salt's real architectural spine is
`salt/loader` — a single dynamic-loading mechanism (`LazyLoader`, `__virtual__` convention,
`NamedLoaderContext` dunder proxies) that ~25 differently-tagged plugin-category directories are
all built on. Given the "roughly 6–10 cells, representative selection, prioritizing load-bearing
over thin" budget, 8 of those ~25 categories were chosen (the loader mechanism itself, plus 7 of
its categories) rather than all 25, and `beacons`/`engines` (the two thinnest, least
widely-depended-upon categories among the candidates) were deprioritized in favor of covering the
mechanism itself in depth.

## Cells covered (9) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `salt/loader` | The actual architectural spine: `LazyLoader` (`salt/loader/lazy.py`) and its factory routines (`salt/loader/__init__.py`: `minion_mods`, `states`, `runner`, `returners`, `grains`, `utils`, `cache`, plus ~18 more not documented here — `beacons`, `engines`, `wheels`, `outputters`, `serializers`, `auth`, `fileserver`, `roster`, `thorium`, `render`, `sdb`, `pkgdb`/`pkgfiles`, `clouds`, `netapi`, `executors`, `tops`, `queues`, `matchers`, `proxy`) are called by every other cell in this forest, directly or via `salt.loader.*`. Nothing in the codebase imports a plugin file by dotted Python path — this mechanism is how all ~25 categories actually get discovered and gated (`__virtual__`). |
| `salt/modules` | 267 files — the largest single plugin category and the one every state, runner, and the minion daemon itself calls through (`__salt__['<module>.<func>']`). Confirmed via `salt/states/pkg.py`, `salt/states/file.py` calling `__salt__['pkg.install']`/`__salt__['file.get_managed']` etc., and via `Minion.functions` in `salt/minion.py`. |
| `salt/states` | 133 files — the declarative layer built directly on `salt/modules` via dynamic `__salt__` dispatch; every state function follows one shared return-shape convention (`name`/`changes`/`result`/`comment`) enforced by the state compiler, not by any one state module. |
| `salt/runners` | 31 files — the master-side counterpart to `salt/modules`; confirmed via `runners/jobs.py`/`runners/manage.py` reading master-side job-cache/key-store state and never referencing minion-only dunders like `__grains__`. |
| `salt/returners` | 11 files — the job-result persistence category; `local_cache.py` doubles as Salt's own default job cache (`get_jid`/`get_jids`/`save_load`), used regardless of whether an external returner is also configured. |
| `salt/cache` | 10 files — a stable `Cache`/`MemCache` facade (`salt/cache/__init__.py`) over a dynamically-dispatched backend driver (`salt/cache/localfs.py`), a clean, small illustration of the loader's "concretization via dynamic dispatch, not inheritance" pattern (modeled with DSL mutation notation). |
| `salt/grains` | 13 files — the minion-side host-fact collector that runs *before* `__salt__`/`__proxy__` exist, confirmed via `salt.loader.grains()`'s docstring and the fact that grain functions only receive `__opts__`/`__grains__` (previously computed), never `__salt__`. |
| `salt/utils` | 173 files — real, honestly documented as a flat organic grab-bag (not a cohesive API); included specifically because the task brief calls out this repository's "flat `salt/modules/`... `salt/utils/` sprawl" as its defining organic-modularity characteristic, and because a curated sample of it (`dictupdate.update`, `data.decode`/`compare_dicts`, `platform.is_windows`, `args.clean_kwargs`, `files.fopen`) is imported directly by nearly every other cell in this forest. |
| `salt` (root: `minion.py`/`master.py` only) | The composition root: `Minion`/`SMinion` (`salt/minion.py`) and `Master`/`MWorker` (`salt/master.py`) are the daemon classes that actually call every `salt/loader` factory routine at process startup and hold the resulting `LazyLoader` instances for the process's lifetime. Scoped deliberately to these two files, not the whole `salt/` directory (every subdirectory documented above has its own cell). |

## Deliberately excluded / deprioritized

- **`salt/beacons`** (20 files) and **`salt/engines`** (6 files) — real, genuine loader-managed
  plugin categories (both are documented, generically, as members of the ~25-category list inside
  `salt/loader`'s own Annotations, alongside `wheels`, `outputters`, `renderers`, `roster`, `sdb`,
  and others — a plain factual statement that these categories exist, with no per-category detail
  for any of them), but **no dedicated cell was authored for either one, and neither one's
  internals, specific files, or conventions are documented anywhere in this forest.** They were
  the two thinnest, least-central candidates from the original reconnaissance list relative to the
  8 cells actually documented (`beacons` has no other cell depending on it the way `modules` does;
  `engines` at 6 files is the smallest category in the codebase), so within the "roughly 6-10
  cells" budget, depth on the loading mechanism itself (`salt/loader`) and its two largest/most
  load-bearing categories (`modules`, `states`) was prioritized over adding two more
  thin-category cells.
- **`salt/cli`, `salt/client`, `salt/config`, `salt/transport`, `salt/crypt.py`, `salt/pillar`,
  `salt/fileserver`, `salt/renderers`, `salt/roster`, `salt/wheel.py`, `salt/auth`, `salt/netapi`,
  `salt/cloud`** and other top-level directories — real subsystems, but each is either a thinner
  consumer of the loader mechanism (already illustrated by the 7 categories documented) or a
  separate concern (CLI argument parsing, config-file loading, transport/crypto plumbing) that is
  not itself part of the loader-managed extension-point spine this forest focuses on.
- **`salt/master.py`'s `AESFuncs`/`AuthFuncs`/`ClearFuncs`/`RequestRouter`/`RequestServer`/
  `Maintenance`/`FileserverUpdate`/`EventMonitor`/`SMaster`** — real classes in the same file as
  the documented `Master`/`MWorker`, but internal transport/auth/process-management machinery
  rather than composition-root code that constructs loader-managed `LazyLoader` instances; left
  undocumented to keep the root `salt` cell focused on its stated purpose (the composition root
  that wires the loader-managed categories together), per the cookbook's "describable in one
  phrase without 'and'" granularity guidance.

This scoping was performed and frozen before `tasks/R02/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
