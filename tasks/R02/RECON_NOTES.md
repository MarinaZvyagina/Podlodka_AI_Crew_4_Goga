# R02 (saltstack/salt) — Task Design Recon Notes

Repository: `saltstack/salt`
Pinned commit: `dd3fe66070a465d045efd6120e0f34e47f3672c2`
Method: no local clone (disk-constrained). All evidence gathered via `gh api
repos/saltstack/salt/contents/...?ref=dd3fe66070a465d045efd6120e0f34e47f3672c2` and
`curl -s https://raw.githubusercontent.com/saltstack/salt/dd3fe66070a465d045efd6120e0f34e47f3672c2/<path>`,
pinned to the exact commit SHA throughout. No local disk state left behind (no clone was made).

This file documents the real code read, why each of the four tasks (`task_A.md`..`task_D.md`,
`metadata_A.yaml`..`metadata_D.yaml`) is grounded in it, and an explicit leak check confirming
none of the four task prompts name the underlying mechanism.

---

## 1. Orientation: what's actually in this repo

Read directly (not trusted blindly, cross-checked against real code below):

- `agents/CLAUDE.md` — confirms the dunder-injection convention as a first-class, documented
  Salt idiom: `__opts__`, `__grains__`, `__pillar__`, `__context__` ("Per-run cache (persists
  during Salt execution)"), `__salt__`, `__utils__`, `__states__`; gives the worked example:
  ```python
  if "cache_key" not in __context__:
      __context__["cache_key"] = expensive_operation()  # Only once per run
  ```
  This is the direct grounding for Task D.
