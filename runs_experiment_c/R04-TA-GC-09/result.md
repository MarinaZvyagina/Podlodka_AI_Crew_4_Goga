# R04-TA-GC-09

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $1.7983685999999999
Duration: 228744ms, turns: 31

## Agent's own summary

# Scope Resolution Report

## Task Summary
Renaming a drawing must never produce a filename that is unsafe to save on Windows/macOS/Linux. The user can type any characters into the name field (ProjectName.tsx / ImageExportDialog.tsx), but the name used at the moment of writing to disk (JSON save, PNG/SVG export) must always be filesystem-safe, and any adjustment made to achieve that must be surfaced to the user rather than applied silently.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `packages/common/src` | Governed shared-utility cell; natural home for a new `sanitizeFilename`-style routine (sibling to existing `normalizeLink` sanitization in `url.ts`); already governs `DEFAULT_FILENAME`. | High |
| `packages/excalidraw/actions` | Governed cell hosting `actionChangeProjectName`, `actionSaveToActiveFile`, `actionSaveFileToDisk` — the commit/save call sites. Individual actions are NOT declared types in this cell's manifest (only the `Action`/`register`/`ActionManager` framework is). | Medium (implementation only, no manifest entries for individual actions) |
| `packages/excalidraw` root (components/App.tsx/data/*) | Contains `ProjectName.tsx`, `ImageExportDialog.tsx`, `App.getName()`, `data/index.ts`, `data/json.ts`, `data/filesystem.ts` — every concrete call site that builds the on-disk filename. Explicitly undocumented/ungoverned per `packages/excalidraw/actions`'s own CODEMANIFEST Annotations ("packages/excalidraw's root is not a documented cell in this study... deliberately excluded... see SCOPE.md"). | High (implementation), but out of CODEMANIFEST governance |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `packages/common/src` | Will own the new sanitization routine; `DEFAULT_FILENAME` constant already here is the fallback target when a sanitized name becomes empty. |
| `packages/excalidraw/actions` | `actionChangeProjectName.perform` is the single commit point for `appState.name`; `actionSaveToActiveFile`/`actionSaveFileToDisk` are two of the call sites that turn that name into a saved file. |
| `packages/excalidraw` root | Home of the remaining call sites (`App.getName()`, `exportCanvas`, `saveAsJSON`, `fileSave`) and both rename UI inputs. Must be touched to close every save/export path, even though it carries no manifest to reconcile. |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| `packages/element/src` | No participation — element/scene data model is untouched by a filename change. |
| `packages/math/src` | Purely geometric primitives; no data-flow relevance to filenames. |
| `packages/fractional-indexing/src` | Order-key generation; unrelated leaf cell. |
| `excalidraw-app/` | Ticket scope is explicitly the editor's own name/title field and its save/export actions, not the standalone app's separate persistence layer (not investigated further unless the investigator finds it re-reads `appState.name` for its own file-like storage — flagged as a watch item, not pre-excluded on faith). |

## Usage Relationships
| Usage | Relevance |
|---|---|
| `packages/common/src`'s `env_detection`/`branding_pattern` usages | Not applicable — the new routine is a plain string transform, not env-branching or branded-type work. |
| `packages/excalidraw/actions`'s `host_app_state` usage | Applies to `actionChangeProjectName.perform`'s existing signature shape (appState param) but not to the sanitization logic itself. |
| No project-level `.goga/usages/` entries exist (`codemanifest.usages`/`codemanifest.annotations` both return "Option not found") | No mandatory base practices to apply. |

## Semantic Participation Summary
- **`packages/common/src`**: gains one new contractual routine (name TBD, e.g. `sanitizeFilename`) that the rest of the fix depends on. This is the only cell where a CODEMANIFEST addition is required.
- **`packages/excalidraw/actions`**: `actionChangeProjectName` is where the raw typed value first becomes `appState.name`; sanitizing (and flagging the adjustment) here is the most natural single choke point for the "commit" side of the rename flow. `actionSaveToActiveFile`/`actionSaveFileToDisk` consume `app.getName()` and pass it straight to `saveAsJSON`/`resaveAsImageWithScene`. No manifest entries exist for any of these three actions, so implementation there is unconstrained by contract text — ordinary code changes.
- **`packages/excalidraw` root**: every other save/export call site (`App.getName()`, `data/index.ts:exportCanvas`, `data/json.ts:saveAsJSON`, `data/filesystem.ts:fileSave`, plus the two rename inputs `ProjectName.tsx`/`ImageExportDialog.tsx`) lives here. All are in scope for implementation; none require CODEMANIFEST changes since the root package is not a documented cell.

## Final Investigation Scope
1. `packages/common/src` (constants.ts, new sanitization file, index.ts, CODEMANIFEST)
2. `packages/excalidraw/actions/actionExport.tsx` (actionChangeProjectName, actionSaveToActiveFile, actionSaveFileToDisk)
3. `packages/excalidraw/components/ProjectName.tsx`
4. `packages/excalidraw/components/ImageExportDialog.tsx`
5. `packages/excalidraw/components/App.tsx` (getName())
6. `packages/excalidraw/data/index.ts` (exportCanvas)
7. `packages/excalidraw/data/json.ts` (saveAsJSON)
8. `packages/excalidraw/data/filesystem.ts` (fileSave)
9. `packages/excalidraw/actions/actionClipboard.tsx` (also calls `app.getName()` per prior exploration — verify relevance during investigation)

## Scope Risks
- **Under-scoping**: missing a save/export call site that reads `appState.name`/`app.getName()` directly (bypassing whichever choke point is chosen) would leave a silent gap where an unsafe name still reaches disk. `actionClipboard.tsx` and any host-app `onExport` integration points must be checked.
- **Over-scoping**: touching `excalidraw-app/`'s own persistence (IndexedDB/localStorage scene storage) would be out of scope — that path doesn't write OS files by filename and isn't implicated by the ticket.
- **Governance risk**: if the sanitization routine is added anywhere other than a documented cell (e.g., dropped directly into `packages/excalidraw/data/filesystem.ts` with no shared cell backing it), it creates undocumented new capability outside any CODEMANIFEST, which the pipeline's manifest reconciliation step must catch — the plan should place the reusable primitive in `packages/common/src` specifically to keep it governed.

## Notes
- No existing filename-sanitization utility exists in the repo (confirmed) — this is new capability addition to `packages/common/src`, not drift correction against an existing manifest entry.
- No project-level base usages/annotations are configured (`.goga/config.yml` has no `codemanifest` section), so no additional mandatory practices apply beyond the DSL/cookbook defaults already loaded.
- `packages/excalidraw/actions`' CODEMANIFEST explicitly disclaims formal coverage of individual registered actions and of the entire `packages/excalidraw` root — this is a documented, deliberate scope reduction (SCOPE.md referenced but not present as a file in this checkout), not an oversight to fix as part of this change.
