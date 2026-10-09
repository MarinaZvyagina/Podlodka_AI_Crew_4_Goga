# R10 (signalapp/Signal-iOS @ 6e3a059f752785b349d5938dfa4c36f216fb0ae3) — Functional Validators

This document records the **functional** validators (as opposed to Phase 4's `task_X_AC*.sh` **architecture**
validators) built for tasks A–D, why each is scoped the way it is, and the actual results of running each one
against the real positive/negative control diffs in `controls/`.

All work was done against the same local clone used for Phase 4/5, `/tmp/benchmark-repos/R10`, pinned at
`6e3a059 Update translations`. Before starting, `git -C /tmp/benchmark-repos/R10 diff --stat` was confirmed
empty (only pre-existing, unrelated untracked files: `.goga/`, `docs/`, a handful of `CODEMANIFEST` files — none
of these were touched). After every verification run below, the repo was reset (`git checkout -- .` +
`git clean -fd Signal SignalServiceKit SignalUI`) and reconfirmed clean; it is clean now.

## Environment / disk-constraint decision (read this first)

At the start of this work, `df -h /` showed **~9GB free** (down from the ~26GB Phase 5 started with, and less
than the ~14GB Phase 5 had left after a single partial `xcodebuild` attempt that still failed with "No space
left on device" at the link step for a third-party Pod — see `CONTROL_RESULTS.md`). Free space kept drifting
down further during this session (to ~6GB) even though `du` showed **no growth** in anything we created —
`df`'s "Used" figure stayed flat at 17Gi throughout, so the drift is APFS purgeable/snapshot churn from other
processes on the shared machine, not anything these scripts wrote. Given this, and given Phase 5's own
documented failure with *more* headroom than we had, **no real `xcodebuild build`/`test` was attempted in this
session.** Each validator below still *contains* a real, disk-gated attempt (checks free space against a 40GB
safety threshold before trying `xcodebuild`) so that on a properly-provisioned CI machine it would actually
compile/link — but on this machine that path is always skipped and reported as `MANUAL REVIEW REQUIRED`, never
silently counted as a pass. This mirrors, and is consistent with, Phase 5's own honest conclusion.

What *did* run for real, every time, on this machine:
- **Fixture injection** into an existing, already-project-referenced test file (not a new file — this project's
  `project.pbxproj` lists test sources explicitly, with no `PBXFileSystemSynchronizedRootGroup`, so a new file
  would not be picked up by Xcode without an unsafe pbxproj edit; appending to an existing referenced file
  avoids that entirely), followed by cleanup that removes exactly the injected block via marker comments
  (verified to restore the file byte-for-byte via `git diff --stat` after every run below).
- **`swiftc -parse`** on the fixture-injected file — a real compiler invocation, syntax-level only (no import
  resolution, no type-checking, no disk-heavy module cache growth), catching gross corruption.
- **A static/behavioral scan** of the actual patched source (current working-tree content, or the diff's added
  lines, depending on task — see per-task notes) that is the real, primary source of the PASS/FAIL verdict on
  this machine.

## Calibration: functional checks are not all equally strict, on purpose

Reading `metadata_X.yaml`'s `notes_for_positive_negative_control` closely reveals the four tasks were **not**
designed with the same functional/architecture split:

- **Task A's** own `functional_requirements` explicitly say the new preference must "Actually change whether a
  voice message attachment gets auto-downloaded — this needs to be a real behavior change in the download
  logic, **not just a new row in the settings UI**." A UI-only trap is disqualified *functionally*, not just
  architecturally. `task_A_functional.sh` is therefore **strict**: it verifies the real decision logic
  (`AutoDownloadPolicy.build`) actually branches on the new preference, and correctly **fails** the negative
  control functionally (this is a deliberate, documented deviation from `CONTROL_RESULTS.md`'s narrative table,
  which described the negative control as passing "a shallow functional check" — that description refers to a
  hypothetical weaker check, not to what `metadata_A.yaml`'s own `functional_check_command` text prescribes;
  see "Deviation notes" below).
- **Tasks B, C, and D's** own notes explicitly design their negative/trap controls to be **functionally
  indistinguishable from the positive control on a single device** — that's the entire point of the "dangerous
  success" scenario (`Functional Success = true, Architecture Conformance = false`, in Task D's own words).
  Their functional validators are therefore **deliberately implementation-agnostic** about *which* code path
  was used (job-framework vs. bolt-on Timer; `InteractionDeleteManager` vs. raw `anyRemove`; `AttachmentStore`
  vs. raw SQL) — that discrimination is what the existing `task_X_AC*.sh` architecture scripts are for.

This calibration is what makes "Dangerous Success" (functional pass + architecture fail) observable at all for
B/C/D, and correctly *not* observable for A's specific negative control (which fails both axes — a valid,
different kind of finding, not a design defect in the validator).