- `agents/docs/architecture.md` — confirms the loader-managed plugin categories (execution
  modules, states, runners, wheel, grains, pillar, beacons, engines, returners, renderers,
  matchers, utils) and explicitly documents `salt/loader/` (`LazyLoader`, "Virtual names:
  Modules can override their name via `__virtual__()`", "Dunder injection", "Caching: Modules
  are cached after first load"). Confirms the loader mechanism is real and central, not just a
  hint from the task brief.
- `salt/loader/lazy.py` and `salt/loader/context.py` — read directly. Confirmed `LazyLoader`
  packs dunders (`self.pack`) into loaded modules via `NamedLoaderContext`/`LoaderContext`
  (contextvars-based), and processes `__virtual__` (and any `virtual_funcs`) per module at
  load time (`self._process_virtual(mod, module_name, virtual_func)`). This is the real
  mechanism behind every loader-managed plugin category, confirmed by direct code read, not
  assumed from the task brief's hint.

## 2. Task A — Local Change: `salt/beacons/diskusage.py`

Read the full file (single-purpose, self-contained beacon module, ~120 lines):
`validate(config)` requires a list; `beacon(config)` walks `psutil.disk_partitions()`, matches
each configured mount (supports regex, Windows drive letters via a `re.sub` normalization
step), and appends `{"diskusage": current_usage, "mount": _mount}` to the return list whenever
`current_usage >= monitor_usage`. There is no low-usage/"below threshold" direction today —
only "at or above X%" is supported. Confirmed via `tests/pytests/unit/beacons/test_diskusage.py`
(read in full) that this is exercised with a real, minimal, self-contained pytest suite
(`test_non_list_config`, `test_empty_config`, `test_diskusage_match`, etc.) with no dependency
on other Salt subsystems — ideal for a bounded Local Change task.

Why this is a good Local Change: the entire feature surface (config parsing + evaluation) lives
in one file with zero imports of other loader categories (`salt.utils.beacons`,
`salt.utils.platform`, `psutil`, `re`, `logging` only). A correct solution should not need to
touch `salt/beacons/__init__.py` (the generic `Beacon.process()` orchestrator that calls
`validate`/`beacon` generically by name) or any other file.

## 3. Task B — Cross-module Feature: beacon status across the beacon-management round trip

This required the deepest real-code tracing, across three files, to confirm a genuine ≥3-boundary
data/control flow (not just a plausible-sounding scenario):

1. `salt/beacons/__init__.py`, class `Beacon`: `process(self, config, grains)` is the actual
   per-cycle evaluation loop — for each configured beacon it calls
   `raw = self.beacons[fun_str](b_config[mod])` (the beacon's `.beacon()` function) inside a
   `try/except`, and on error already builds an error-carrying event dict. This is the single,
   real point where "did this beacon fire, did it error" is knowable. The same file also defines
   `list_beacons`, `add_beacon`, `modify_beacon`, `delete_beacon`, `enable_beacon`,
   `disable_beacon`, `validate_beacon`, `reset` as plain methods on `Beacon` — confirmed by
   reading `list_beacons` in full: it fetches state and then
   `salt.utils.event.get_event("minion", opts=self.opts)` → `evt.fire_event({"complete": True,
   "beacons": beacons}, tag="/salt/minion/minion_beacons_list_complete")`. This is the exact
   reply-side of a request/response pattern.
2. `salt/minion.py`, method `manage_beacons(self, tag, data)` (confirmed by reading the method
   body directly, ~line 4149): reads `data["func"]`, looks it up in a local `funcs` dict mapping
   func-name strings to `(method_name_on_self.beacons, kwargs)` pairs (e.g.
   `"list": ("list_beacons", {...})`), then does `getattr(self.beacons, alias)(**params)`. This
   dict is the real dispatch table that must gain one more entry for a new read-only status
   query. `minion.py` also shows the tag-routing: `elif tag.startswith("manage_beacons"):
   _minion.manage_beacons(tag, data)`, confirming `manage_beacons` events reach this method from
   the minion's own event loop.
3. `salt/modules/beacons.py`, function `list_(...)` (read in full): fires
   `__salt__["event.fire"]({"func": "list", ...}, "manage_beacons")`, then blocks on
   `event_bus.get_event(tag="/salt/minion/minion_beacons_list_complete", wait=...)` — the
   request side of the same round trip, run from the execution-module (job) process context.

This confirms a real architectural fact worth grounding Task B's constraints on: execution
modules run as separate job invocations, decoupled from the long-running minion daemon process
that owns the live `Beacon` object — hence the existing event-fire/wait-for-completion-tag
pattern is not incidental, it's how CLI-invoked module code reaches daemon-owned in-memory
state at all. A "just read `self.beacons` directly from the module" approach is not actually
possible across that process boundary in the general (remote-dispatch) case, which is exactly
what makes the naive/parallel-mechanism trap (log-scraping, a new status file, a new thread)
plausible and wrong.

## 4. Task C — Existing Extension Point: `salt/cache/`

Verified candidate #1 — `salt/cache/` (chosen):
- `salt/cache/__init__.py`: `factory(opts, **kwargs)` picks `MemCache` or `Cache`; `Cache.driver
  = opts.get("cache", salt.config.DEFAULT_MASTER_OPTS["cache"])` (default `"localfs"`);
  `Cache.modules` is a cached property returning `salt.loader.cache(self.opts)`; `store`/`fetch`/
  etc. each build `fun = f"{self.driver}.{funcname}"` and call `self.modules[fun](...)`.
- `salt/loader/__init__.py`, function `cache(opts, loaded_base_name=None)` (confirmed by reading
  the function directly): `return LazyLoader(_module_dirs(opts, "cache", "cache"), opts,
  tag="cache", ...)` — i.e. **every** `.py` file under `salt/cache/` is auto-discovered by
  filename via the generic `LazyLoader`/`_module_dirs` mechanism; there is no central registry
  list anywhere that a new backend must be added to.
- `salt/cache/localfs.py` (read in full) and `salt/cache/redis_cache.py`,
  `salt/cache/consul.py` (headers read) confirm the shared function contract:
  `store(bank, key, data, cachedir)`, `fetch(bank, key, cachedir)`, `updated(bank, key,
  cachedir)`, `flush(bank, key=None, cachedir=None)`, `list_(bank, cachedir)` (aliased via
  `__func_alias__ = {"list_": "list"}`), `contains(bank, key, cachedir)`. `consul.py`'s
  docstring explicitly documents `cache: consul` as the config knob operators set — confirming
  this is genuinely how existing backends are selected, not an invented convention.
- Existing directory listing at the pinned commit: `salt/cache/{__init__,consul,etcd3_cache,
  etcd_cache,localfs,localfs_key,mmap_cache,mmap_key,mysql_cache,redis_cache}.py` — 8 real sibling
  backends beyond the default, strong evidence this really is an established "drop a file in,
  it's a new option" convention rather than a one-off.
- Test-suite evidence, which is what makes this task's positive/negative controls unusually
  crisp: `tests/pytests/functional/cache/helpers.py::run_common_cache_tests(subtests, cache)` is
  a single shared conformance-test function, and `tests/pytests/functional/cache/test_localfs.py`
  (read in full) simply builds `salt.cache.factory(opts)` with `opts["cache"] = "localfs"` and
  calls `run_common_cache_tests(subtests, cache)`. Every other backend
  (`test_redis.py`, `test_consul.py`, `test_mysql.py`, `test_etcd.py`, ...) follows the identical
  pattern (confirmed via directory listing). A correct SQLite backend's test should do exactly
  this; a trap implementation, built as a bespoke parallel utility, structurally cannot reuse
  this suite without first being rewired to look like a `salt.cache` backend — making AC4 in
  `metadata_C.yaml` a strong, low-ambiguity differentiator.

Verified alternative candidate #2 — `salt/sdb/` (considered, not chosen): listing shows
`salt/sdb/{__init__,env,yaml}.py`. This is also a loader-discovered plugin category (structured
data backend, referenced via `sdb://` URIs in config/pillar/state files for secret lookups).
Rejected as the primary Task C choice because (a) it requires the task-solver to understand
Salt-specific `sdb://` URI resolution syntax to even pose a well-formed functional requirement,
which risks nudging the agent toward the mechanism by necessity of describing the feature at
all, and (b) it lacks the `salt/cache/`-style shared cross-backend conformance test harness that
makes positive/negative control differentiation for `salt/cache/` unusually clean and
low-subjectivity. `salt/matchers/` and `salt/output/` were also briefly considered (both are real
loader categories per `agents/docs/architecture.md`) but not traced in code depth, since
`salt/cache/` already gave strong, fully-verified evidence.

## 5. Task D — Architecture Trap: `salt/modules/disk.py::usage()`

Read `salt/modules/disk.py` in full down through `usage()`. Confirmed: `usage(args=None)` builds
a `df`-family command based on `__grains__["kernel"]`, calls
`__salt__["cmd.run"](cmd, python_shell=False)`, and parses the output into a dict keyed by mount
point on **every single call** — `grep -n "__context__"` against the file returns no matches
at the pinned commit, i.e. this function does not yet use the per-run cache convention, even
though it is exactly the kind of "expensive, deterministic-within-a-run" operation
`agents/CLAUDE.md` uses as its own worked example for `__context__`. `salt/modules/network.py`
was also checked as a second candidate (also has no `__context__` usage across its ~50 functions)
but `disk.usage()` was chosen as the concrete grounding since its `agents/CLAUDE.md`-documented
"correct" pattern is a closer structural match (single cheap key, single shell-out, simple
existing test file).

The differentiating test design (in `metadata_D.yaml`'s `functional_check_command` and AC3) is
grounded in a second, independently confirmed real fact: `tests/pytests/unit/modules/test_disk.py`
uses `configure_loader_modules` returning `{disk: {}}` (confirmed by reading the fixture and
several test bodies using `patch.dict(disk.__salt__, ...)` / `patch.dict(disk.__grains__, ...)`),
which is Salt's standard per-test dunder-injection fixture (documented generically in
`agents/docs/testing.md`, whose example fixture explicitly sets fresh `__opts__`/`__grains__`
per test). Because the `salt.modules.disk` Python module object is imported once and reused for
the life of the pytest process, while `__context__` (like the other dunders) is reset per test
by this fixture, a plain module-level global cache and a `__context__`-based cache are
**observably different** under a two-test sequence with different mocked `cmd.run` output —
this is what makes AC3 a genuine functional/architectural differentiator rather than a purely
static grep-based one, satisfying the positive/negative-control requirement with an actual
executable distinguishing test, not just code review.

## 6. Leak check (Research.md §22 requirement)

`grep -inE` for internal terms (`loader`, `__virtual__`, `LazyLoader`, `Beacon.process`,
`manage_beacons`, `salt/cache`, `__context__`, `dunder`, `salt/beacons/__init__`, `Cache class`,
`factory()`) against `task_A.md`, `task_B.md`, `task_C.md`, `task_D.md` returns **zero matches**
(ran directly, see command in this recon session). Each task prompt was independently reread
after drafting to confirm it reads as a plain engineering ticket:

- Task A: talks about "beacon" (public/documented Salt feature name) and "alert
  configuration" only; never names `diskusage.py`, `validate()`/`beacon()`, or the
  `Beacon.process()` dispatch convention.
- Task B: talks about "minion", "beacon", "command line" (all user-facing concepts); never
  names `salt/beacons/__init__.py`, `manage_beacons`, event tags, or the
  fire-event/wait-for-reply pattern.
- Task C: talks about "master", "minion data cache", "SQLite", "configuration" (all
  user-facing/observable); never names `salt/cache/`, `factory()`, `salt.loader.cache()`, or the
  backend function contract.
- Task D: talks about "disk usage command", "df", "Salt run" (all user-facing/observable);
  never names `__context__`, dunders, the loader, or module-level globals (the trap pattern
  itself is not named — only its *symptom* is described functionally).

## 7. Honesty notes / things that did not fit as cleanly as hoped

- Task B is the hardest of the four to keep purely "cross-module" rather than drifting toward
  "extension point" flavor, since the event-fire/wait-for-reply pattern it must reuse is itself
  a kind of established convention. It was kept as Task B (not folded into Task C) because the
  correct solution requires genuine understanding of *three separate files' control flow*
  (evaluation loop → dispatch table → CLI surface) rather than "notice a single named-by-file-name
  plugin slot and drop a file into it," which is the defining shape of Task C. This is a
  judgment call, documented here rather than hidden.
- Task C's functional requirement text mentions "Redis, MySQL, and similar" once, by name, to
  motivate *why* an operator would want this (avoiding a separate DB service) — this is
  disclosed as a deliberate choice: it names real third-party systems Salt integrates with
  (observable, documented, public information: `consul.py`'s own docstring says `pip install
  python-consul` etc.), not any internal Salt class/module/pattern name, so it does not violate
  the "don't name the extension point" rule, but it is flagged here for transparency since it is
  the closest any of the four prompts comes to a borderline call.
- Salt's actual test execution requires the `pytest-salt-factories` plugin and various minion/
  master fixtures; the `functional_check_command`s given assume a working `pip install -e .`
  dev environment per `repos.yaml`'s `build_command` — they were not actually executed in this
  recon session (no local clone/install was performed, per the disk constraint), so exact pytest
  invocation flags may need minor adjustment at Phase 4/5 (validator implementation) time, but the
  target files, fixtures, and existing test patterns they build on were all read directly from
  real source, not guessed.
