# SETUP_COST.md — R07 (mihonapp/mihon)

## initial_generation_time

Active tool-call work spanned roughly **10:54–11:15 MSK (≈ 21 minutes)** on 2026-08-26 for the
full pipeline: reading `TREATMENT_DESIGN.md`/`PROTOCOL.md` (including Amendment 1), verifying the
pinned commit and running `goga init` (kotlin), loading the `goga-cell`/`goga-cell-kotlin`/
`goga-cookbook` DSL skills, exploring Mihon's 13-Gradle-module layout and reading the real source
of all 12 planned cells directly, authoring the ~1,220-line `docs/arch/architecture-overview.md`
plan (12 cells, written incrementally: one skeleton `Write` then one `Edit` per cell, per the
Amendment 1 mitigation), materializing it to 12 `CODEMANIFEST` files, 2 rounds of `goga lint`
correction, `goga schema` verification, and `goga contract` drift spot-checks on 5 cells.

The Skill tool's `/goga:apply` slash command was not exercised as an interactive step in this
session; materialization followed Amendment 1's documented fallback directly (a scripted
extraction of each `### Cell N: `path``/```yaml``` block from the plan file into
`<cell_path>/CODEMANIFEST`), since a prior validation run (R01) had already confirmed this
fallback is an accepted equivalent to invoking `goga-cells-by-brainstorm` by hand.

## manual_correction_time

Concentrated in one scripted pass plus a handful of targeted single-line edits, all within the
session above (not separately timed, but a few minutes of the total): one scripted global
backtick-stripping pass (see below), followed by 5 manual `Edit` calls restoring/fixing specific
backtick references and 2 manual `Edit` calls swapping mutation-syntax argument order.

## number_of_manual_corrections

- **Lint correction rounds: 2** (`goga lint` was run 3 times total):
  1. Initial `goga lint` on the freshly materialized 12-cell forest: **202 errors** — two rule
     types: `annotation_links_exists` (200 — invalid backtick cross-references to sibling method
     names, dotted expressions like `Source.getMangaUpdate`, enum constants like `ALWAYS_UPDATE`,
     wildcards like `fetch*`/`setRemote*`, and plain-language words that happened to also be a
     signature-parameter name from a *different* method/entity than the one being annotated —
     the same failure mode identified during the R01 validation run), `mutation_exists` (2 — see
     below).
  2. **Fix (scripted):** collected the exact list of 150 distinct invalid link strings directly
     from the `goga lint` error output (`Link `X` ... does not match`), then ran one Python pass
     stripping the surrounding backticks for every literal `` `X` `` occurrence across the plan
     document (310 occurrences total), converting them from broken links to plain prose — safe
     because a non-backticked mention is never a lint violation, only an invalid backtick *link*
     is. Regenerated all 12 `CODEMANIFEST` files from the corrected plan. Re-lint: **4 errors**
     remained — 2 `import_is_used` (the blanket stripping pass had also removed two *valid*
     backtick references, to `Chapter` in `domain/chapter/repository` and to `SManga` in
     `domain/manga/model`, as a side effect of those exact words also being invalid elsewhere in
     the document) and 2 `mutation_exists` (`"ConfigurableSource::Source()"` and
     `"CatalogueSource::Source()"` had the mutation base/target order backwards — the DSL's
     `Base::Target` syntax requires the *existing/imported* type first and the *new* mutated type
     second, i.e. `"Source::ConfigurableSource()"`/`"Source::CatalogueSource()"`).
  3. Restored the 2 valid backtick references and corrected the 2 mutation-syntax argument
     orders (4 total single-line `Edit` fixes, applied to both the plan document and the
     materialized `CODEMANIFEST` files to keep them in sync). Re-lint: **0 errors**.
- **Contract-drift corrections: 0.** `goga contract` was run against 5 cells (see below); every
  discrepancy found was either an intentional, disclosed abbreviation already present in the
  annotation text, or a tool-level extraction limitation (see `contract_drift_findings`) — no
  CODEMANIFEST content was found to be factually wrong and requiring correction.

## artifact_size

- **12 CODEMANIFEST files** (one per documented cell)
- **1,073 total lines** (`wc -l` across all 12 files in the deliverable directory)
- Cell sizes range from 42 lines (`domain/.../track/repository`) to 189 lines
  (`app/.../data/track`, the `Tracker` extension point)
- No `.usages/` files were created — every practice/convention used the DSL's **inline** `Usages`
  form (each practice is short, cell-specific prose: e.g. `chapter_flags_bitmask`,
  `sqldelight_row_mapper`, `extension_point`), consistent with `goga-cookbook`'s guidance that a
  separate file is unnecessary for short, cell-specific practices. No `.usages/*.md` artifact
  count applies.

## contract_drift_findings

`goga contract` (Kotlin extractor) was run against 5 cells — `domain/.../track/model`,
`domain/.../chapter/model`, `domain/.../manga/model`, `source-api/.../source`, and
`data/.../manga` — comparing CODEMANIFEST signatures/methods/properties against the real
tree-sitter-extracted implementation:

- **`source-api/.../source`** — perfect match on every method and property across `Source`,
  `CatalogueSource`, and `ConfigurableSource` (the three types in this cell that have a Kotlin
  class body). No drift.
- **`domain/.../chapter/model`, `domain/.../manga/model`** — perfect match for `Chapter`,
  `Manga`, and the top-level `applyFilter` routine (every signature, method, and derived-property
  type matched exactly, including nullable-type markers). No drift.
- **`data/.../manga`** — `MangaMapper`'s three mapper methods matched on return type and
  semantic label; the CODEMANIFEST intentionally documents an *abbreviated* parameter list for
  these row-mapper functions (disclosed inline as "not individually listed here for brevity",
  since each maps 20-30 raw SQL columns) — `goga contract` correctly surfaced the full real
  parameter list, confirming the abbreviation was accurately disclosed rather than silently
  incomplete. `MangaRepositoryImpl`'s constructor signature matched exactly.
- **Tool-level finding, not a content error:** for every type in this forest that is a
  single-line, bodyless Kotlin declaration — i.e. `data class X(...)` or
  `data class X(...) : SomeInterface` with no trailing `{ }` block (`Track`, `ChapterUpdate`,
  `NoChaptersException`, `MangaCover`, `MangaUpdate`, `MangaWithChapterCount`) — `goga contract`
  returned `"implementation": null` even though the CODEMANIFEST-declared signature was manually
  re-verified against the real source (already read in full during authoring) to be accurate.
  Every type in the same cells that *does* have a body block (`Track`'s sibling types have none,
  but `Chapter`, `Manga`, `MangaMapper`, all of `source-api/source`) extracted and matched
  correctly. This indicates Goga v1.2.2's Kotlin contract extractor does not detect bodyless
  single-expression-style class declarations, not that this forest's documentation of those types
  is wrong. Disclosed here per the freeze-discipline convention established during the R01
  validation run; no CODEMANIFEST content was changed as a result, since re-verification against
  the real source found the documented signatures correct.

No drift was found that would materially mislead an agent about a cell's real public shape.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if Mihon or Goga change
mid-benchmark.
