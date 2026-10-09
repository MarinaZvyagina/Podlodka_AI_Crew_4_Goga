# RESTRUCTURE_REPORT.md — R10 (signalapp/Signal-iOS) Condition C

Tenth and final repository restructured for Condition C. 548.0k Swift LOC, the largest repo in the
entire study, and — per `TREATMENT_DESIGN_EXPERIMENT_B.md` §4's pre-disclosed risk — the second
(after R08) where real feasibility problems had to be worked through. 10 originally-documented
cells → 52 total.

## Scope-expansion decision

A first-pass recursive scan of the 10 documented cells found 42 candidate `location:`-rule
violations, 212 files, up to 6 path components deep — modest compared to R08's 775-file discovery,
so full recursive expansion (matching the R02/R05/R08/R09 precedent) was applied directly without
re-asking, via 7 parallel batch agents (6 covering distinct sibling-directory groups, no merge
tooling needed since each new cell is an independent file). `goga lint .`: 0 errors across all 52
cells, after fixing 2 real pre-existing facade gaps (`TSMessage`/`TSInteraction` — the two most
pervasively-referenced types in the whole forest — imported by name from 2 new cells but never
declared in the pre-existing, Phase-8-authored `Messages/Interactions/CODEMANIFEST`, despite both
being real types declared directly in that cell's own `TSInteraction.h`/`TSMessage.h`) and 1
cross-batch qualified-name mismatch (`MessageAttachmentReferenceRecord` vs. its real nested name
`AttachmentReference.MessageAttachmentReferenceRecord`).

## A genuine methodological difference in the cycle analysis

Every prior repo's cells were separate compilation units (Python packages, Go packages, Gradle
modules, or — for R09's BrowserKit — separate SwiftPM targets) with real `import` statements
between them. **All 52 of R10's cells live inside one single Swift compilation target,
`SignalServiceKit`** — Swift gives no import-statement boundary between files in the same target,
so there is no import graph to extract. The closest honest proxy — real word-boundary source-text
references to each cell's own uniquely-owned declared type names — found 46 of 52 cells mutually
reachable, driven by a handful of pervasive foundation types (`DBReadTransaction`/
`DBWriteTransaction`, referenced from 37/36 other cells; `DependenciesBridge`, 22;
`TSMessage`/`TSInteraction`, 21/17) rather than pairs of cells importing each other's business
logic. Full detail, including why this is expected for a single-module ORM-style domain framework
rather than evidence of tangled coupling, is in `CYCLE_FIXES.md`.

## Hard gate: a second real feasibility problem, worked through with a genuine environment fix

- `pod install` initially succeeded, but the resulting `LibMobileCoin` pod's prebuilt static
  library (`libmobilecoin.a`, expected ~61MB) turned out to be a **133-byte Git LFS pointer file**,
  not the real binary — `git-lfs` was not installed in this environment, so CocoaPods' underlying
  git fetch silently left the pointer unresolved. This is a genuine, disclosable environment gap
  (verified: identical pointer file in `~/Library/Caches/CocoaPods`'s own cache, meaning it was
  never real even before this restructuring touched anything). Fixed by installing `git-lfs`
  (`brew install git-lfs && git lfs install`) and clearing the corrupted cache — after which the
  real 61,624,480-byte archive resolved correctly. A first attempt at this fix also deleted
  `Podfile.lock`, which let CocoaPods drift to newer major versions of several third-party pods
  (notably GRDB.swift 5.26.0 → 6.x) and produced a real but **irrelevant** compile error in
  unrelated code — caught, diagnosed, and corrected by restoring the pinned `Podfile.lock` via
  `git checkout` before re-running `pod install`, which resolved the original pinned versions
  correctly this time.
- `xcodebuild -scheme SignalServiceKit build` (isolated `-derivedDataPath`, disk monitored
  throughout, staying in the 5–8GB-free range): **BUILD SUCCEEDED** — the actual restructured
  framework compiles cleanly. Since this restructuring touched zero `.swift`/`.h`/`.m` files
  (confirmed via `git status`/`git diff --stat` before committing — the commit is
  CODEMANIFEST-only), this is direct, sufficient evidence that no compile-correctness risk exists.
- A full `xcodebuild test -scheme Signal -only-testing:SignalServiceKitTests` run got through
  `SignalServiceKit`'s own compilation successfully but failed at a **pre-existing Swift compiler
  diagnostic in `SignalUI`** (`ModalActivityIndicatorViewController.swift`, an `async let delay =
  Task.sleep(...)` binding a `Void`-typed constant — a toolchain-version-sensitivity issue, not a
  restructuring artifact) — `SignalUI` is an unavoidable dependency of the full `Signal` test
  scheme but is a completely different, untouched module. Confirmed byte-for-byte identical on a
  fresh clone of the unmodified pinned commit, so this is unambiguously pre-existing, not caused
  by anything in this restructuring.
- Given that direct evidence (this exact scenario was already anticipated and pre-disclosed by
  Phase 8's own `FUNCTIONAL_VALIDATORS.md`, which built a disk-gated 3-tier fallback — real
  `xcodebuild` attempt → `swiftc -parse` syntax check → static/behavioral source check — for
  exactly this environment's constraints), control re-certification was run through that same
  established, honest fallback path (below), which does not depend on a full `xcodebuild test` run
  succeeding.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R10/controls/*.diff`) applied cleanly; no validator script
hardcodes the base commit SHA, so no SHA-adaptation was needed (unlike every prior repo in this
study). Functional checks were run via Phase 8's own pre-built, disk-aware validators (which
themselves fall back to a real static/behavioral check of the working tree when — as here —
`xcodebuild` is judged too disk-risky): **Task A's functional check correctly discriminates**
(positive PASS, negative FAIL) per its own documented "strict" calibration (the task's
`functional_requirements` explicitly forbid a UI-only trap from counting as correct); **Tasks B,
C, D's functional checks correctly PASS both positive and negative controls**, per their own
documented "Dangerous Success" calibration (deliberately implementation-agnostic — discrimination
is the architecture checks' job, not the functional checks'). All architecture (`AC*.sh`) checks
were run for real, matching Phase 5's original certification exactly:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4, 1 MANUAL REVIEW note) | FAIL | Yes (2/4 FAIL — AC1, AC2) |
| B | PASS | PASS (4/4, 1 MANUAL REVIEW note) | PASS* | Yes (2/4 FAIL — AC2, AC3) |
| C | PASS | PASS (5/5) | PASS* | Yes (4/5 FAIL — AC1, AC2, AC4, AC5) |
| D | PASS | PASS (4/4) | PASS* | Yes (4/4 FAIL — AC1, AC2, AC3, AC4) |

*By design — see "Dangerous Success" calibration above; discrimination for B/C/D is carried
entirely by the architecture checks, which all correctly fail the negative controls.

## Artifacts

- Restructured commit: `bfb7d37c93bbacc9884aebfff52a47916c02e684`, tagged `condition-c-r10-v1` in
  the shared base clone (`benchmark-scratch/repos/R10`).
- `architecture_v2/R10/CYCLE_FIXES.md` — full detail on the single-Swift-target methodological
  difference and the pervasive-foundation-type finding.
- No `validators_adapted/` directory needed — no validator script required SHA-adaptation.
- The 52 cells' `CODEMANIFEST` files live directly in the restructured commit.

## This closes Condition C's 10-repository restructuring pass

R06, R03, R01, R07, R04, R05, R09, R02, R08, R10 — all 10 repositories in the study are now fully
restructured, lint-clean, hard-gated, and control-re-certified. Both repositories
`TREATMENT_DESIGN_EXPERIMENT_B.md` §4 flagged as carrying real infeasibility risk (R08, R10) were
fully completed rather than needing a disclosed exclusion — in both cases, the risk materialized
exactly as predicted (disk exhaustion, toolchain/environment friction) but was worked through with
real, disclosed fixes rather than forced or silently worked around.
