# PLAUSIBILITY_CHECK.md — R02 (saltstack/salt)

## When this check was performed

`tasks/R02/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 9 CODEMANIFEST files were authored, materialized, linted
(`goga lint`: 0 errors), schema-verified (`goga schema`), and drift-checked (`goga contract` on 4
cells) — per the assignment's explicit ordering requirement. No content in the architecture
forest was revised in response to reading the tasks (see "Outcome" below).

## The four task prompts (quoted)

- **Task A**: add a "usage dropped below expected" alert to the disk-usage beacon, alongside its
  existing "usage rose above threshold" alert, so both can be configured for the same or
  different mounts, without breaking operators' existing high-usage alert configuration — this
  is meant to catch a filesystem that silently failed to mount (looking like near-zero usage on
  what's actually the root filesystem) rather than a genuine cleanup.
- **Task B**: add a way to ask a minion, live (not via log-reading, not requiring a new probe
  cycle or a restart), when each of its configured beacons last actually fired and whether that
  last firing errored — clearly distinguishing "never fired yet" from a stale/fabricated value.
- **Task C**: add a SQLite-file-backed option for the master's cached data (grains snapshots,
  mine data, job returns), selectable through normal master configuration, using only the Python
  standard library, that survives a master restart — without changing behavior for deployments
  that don't opt in.
- **Task D**: make repeated same-argument calls to the command that reports disk usage (which
  currently shells out to `df` every time) return quickly within a single Salt run, without
  serving stale data across separate runs, and without changing the command's return format or
  call signature.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 9 CODEMANIFEST files for the task-specific terms each prompt turns on: `beacon`,
`disk usage`/`disk_usage`, `sqlite`, `mount point`, `threshold`, `last fired`/`last_fired`,
`durable`, `persistent`, `df utility`, `redis`, `mysql`, `percentage`. Exactly **one** match
across the entire forest: the bare word "beacons" in `salt/loader/CODEMANIFEST`'s global
Annotations, in a plain enumeration of the ~25 loader-managed plugin category names ("execution
modules, states, runners, returners, grains, `beacons`, engines, cache, wheels, outputters,
renderers, roster, sdb, and more") — a real, generic architectural fact (this category exists and
is loader-managed) with zero detail about what any specific beacon does, no mention of the
disk-usage beacon, thresholds, alerting, or firing status. No dedicated `salt/beacons` cell was
authored at all (see `SCOPE.md`'s "Deliberately excluded" section — `beacons`/`engines` were the
two thinnest candidates left out of the 9-cell budget). The forest never says anything shaped like
"add an alert here" or "cache this command's output" — every annotation describes what a real,
already-existing class/function does today, in the codebase's own vocabulary (e.g. `LazyLoader`,
`__virtual__`, `NamedLoaderContext`, `Cache.modules`, `local_cache.py`'s `get_jid`/`get_jids`),
consistent with `TREATMENT_DESIGN.md` §4's required phrasing style.

## Where genuine overlap exists, and why it's expected rather than leakage

One of the four tasks (C) touches functionality that lives inside a cell this forest documents in
some detail — this is unavoidable and, per the treatment design, *intended*: a real architecture
doc-set should make a repository's existing extension points discoverable, and RQ7/RQ9 of the
benchmark specifically ask whether the Goga treatment changes existing-extension-point usage and
how the effect varies by task type. Providing accurate, task-agnostic documentation of a real
extension point is not the same as hinting at a specific task built on top of it:

- **Task C ↔ `salt/cache`**: this is the one closest overlap. Task C asks for a new,
  config-selectable SQLite backend for the master's cache; the `salt/cache` cell's Annotations
  say exactly: "actual storage operations are delegated to a dynamically-dispatched backend
  driver module, selected by the `cache` config option (default `localfs`) and loaded on demand
  via `salt.loader.cache`... modeled here with the DSL's mutation notation
  (`Cache::LocalFSBackend`) because it is a real concretization-without-inheritance pattern: the
  driver is a plain module of same-named functions dynamically dispatched through a `LazyLoader`,
  not a Python subclass of `Cache`." This describes the *mechanism* (how `Cache`/`MemCache`/the
  backend-driver pattern work, using only real, pre-existing names and the real default driver)
  without ever mentioning SQLite, durability across restarts, or "no third-party dependencies" —
  those are Task C's specific requirements, not anything this cell states or implies. An agent
  still has to recognize that "a config-selectable persistent cache backend" *is* this driver
  pattern and work out that a new backend needs `store`/`fetch`/`updated`/`flush`/`list_`/
  `contains` module-level functions matching `localfs.py`'s shape — the forest doesn't spell that
  recipe out the way R01's protections-extension-point description did (it deliberately stops at
  "a driver module is a concretization... dispatched dynamically," without an explicit "subclass
  X, implement Y, register Z" step-by-step). Judgment call: kept as-is, since documenting this
  real extension point at the mechanism level is precisely what the Goga condition is meant to
  test, not a giveaway of Task C's specific answer.
- **Task A/B ↔ `salt/loader`'s generic mention of `beacons`**: covered above — a bare category
  name with zero mechanism detail (no `Beacon` interface, no per-beacon convention, no firing/
  error-tracking concept documented anywhere), so there is nothing here for an agent to discover
  beyond "a `beacons` plugin category exists," which does not meaningfully advantage either task.
- **Task D ↔ `salt/modules`**: no overlap found. The forest documents `cmdmod.run`/`__virtual__`/
  `test.ping`/`file.get_hash` from `salt/modules` — none of which is the disk-usage-reporting
  command Task D targets, and no caching/memoization behavior is mentioned anywhere in the forest
  for any execution module.

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task C / `salt/cache`) was judged to be the expected, in-scope operation of
documenting a real, load-bearing extension point at the mechanism level — not task-specific hint
content — and is disclosed here explicitly rather than papered over, per `TREATMENT_DESIGN.md`
§4's "independent plausibility check" requirement. Tasks A and B, which both concern the
`salt/beacons` category, are essentially unassisted by this forest: no `salt/beacons` cell exists,
and the one passing mention of the category name carries no mechanism detail at all.
