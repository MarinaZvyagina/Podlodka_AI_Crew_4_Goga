# PLAUSIBILITY_CHECK.md — R09 (mozilla-mobile/firefox-ios)

## When this check was performed

`tasks/R09/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 9 CODEMANIFEST files were authored, materialized, linted, and
drift-checked — per the assignment's explicit ordering requirement. No content in the
architecture forest was revised in response to reading the tasks (see "Outcome" below).

## The four task prompts (quoted)

- **Task A**: fix a bug where removing a browser window's saved tab data only deletes the
  primary on-disk copy, leaving its recovery backup copy orphaned forever, causing the profile
  folder to grow without bound over time; both the primary and backup copy must be deleted
  together, non-existent-backup cases must not error, and untargeted windows (and their
  backups) must be left untouched.
- **Task B**: add a third choice ("Close Tab") to the navigation toolbar's customizable middle
  button, alongside the existing "Home"/"New Tab" choices — persisted the same way, measured by
  telemetry the same way, without changing the existing two choices' behavior.
- **Task C**: A/B test an alternative speech-to-text pipeline for voice search behind a flag,
  with enrolled/non-enrolled users running side by side without shared mutable state, all
  existing feature behavior (record button, streaming partial results, error handling,
  stop/cancel) unchanged either way, and test coverage that both pipelines are selectable.
- **Task D**: show a brief, self-dismissing confirmation message after the "Copy Address"
  accessibility action copies the current URL, similar to the existing bookmark-confirmation
  pattern.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 9 CODEMANIFEST files for the task-specific terms each prompt turns on: none of
"orphan", "stale", "close tab" (as a toolbar button choice), "middle button", "home button" /
"new tab button" (as toolbar customization choices), "A/B test", "alternative pipeline",
"enrolled", "speech-to-text", "TranscriptionEngine", "SpeechAnalyzerEngine",
"SFSpeechRecognizerEngine", "copy address", "clipboard", "confirmation toast", or "bookmark
confirmation" appear anywhere in the forest. The one hit from a broad grep pass — "backup file"
in `TabDataStore`'s CODEMANIFEST — is the pre-existing, real `backup_on_write` mechanism
description authored from reading `TabDataStore.swift`/`TabFileManager.swift` directly; it never
says anything shaped like "the backup copy isn't cleaned up" or "fix the leak" — see the Task A
discussion below for why this generic, real-mechanism description is expected, not leakage.

## Where genuine overlap exists, and why it's expected rather than leakage

Two of the four tasks (A, C) touch functionality that lives inside or very near cells this forest
documents; one (B) touches a cell only at a shallow, non-overlapping layer; one (D) has no
overlap at all.

- **Task A ↔ `BrowserKit/Sources/TabDataStore`**: this is the closest overlap, structurally
  identical in kind to the R01 (freqtrade) precedent's Task-C/`plugins/protections` case. The
  forest's `backup_on_write` usage text says exactly: "Before a window's data file is
  overwritten, the previous copy is saved as a backup file, so that a read failure on the
  primary file can fall back to the last known-good backup." — a true, generic architectural fact
  about *why* the backup mechanism exists, read directly from `TabDataStore.swift`'s
  `createWindowDataBackup`/`windowURLPath(isBackup:)` methods. It says nothing about backups
  being leaked, never being deleted, or growing unbounded — the CODEMANIFEST's
  `removeWindowData` annotation ("Delete the saved data for exactly the given window UUIDs,
  leaving others untouched") describes the method's documented *contract*, not the real
  implementation's actual bug (only deleting the primary-copy directory, never the backup
  directory) — an agent still has to go read the real `removeWindowData` implementation to
  discover that it doesn't yet touch the backup directory at all. Judgment call: kept as-is,
  since documenting this real, pre-existing persistence mechanism (and the fact that a backup
  copy exists at all) generically is precisely the kind of architecture-discoverability the Goga
  condition is meant to test (relevant to RQ7/RQ8: extension-point usage rate, architecture
  discovery cost) — not an accidental hint at the specific bug or its fix.
- **Task C ↔ `BrowserKit/Sources/QuickAnswersKit/UI`**: overlap exists only at the feature-name
  level, and in the *opposite* direction from leakage. The forest's `QuickAnswersKit/UI` cell
  documents the feature's public presentation surface (`QuickAnswersViewController`,
  `QuickAnswersNavigationHandler`, `QuickAnswersTelemetry`) and explicitly states that "the
  speech-capture and results-fetch backend behind it (recording engines, transcription, the
  results service) is a separate, internal implementation detail of this same target and is out
  of scope for this cell." The actual mechanism Task C's A/B test would plug into — a
  `TranscriptionEngine` protocol already implemented by two concrete engines, selected today by
  an `if #available` OS-version check rather than a flag — lives entirely in the `Backend`
  subdirectory this forest deliberately excluded (see `SCOPE.md`: "`QuickAnswersKit/Backend`...
  has no `public` declarations at all"). An agent gets zero architectural help from this forest
  in locating `TranscriptionEngine` or its two existing implementations; if anything, the
  forest's own scoping note points *away* from that mechanism by calling it out of scope.
- **Task B ↔ `BrowserKit/Sources/ToolbarKit`**: weak, non-actionable overlap. `ToolbarKit`
  documents `ToolbarElement`/`ToolbarMenuElement`/`ToolbarManager` — the generic UI value-type
  model and border-drawing policy for toolbar controls — with no mention of "Home"/"New Tab"/
  "Close Tab" as specific middle-button choices, no mention of a settings screen, and no mention
  of how a choice is persisted or measured (that logic lives in `Client`-side feature code this
  forest does not document, e.g. wherever the toolbar's own Redux slice and settings screen
  live, both out of scope per `SCOPE.md`). The forest would tell an agent generically what a
  `ToolbarElement`'s `onSelected` closure and `menuElements` are for, but nothing about the
  three-way Home/New-Tab/Close-Tab choice itself.
- **Task D ↔ (no cell)**: no overlap found. Nothing in the forest mentions the address bar's
  "Copy Address" accessibility action, clipboard operations, or any confirmation/toast UI
  pattern (`ComponentLibrary`, where such a shared confirmation-toast component would likely
  live, was not in scope for this forest — see `SCOPE.md`'s exclusion list).

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task A / `TabDataStore`) was judged to be the expected, in-scope operation of
documenting a real, load-bearing persistence mechanism generically — not task-specific hint
content — and is disclosed here explicitly rather than papered over, per `TREATMENT_DESIGN.md`
§4's "independent plausibility check" requirement. The Task C case is disclosed for completeness
even though it runs opposite to the leakage concern (the forest documents only the feature's
outer shell and explicitly excludes the exact mechanism the task would use). As with the R01
precedent, no retroactive rewording was performed after seeing the task list, to avoid the
appearance of hand-tuning the artifact post hoc, which would itself be a worse violation of the
freeze discipline than leaving these honestly-disclosed, architecturally-justified overlaps in
place.
