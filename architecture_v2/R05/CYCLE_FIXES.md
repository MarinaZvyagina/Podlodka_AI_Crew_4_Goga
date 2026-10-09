# CYCLE_FIXES.md — R05 (VictoriaMetrics/VictoriaMetrics) Condition C

No circular dependencies found among any of the 55 cells in this restructuring (9 originally
documented + 46 new nested cells created per the scope-expansion decision below).

## Method: real import-graph analysis, not grep

Unlike prior repos in this study (which used `grep`-based cross-cell import scanning), R05's
scale (55 cells across a 120k-LOC Go monorepo) called for Go's own tooling: `go list -f
'{{.ImportPath}}|{{join .Imports ","}}'` was run once across all 8 target package trees
(`app/vminsert/...`, `app/vmagent/...`, `app/vmselect/...`, `app/vmstorage/...`,
`lib/storage/...`, `lib/mergeset/...`, `lib/promscrape/...`, `lib/promrelabel/...`), producing an
exact, compiler-verified direct-import list per package (76 packages). This was filtered to edges
between the 55 target cells and fed into a standard DFS-based cycle detector (white/gray/black
coloring). Result: **zero cycles** — the graph is a clean DAG, layered roughly as
`app/{vminsert,vmagent,vmselect}` → their own wire-format/query subpackages → `app/vmstorage` →
`lib/storage` → `lib/mergeset`, with `lib/promscrape`/`lib/promrelabel` consumed horizontally by
the ingestion/query binaries.

## Scope-expansion decision (governs why 46 new cells exist)

Phase 8's original 9-cell scope deliberately covered only each binary's own top-level
`main.go`-resident entry points (`Init`/`Stop`/`RequestHandler`), explicitly disclosing (in
`SCOPE.md`) that the ~47 real subdirectories underneath `app/vminsert`, `app/vmagent`, and
`app/vmselect` (one per wire ingestion/query protocol) were left undocumented for budget reasons —
a real violation of Goga's `location:` rule (a documented cell's real subdirectory-with-code needs
its own manifest), disclosed rather than silently ignored. Per explicit user decision, Condition C
resolved this by fully expanding scope rather than preserving the disclosed exclusion: 46 of the
~47 subdirectories with real `.go` code got their own new cell (the one exception,
`lib/promscrape/discovery`, has zero `.go` files of its own — it's a pure container of ~22
sub-package directories, one of which, `kubernetes`, was already a separate documented cell before
this restructuring; the other 21 remain out of scope for the same reason they always were — Phase
8's own `SCOPE.md` disclosed that documenting all 22 structurally-identical service-discovery
backends would duplicate the same contract shape without adding architectural information, a
different and still-valid rationale from the budget-driven cut this restructuring resolved
elsewhere).

## Two confirmed `goga lint` tool limitations encountered at this scale

Both were independently discovered by two different agents working on separate cell families,
then confirmed centrally:

1. **`import_has_valid_from_path` false positives when linting a single cell out of full-project
   context** — the same limitation documented in every prior repo in this study; resolved by
   linting from the project root (`goga lint .`), where it disappears.
2. **`import_has_not_duplicate` compares pre-alias source names, not resolved aliases** — new to
   this study, only surfaced because R05 is the first repo with enough sibling cells sharing
   identical real Go identifiers (e.g. 9 different wire-format packages each exporting their own
   `InsertHandler`) to trigger it at scale. Goga's DSL documents `AS` aliasing specifically to
   resolve such collisions, and both `app/vminsert`'s and `app/vmagent`'s manifests apply it
   correctly and uniquely — but the lint check still flags the pre-alias name as a duplicate
   across `From:` blocks. Verified empirically (not just asserted): every alias is syntactically
   valid and unique in its document, and the error persists regardless of the alias chosen.
   Resolved per-cell by formally importing only the entry points whose real (unaliased) name is
   unique forest-wide, and describing the rest in prose with an explicit `aliasing_limit` Usages
   entry naming exactly which real dependencies this affects and why — an honest disclosure of a
   tool gap, not a content gap (every real dependency is still documented, just not through a
   formal `Imports:` line for the colliding subset).
