# CYCLE_FIXES.md — R10 (signalapp/Signal-iOS) Condition C

`goga lint .` passes clean across all 52 cells (`cells: 52 errors: 0`) — no formal Goga `Imports:`
cycle exists anywhere in the DSL model. A separate real-dependency analysis (below) found that
most of the 52-cell forest is mutually reachable, disclosed here rather than hidden — but the
underlying cause here is structurally different from every prior repo in this study, and that
difference is itself the finding worth recording.

## Method, and a genuine methodological difference from every prior repo

R01/R02/R05/R08/R09 all had a real per-cell *compilation unit* boundary to analyze (a Python
package, a Go package, a Gradle module, or — for R09's BrowserKit — a separate SwiftPM library
target with real `import ModuleName` statements between targets). **R10's 52 cells all live inside
one single Swift compilation target, `SignalServiceKit`** — and within a single Swift target,
files do not `import` each other; every type in every file is visible to every other file with no
compiler-enforced boundary at all. There is no `import`-statement graph to extract here, unlike
every prior repo.

The closest honest proxy: for each of the 52 cells' own CODEMANIFESTs, every declared top-level
type name that is *uniquely owned* (declared in exactly one cell, not reused/overloaded elsewhere
in the forest — 337 of the forest's declared names qualified) was checked for real word-boundary
source-text references across every other cell's own `.swift`/`.h`/`.m` files. This is noisier
than a true import graph (it can't distinguish "uses this type as a real dependency" from, in
principle, an unrelated comment or string — though in practice Swift identifiers rarely appear
outside real code) but it is the only real signal available for a single-target codebase, and it
only counts names that are unambiguously owned by one cell, so no cross-cell name collision can
produce a false edge.

## Finding: a 46-of-52-cell weakly-connected mass, driven by a small set of pervasive foundation types

440 real cross-cell references were found; DFS cycle detection shows 46 of the 52 cells are
mutually reachable (only `Jobs`, `Attachments` [the 2-file leaf], `Attachments/V2/AudioWaveform`,
`Attachments/V2/Mocks`, `Attachments/V2/Thumbnails`, and `Interactions/Polls/Records` sit outside
it). Unlike R02's `salt/loader` or R08's `AppDependencies` — where a small number of *specific
bidirectional pairs* drove the cycle — R10's mass is explained by a short list of foundation types
referenced almost everywhere as parameters or base classes, not by pairs of cells that both import
each other's business logic:

| Type | Declared in | Referenced from N other cells |
|---|---|---|
| `DBReadTransaction` / `DBWriteTransaction` | `Storage/Database/SDSDatabaseStorage/V2` | 37 / 36 |
| `DependenciesBridge` | `Environment` | 22 |
| `TSMessage` / `TSInteraction` | `Messages/Interactions` | 21 / 17 |
| `TSAccountManager` | `Account/TSAccountManager` | 14 |
| `TSGroupThread` / `TSContactThread` | `Threads` | 14 / 12 |
| `AttachmentStore` | `Messages/Attachments/V2/AttachmentStore` | 13 |
| `InteractionFinder` | `Storage/Database/Records` | 12 |

`DBReadTransaction`/`DBWriteTransaction` alone (a read/write database-transaction handle passed
as a parameter into nearly every persistence-touching method in the entire forest — the same
pattern documented in the pre-existing `Environment`/`SDSDatabaseStorage` cells' own Annotations)
account for the largest share: any two cells that each have a method taking a transaction
parameter and are each referenced by the other for some other reason will show up as "mutually
reachable" under this analysis, even though neither cell's business logic depends on the other's.
`TSMessage`/`TSInteraction` (the base persisted-model hierarchy every message/interaction type
inherits from) and `DependenciesBridge` (the app's composition root, deliberately constructed from
nearly every other subsystem, exactly as its own Annotations already state) are the two next
largest, and both are the *expected* shape of a mature single-module ORM-style domain framework,
not evidence of tangled business-logic coupling between unrelated features.

## Resolution: disclosed, not hidden — and a note on why this isn't a formalization question

For R02/R05/R08/R09, the resolution pattern was "formalize the structurally-heavier direction as a
Goga `Imports:`, describe the reverse in prose." That pattern doesn't cleanly apply here: because
Swift gives no compiler-enforced boundary between files in the same target, there is no "reverse
direction" to leave informal — every reference in every direction is equally real and equally
unenforceable by the language itself. `goga lint .` reports 0 errors because the DSL's declared
`Imports:` blocks (which every cell in this forest does use, for the specific named types each
cell's own signatures actually reference) are — as established in every prior repo — a narrower,
intentional, type-driven documentation of the *load-bearing* dependencies worth naming, not a
transitive closure of every real source-text reference. That distinction is doing more work here
than in any prior repo, because for a single-Swift-target codebase, the "transitive closure of
every real reference" is close to the whole graph by construction — this is a property of Swift's
module system, not a defect introduced by this restructuring, and not something a cell-boundary
restructuring can or should try to collapse into a clean DAG without introducing real SwiftPM
module boundaries into Signal-iOS's actual build (out of scope for Condition C).

## Two real facade gaps found via whole-project lint (not single-cell)

`TSMessage` and `TSInteraction` — the two most pervasively-referenced types in the entire
forest — were imported by name from `SignalServiceKit/Messages/Stickers`' and `.../BodyRanges`'
own declared `Imports:` blocks, but neither had ever been declared in the pre-existing (Phase
8-authored) `SignalServiceKit/Messages/Interactions/CODEMANIFEST`, despite both being real,
central types declared directly in that cell's own `TSInteraction.h`/`TSMessage.h` files. Fixed by
adding minimal (not exhaustive — these are large legacy Objective-C base classes; a full facade
dump was judged out of proportion to a 2-symbol import gap) but accurate entity declarations for
both, explicitly noting in each that it documents the type's existence and role for cross-cell
reference purposes rather than its complete historical API surface.

A third, narrower issue — `Messages/Attachments/V2/AttachmentReference` imported the bare name
`MessageAttachmentReferenceRecord`, but the type is actually declared under its real nested name,
`AttachmentReference.MessageAttachmentReferenceRecord`, in `Messages/Attachments/V2/Records` — was
a same-cell-family naming mismatch between two parallel batch-agent outputs, not a genuine facade
gap; fixed by correcting the `Imports:` and body signature to the real qualified name.