---

## Task A — Voice-message auto-download preference

**Script:** `validators/task_A_functional.sh` · **Fixture:** `validators/fixtures/task_A_test.swift` (injected
into `SignalServiceKit/tests/Attachments/AutoDownloadPolicyTest.swift`)

**Command:** `validators/task_A_functional.sh /tmp/benchmark-repos/R10`

**What it checks:**
1. Injects a Swift Testing (`import Testing`) fixture exercising the real public entry point named in
   `metadata_A.yaml`'s `required_existing_abstractions` — `AutoDownloadPolicy.build` and
   `MediaBandwidthPreferences.MediaType` — asserting only on externally observable behavior, **never assuming
   the new case's name**: (a) `MediaType.allCases.count >= 5`, (b) a large voice-message audio attachment
   resolves to some `.preference(mediaType:)` that is `!= .audio`, (c) a small voice-message audio attachment
   still resolves to `.always` (fast path preserved), (d) a non-voice audio attachment still resolves to
   `.preference(mediaType: .audio)`. `swiftc -parse` runs on the injected file (real, passed every time).
2. Disk-gated real `xcodebuild build -scheme SignalServiceKit` attempt (skipped here — see above).
3. **Primary verdict on this machine:** a static/behavioral scan of the *current* (patched) file content —
   extracts the actual `MediaType` case list from `MediaBandwidthPreferenceStore.swift` (implementation-agnostic
   to the new case's name), then confirms `AutoDownloadPolicy.swift`'s audio branch (a) gates on
   `renderingFlag == .voiceMessage`, (b) routes that branch to the newly-discovered case (not `.audio`), and (c)
   still falls back to `.preference(mediaType: .audio)` for non-voice audio.

**Confirmed results (this session, both resets to a clean checkout before/after):**
| Control | Result | Detail |
|---|---|---|
| `controls/task_A_positive.diff` | **PASS** (exit 0) | New case `voiceMessage` found; `AutoDownloadPolicy` branch confirmed gated + routed to `.voiceMessage`; `.audio` fallback intact; UI label switch also extended (informational) |
| `controls/task_A_negative.diff` | **FAIL** (exit 1) | `MediaType` still has only 4 cases (`photo video audio document`) — negative control never touches `MediaBandwidthPreferenceStore.swift` or `AutoDownloadPolicy.swift` at all |

**Deviation note:** `CONTROL_RESULTS.md`'s Task A table lists the negative control's functional row as "PASS
(shallow) — setting exists, is togglable, persists." Our validator correctly returns FAIL instead, because it
implements `metadata_A.yaml`'s actual `functional_check_command` text (which explicitly asks to confirm
`AutoDownloadPolicy.swift`'s routing, not just "a setting exists") and its `functional_requirements` bullet
forbidding a UI-only implementation. This is an intentional, justified strengthening, not a bug — a validator
that let the negative control pass functionally here would contradict metadata_A.yaml's own stated
requirements.

**Manual-review-only:** persistence across a real app relaunch; that a real network download is actually
skipped/performed per the resolved preference (both require running the app).

---

## Task B — Attachments-only filter for in-conversation search

**Script:** `validators/task_B_functional.sh` · **Fixture:** `validators/fixtures/task_B_test.swift` (injected
into `Signal/test/util/FTS/GRDBFullTextSearcherTest.swift`)

**Command:** `validators/task_B_functional.sh /tmp/benchmark-repos/R10`

**What it checks:**
1. Injects an XCTest fixture calling `FullTextSearcher.shared.searchWithinConversation(..., attachmentsOnly:)`
   — this assumes the architecturally-prescribed location for the new parameter (documented as a known
   limitation: a candidate that filters entirely in the UI layer, like the negative control, would fail to
   *compile* against this fixture, not fail an assertion — this fixture is aspirational for a full-build
   environment, not the source of the on-machine verdict). `swiftc -parse` runs regardless (passed every time).
2. Disk-gated real `xcodebuild build -scheme Signal` attempt (skipped here).
3. **Primary verdict on this machine:** a layer-agnostic static scan of the diff's added lines for (a) an
   attachments-only toggle/parameter signal (`attachmentsOnly`/`isAttachmentsOnlyFilter`/etc.) and (b) an
   attachment-presence-check signal (`hasBodyAttachments(`, `attachmentStore.fetchReferences(`,
   `MessageAttachmentReference`, `hasMediaAttachments(` — accepting **either** the correct `AttachmentStore`
   abstraction or the negative control's raw SQL, since distinguishing those is `task_B_AC2.sh`/`AC3.sh`'s job).

**Confirmed results:**
| Control | Result | Detail |
|---|---|---|
| `controls/task_B_positive.diff` | **PASS** (exit 0) | `isAttachmentsOnlyFilterEnabled` + `attachmentsOnly:` parameter found; filtering via `message.hasBodyAttachments(transaction:)` found |
| `controls/task_B_negative.diff` | **PASS** (exit 0) | `isAttachmentsOnlyFilterEnabled` found; filtering via raw SQL against `MessageAttachmentReference` found — functionally it does filter, matching `CONTROL_RESULTS.md`'s "PASS (shallow)" framing exactly |

This is the intended "Dangerous Success" shape for Task B: functional PASS on both, while `task_B_AC2.sh` and
`task_B_AC3.sh` (already existing, re-confirmed not touched) fail the negative control.

**Manual-review-only:** actual runtime search-result correctness with real photo/video/voice/file attachments;
that previous/next result navigation still works; that both 1:1 and group threads behave identically (all
require a full app build + simulated conversation).

---

## Task C — Message retention cleanup via the job framework

**Script:** `validators/task_C_functional.sh` · **Fixture:** `validators/fixtures/task_C_test.swift` (injected
into `SignalServiceKit/tests/Jobs/JobQueueRunnerTest.swift`)

**Command:** `validators/task_C_functional.sh /tmp/benchmark-repos/R10`

**What it checks:** Task C's required entry point is a *pattern* (JobRecord/JobRunner/JobRunnerFactory), not one
fixed pre-existing symbol name — a legitimate implementation can name its job type anything. A compiled unit
test cannot call a symbol it doesn't know the name of, so (unlike A/B) **no literal runnable assertion is
possible here**; `fixtures/task_C_test.swift` is a documented manual-QA checklist instead (still injected +
`swiftc -parse`'d, to confirm it doesn't corrupt the host file). The real, framework-agnostic, on-machine
verdict is a static scan of the diff's added lines for **all** of: a retention-preference signal, a
cutoff-date-computation signal, an actual deletion call (`interactionDeleteManager.delete(` OR
`.anyRemove(transaction:`), a resumption/batching signal (`TimeGatedBatch`, `anchorMessageRowId`,
`lastProcessedRowId`, `JobRecord`, `cursor`, etc.), and a launch/trigger signal
(`start(shouldRestartExistingJobs`, `applicationDidBecomeActive`, etc.) — deliberately accepting **either** the
correct job-framework pattern or the bolt-on Timer/lifecycle equivalent, since that distinction is
`task_C_AC1.sh`–`AC5.sh`'s job.

**Confirmed results:**
| Control | Result | Detail |
|---|---|---|
| `controls/task_C_positive.diff` | **PASS** (exit 0) | All 5 signal categories found: `MessageRetentionCleanupJobQueue`, `cutoffReceivedAtTimestamp`, `interactionDeleteManager.delete(`, `JobRecord`/migration case, `jobQueueRunner.start(shouldRestartExistingJobs:)` |
| `controls/task_C_negative.diff` | **PASS** (exit 0) | All 5 signal categories found: `MessageRetentionManager`/`retentionWindowDays`, `cutoffReceivedAtTimestamp`, `interaction.anyRemove(transaction:)`, `lastCleanupCompletedThroughDateKey`/cursor, `applicationDidBecomeActive` — matches `CONTROL_RESULTS.md`'s "PASS (shallow) — messages do get deleted, and it resumes via its own UserDefaults-style cursor" exactly |

Both PASS, exactly the intended "Dangerous Success" shape (`task_C_AC1.sh`–`AC5.sh` fail all 5 for the negative
control, already re-confirmed unmodified).

**Manual-review-only (always printed, regardless of the static verdict — see the checklist in
`fixtures/task_C_test.swift`):** UI responsiveness during a large cleanup; that an interrupted cleanup actually
resumes (vs. restarting or silently stopping) after a real force-quit/relaunch; sign-out safety mid-cleanup;
immediate (no-relaunch) conversation preview/unread/message-list correctness after a pass; retroactive
application on first enabling; changing/disabling the window at any time. None of these can be verified without
running the app.

---

## Task D — Delete all messages sent by me in a conversation

**Script:** `validators/task_D_functional.sh` · **Fixture:** `validators/fixtures/task_D_test.swift` (injected
into `SignalServiceKit/tests/Messages/DeleteForMe/DeleteForMeOutgoingSyncMessageManagerTest.swift`)

**Command:** `validators/task_D_functional.sh /tmp/benchmark-repos/R10`

**What it checks:** Like Task C, the new "delete all my messages in this thread" entry point has no fixed name
(only the underlying `InteractionDeleteManager`/`DeleteForMeOutgoingSyncMessageManager` it must route through is
fixed) — this benchmark's own positive/negative controls happen to converge on the same
`DeleteAllMessagesSentByLocalUserManager` name, but hardcoding that would violate the "not internal helpers
specific to one candidate implementation" instruction, so it isn't hardcoded. `fixtures/task_D_test.swift` is
likewise a documented manual-QA checklist (injected + `swiftc -parse`'d). The on-machine verdict is a static
scan of the diff's added lines for **all** of: a local-user-message-selection signal (`TSOutgoingMessage`), a
thread-scoped enumeration signal (`InteractionFinder`/`enumerateInteractions`), and an actual deletion call
(`interactionDeleteManager.delete(` OR `.anyRemove(transaction:` — deliberately accepting either, per this
task's own documented intent that the `anyRemove` path should be "Functional Success = true, Architecture
Conformance = false").

**Confirmed results:**
| Control | Result | Detail |
|---|---|---|
| `controls/task_D_positive.diff` | **PASS** (exit 0) | `TSOutgoingMessage` check + `InteractionFinder(...).enumerateInteractionsForConversationView` + `interactionDeleteManager.delete(` all found |
| `controls/task_D_negative.diff` | **PASS** (exit 0) | Same selection/enumeration signals + `interaction.anyRemove(transaction: tx)` found — matches `CONTROL_RESULTS.md`'s "PASS (same-device) — deletes the right messages locally" exactly |

Both PASS, exactly the intended "Dangerous Success" shape (`task_D_AC1.sh`–`AC4.sh` fail all 4 for the negative
control, already re-confirmed unmodified).

**Manual-review-only (always printed):** multi-device sync propagation (a same-device static check fundamentally
cannot distinguish a real sync-message send from silence — `task_D_AC2.sh` is the closest automatable proxy,
checking for `.sendSyncMessage(interactionsThread:)` in the diff); call-record consistency (`task_D_AC3.sh` is
the closest proxy); immediate UI/cache consistency without relaunch (`task_D_AC4.sh` is the closest proxy). This
is precisely the gap the task is designed to probe, and is never silently scored as a full pass.

---

## Summary

| Task | Functional check strictness | Positive | Negative | Matches CONTROL_RESULTS.md? |
|---|---|---|---|---|
| A | Strict (behavior-change required, per metadata's own text) | PASS | **FAIL** | Deviates, intentionally (see Deviation note above) |
| B | Layer-agnostic (architecture axis handles the rest) | PASS | PASS | Yes — "Dangerous Success" shape |
| C | Framework-agnostic (architecture axis handles the rest) | PASS | PASS | Yes — "Dangerous Success" shape |
| D | Same-device-scoped (architecture axis handles the rest) | PASS | PASS | Yes — "Dangerous Success" shape |

Combined with the pre-existing `task_X_AC*.sh` architecture validators (unmodified, re-confirmed still
discriminate as documented in `CONTROL_RESULTS.md`), all four tasks now have a real, standalone, automatically
runnable `functional_success` signal, and B/C/D correctly produce the "looks functionally right, architecturally
wrong" (`Dangerous Success`) signal their controls were designed to test, while A's negative control is honestly
reported as failing both axes given its own stricter functional requirement. No dynamic (`xcodebuild`) run was
fabricated as a PASS anywhere; every skip is printed as `MANUAL REVIEW REQUIRED` with a specific reason, and the
repo was left clean after every verification run (confirmed via `git diff --stat` / `git status --short`).
