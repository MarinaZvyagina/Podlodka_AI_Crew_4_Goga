# CYCLE_FIXES.md — R02 (saltstack/salt) Condition C

`goga lint .` passes clean across all 14 cells (`cells: 14 errors: 0`) — no formal Goga `Imports:`
cycle exists anywhere in the DSL model. A separate, real Python-import-graph analysis (described
below) was also run, since `goga lint` only validates that *declared* imports resolve correctly;
it does not check for undeclared cross-cell dependencies or detect cycles in the real source
graph. That analysis found a large, genuine strongly-connected component, disclosed here rather
than hidden.

## Method: AST-based Python import graph, not grep

All 662 real `.py` files tracked across the 14 cells (9 originally-documented cells + 5 nested
`salt/utils/*` subdirectory cells created per the R05-established `location:`-rule precedent —
`openstack`, `validate`, `decorators`, `dockermod`, `pkg`) were parsed with Python's own `ast`
module. Every `import`/`from...import` statement was resolved to its owning cell via longest-prefix
match against the 14 cell paths, with one deliberate exclusion: the root `salt` cell is scoped to
exactly `minion.py` + `master.py` (per the original Phase 8 SCOPE.md), not the entire `salt.*`
namespace — so `import salt.exceptions`, `salt.config`, `salt.client`, etc. (296, 27, 15 sites
respectively, and dozens of other genuinely out-of-scope top-level modules) were correctly excluded
as out-of-cell dependencies, not counted as edges. The resulting cell-to-cell edge graph was run
through a standard DFS cycle detector (white/gray/black coloring).

## Finding: an 11-cell strongly-connected component

`{salt, salt/loader, salt/utils, salt/utils/decorators, salt/utils/validate, salt/utils/pkg,
salt/modules, salt/grains, salt/runners, salt/returners, salt/cache}` are all mutually reachable.
Only `salt/states`, `salt/utils/dockermod`, and `salt/utils/openstack` sit outside the cycle (pure
consumers with no real inbound edges from the cells they depend on).

Two distinct kinds of edges drive this, both structurally genuine rather than accidental:

1. **`salt/loader` as a dynamic-plugin-loading hub.** `salt/loader.py`'s job is to discover and
   instantiate every plugin category (`modules`, `states`, `runners`, `returners`, `grains`), so it
   inherently touches all of them (`loader → modules`, 1 site — a special-cased dispatch path).
   Conversely, files across `modules`/`utils`/`cache` reference loader-injected context types
   (`LazyLoader`, `NamedLoaderContext` — confirmed earlier this session by direct reading of
   `salt/loader/lazy.py`'s `__salt__`/`__utils__` dispatch-dict construction) or import loader
   helpers directly (`modules → loader`, 11 sites; `utils → loader`, 13 sites; `runners → loader`,
   4 sites). This is an intentional dependency-injection-container shape, not a layering violation
   — it is how Salt's plugin system has worked for 15+ years.

2. **`salt/utils` and `salt/utils/decorators`/`salt/utils/validate` as a shared, bidirectionally-used
   toolbox.** The overwhelming majority of edges run *into* `salt/utils` (`modules → utils`, 810
   sites; `states → utils`, 154; `runners → utils`, 50; `returners → utils`, 26; `grains → utils`,
   33) — the expected direction for a shared-helpers package. But `salt/utils` itself imports back
   from a handful of higher-level cells for narrow, specific reasons (`utils → modules`, 11 sites —
   e.g. a utility function shelling out via `cmdmod`; `utils → cache`, 4; `utils → grains`, 1), and
   its own nested subdirectory cells are mutually dependent on their parent (`utils →
   utils/decorators`, 15 sites, `utils/decorators → utils`, 7; `utils → utils/validate`, 2,
   `utils/validate → utils`, 1) — the same parent/child mutual-helper-borrowing shape already seen
   and disclosed in this study for `firefox-ios/BrowserKit/AddressToolbar` ↔ `LocationView` and
   `freqtrade`'s `common` ↔ `math`-like cells, just recurring at every level of this particular
   subtree.

## Resolution: matches the pattern established in every prior repo, at larger scale

Goga's formal per-cell `Imports:` declarations are deliberately narrower than a full transitive
closure of real `import` statements — they declare the specific *named types* a cell's own
signatures/annotations actually reference (e.g. `salt/modules` declares `LazyLoader` +
`NamedLoaderContext` because those literal type names appear in its own Annotations text; `salt/
grains` declares `fopen` + `is_windows` because its own routine bodies call them directly), not
every file that happens to `import salt.utils.foo` at the top of a source file. `goga lint`
validates that declared imports resolve to something real (`import_type_exists`,
`import_has_valid_from_path`) — it does not require every real Python import to be formally
declared, and does not itself detect cycles. Consistent with R01 (`common` ↔ `math`), R05 (clean
DAG, no cycles found), and R09 (`WebEngine` ↔ `WKWebview`, `Coordinators` ↔ its children,
`AddressToolbar` ↔ `LocationView`): the structurally-heavier, type-bearing direction of each
relationship is what's formally declared (already lint-clean, 0 errors project-wide); the reverse
and lower-traffic real-code edges are disclosed here in prose rather than silently omitted. No
formal two-cell `Imports:` cycle was created in the DSL — the SCC exists only in the real source
graph, which is expected for a 15-year-old dynamic-plugin-loader architecture and not something a
cell-boundary/documentation restructuring can or should collapse into a clean DAG without changing
Salt's actual runtime loading design (out of scope for Condition C).

## Two real facade gaps found and fixed during this cross-check

The whole-project `goga lint .` run that surfaced the SCC investigation also caught two genuine
omissions in `salt/utils/CODEMANIFEST`: `fopen` (`salt/utils/files.py`) and `is_windows`
(`salt/utils/platform.py`) are both imported by name from `salt/grains/CODEMANIFEST`'s own
declared `Imports:` block, but neither had a corresponding routine declaration in
`salt/utils/CODEMANIFEST` — an actual gap left by the full-completeness expansion's batch-agent
split (both files' batches otherwise covered their full file, but each independently treated these
two as already-covered "pre-existing sample" entries, and the pre-existing 5-sample body was fully
replaced rather than merged). Fixed by adding both as proper routine declarations
(`fopen(...args: object, ...kwargs: object) -> file_obj:IO`, `is_windows() -> result:bool`) in
their respective files' blocks. `goga lint salt/utils` and `goga lint .` both now report 0 errors.

## Two confirmed `goga lint` tool limitations (same as every prior repo)

- **`import_has_valid_from_path` false positive when linting a single cell out of full-project
  context** — `salt/loader`'s `LazyLoader`/`NamedLoaderContext` types, referenced from `salt/
  states` and `salt/modules`, report "not found on filesystem" when linting those cells in
  isolation; resolves to 0 errors when linting from the project root (`goga lint .`).
