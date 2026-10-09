// === TASK_C_FUNCTIONAL_VALIDATOR_FIXTURE ===
// Injected temporarily by validators/task_C_functional.sh into SignalServiceKit/tests/Jobs/JobQueueRunnerTest.swift
// (an existing, already-project-referenced test file for the job-execution framework), and stripped back out
// afterward. Not part of the permanent test suite.
//
// WHY THIS IS A CHECKLIST, NOT A LITERAL RUNNABLE ASSERTION:
// Unlike Task A (`AutoDownloadPolicy.build`) and Task B (`FullTextSearcher.searchWithinConversation`), Task C's
// required entry point is a *pattern* (JobRecord / JobRunner / JobRunnerFactory / JobQueueRunner), not a single
// fixed, pre-existing public symbol name. The task deliberately never names the concrete type a correct
// implementation should introduce (see RECON_NOTES.md: "task_C.md does not leak the mechanism"), and a
// legitimate correct implementation is free to call its job type anything
// (`MessageRetentionCleanupJobRecord`/`Runner`/`Queue` in the reference positive control is only one choice).
// A compiled Swift test cannot call a symbol whose name it doesn't know, so this feature genuinely cannot be
// exercised through "its real public entry point" the way Tasks A/B can be — it is architecture-shaped, not a
// single fixed API. validators/task_C_functional.sh's automated signal is therefore a static/behavioral scan
// over the whole diff (name-agnostic: it accepts either a real JobRecord/JobRunner pair OR a bolt-on
// Timer/lifecycle-driven equivalent, since BOTH can genuinely delete old messages and "resume" -- that
// distinction is what the architecture checks (task_C_AC1..AC5.sh) are for, not this functional check).
//
// This file instead documents the manual QA steps that would confirm the deeper *dynamic* functional
// requirements which no static analysis (ours or anyone's) can verify without actually running the app:
//
// MANUAL QA CHECKLIST (perform against a running build on a real device/simulator):
//   1. Settings: set a retention window (e.g. "30 days") on an account with > 1 batch's worth of history
//      (BulkDeleteInteractionJobRunner-style jobs batch via TimeGatedBatch; use enough messages to span
//      multiple batches, e.g. > 1-2k interactions across a few threads, all older than the cutoff).
//   2. Confirm the UI does not freeze/hang while the cleanup runs (scroll a conversation list during cleanup).
//   3. Mid-cleanup, force-quit the app (or background it and let iOS suspend/kill it). Relaunch.
//      Confirm cleanup resumes and continues making progress -- it must not restart from scratch, and it must
//      not have silently stopped (check remaining old-message count decreases further after relaunch).
//   4. Mid-cleanup, sign out. Confirm no conversation is left half-deleted/corrupted-looking; signing back in
//      (or checking local state before full data wipe on sign-out) should not show a broken thread.
//   5. After a cleanup pass completes, confirm conversation previews/unread counts/message lists in the chat
//      list and open conversation view are correct *immediately*, without relaunching the app.
//   6. Turn the retention window on for the first time on an account with pre-existing old history; confirm it
//      is applied retroactively (old messages disappear), not just to new incoming messages.
//   7. Change the window to a shorter/longer value, and turn it off entirely; confirm behavior updates
//      accordingly (a shorter window deletes more; off stops future automatic deletion).
//
// None of steps 2-7 are asserted by validators/task_C_functional.sh's automated portion -- they are printed
// as "MANUAL REVIEW REQUIRED" by that script, exactly as this comment describes them.
// === END TASK_C_FUNCTIONAL_VALIDATOR_FIXTURE ===
