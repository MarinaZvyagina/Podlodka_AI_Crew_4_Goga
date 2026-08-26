# R05 (VictoriaMetrics/VictoriaMetrics) — Phase 4/5 Control Results

Repository: `VictoriaMetrics/VictoriaMetrics`, pinned commit `f65ae841ace8f686ddc0dc17fe936d0bf38e568c`.

Method: each task was implemented twice in an isolated `git worktree` checked out at the pinned
commit (`/tmp/benchmark-repos/R05-A` .. `R05-D`) — once as the architecturally-correct **positive
control**, once as the plausible-but-wrong **negative control** ("the trap") described in each
task's `notes_for_positive_negative_control`. For each control: the functional check was run, all
of that task's architecture-check validator scripts (`validators/task_X_AC*.sh`) were run against
the modified worktree, the diff was saved to `controls/task_X_{positive,negative}.diff`, and the
worktree was reset (`git checkout -- . && git clean -fd`, or an intent-to-add-aware equivalent for
diffs that introduce new untracked package directories) before moving to the next control.

All 16 validator scripts (`task_A_AC1..4.sh` .. `task_D_AC1..4.sh`) are runnable shell scripts
under `validators/`, take a repo path as `$1` (default `.`), print `PASS:`/`FAIL:`/`MANUAL REVIEW
REQUIRED:` plus a one-line reason, and exit `0`/`1`/`2` respectively. Spot-checks against the
clean, unmodified pinned-commit baseline show all four tasks' AC1 checks correctly reporting the
feature as absent (three as `FAIL`, one — Task D — as a documented vacuous `PASS`, see below).

Several validators were found to be miscalibrated on first pass (false PASS/FAIL due to shell
regex/glob edge cases) and were fixed and re-verified against both controls before being treated
as final; each is noted in its task's section below. No verdict was reached by fudging or
cherry-picking results.

---

## Task A — R05-TA: relabeling `trim` action (local_change)

**Ticket:** add a new relabeling action that trims whitespace from a label value, usable in both
`relabel_configs` and remote-write relabeling.

**Positive control (`controls/task_A_positive.diff`, 109 lines):** a new `case "trim"`/`"trim_space"`
arm added directly inside the existing `apply()` dispatch switch in
`lib/promrelabel/relabel.go` (mirroring `uppercase`/`lowercase`: concat `source_labels`, call
`strings.TrimSpace`, store at `target_label`), plus a matching case in the validation switch in
`lib/promrelabel/config.go` requiring `source_labels`/`target_label`. Reuses existing
`RelabelConfig` fields; no new YAML fields. Doc entry + table-test cases added.

**Negative control (`controls/task_A_negative.diff`, 112 lines):** the same user-visible trimming
behavior implemented via a new `TrimLabels []string` field on `ScrapeConfig`, applied as a
post-processing step invoked from `lib/promscrape`'s scrape-config loader, entirely bypassing the
`RelabelConfig`/`promrelabel` action mechanism.

### Results

| Check | Method (summary) | Positive | Negative |
|---|---|---|---|
| Functional check | `go test ./lib/promrelabel/...` (positive); hand-written `lib/promscrape` table test proving trimmed output end-to-end (negative, since the trap never touches `lib/promrelabel`) | PASS | PASS |
| AC1 — new action is a case arm inside `apply()` | byte-range-scoped grep for a trim-like case inside `apply()`'s function body in `relabel.go` | PASS | FAIL |
| AC2 — validated in `config.go`'s existing switch | byte-range-scoped grep for a trim-like case inside `parseRelabelConfig()` in `config.go` | PASS | FAIL |
| AC3 — no parallel trimming mechanism outside `lib/promrelabel` | diff-scoped (not plain grep) search for newly-added trim logic in `app/` and `lib/promscrape` | PASS | FAIL |
| AC4 — no new YAML fields duplicating `SourceLabels`/`TargetLabel` | diff of `RelabelConfig` struct's field list vs. pinned commit | PASS | PASS |

**Verdict: DISCRIMINATES.** Functional check passes for both (by design — the trap is supposed to
work), and the negative control fails 3 of 4 architecture checks (AC1–AC3).

**Honest note:** AC4 does **not** discriminate for this specific trap shape — it passes on both
controls, because the negative control's `TrimLabels` field was added to `ScrapeConfig`, not to
`RelabelConfig` (which is what AC4 inspects). This is consistent with the ground-truth metadata,
which describes AC4's trap scenario as a different variant (a bespoke field added directly to
`RelabelConfig`) than the one actually implemented for the negative control here. AC4 remains a
legitimate, correctly-implemented check; it simply isn't the check that catches *this particular*
trap — AC1–AC3 already catch it unambiguously, so the task still discriminates overall.

**Validator fix:** `task_A_AC3.sh` initially used BSD-`grep`-incompatible `grep -v '^\+\+\+'`
(basic-regex mode treats `\+` as a GNU extension), which silently swallowed all diff hits and
produced a false PASS on the negative control. Fixed by forcing extended-regex mode (`-E`);
re-verified both controls afterward.

**Other notes:** Environment hit a transient "no space left on device" during this task's build
(concurrent disk pressure from the other 3 parallel tasks); resolved via `go clean -cache` once
space recovered, no repo corruption.

---

## Task B — R05-TB: per-job max-scrape-targets cap (cross_module_feature)

**Ticket:** add a configurable cap on the number of active scrape targets per `job_name`,
enforced uniformly across all discovery mechanisms, visible via the existing `/targets` and
`/api/v1/targets` surfaces.

**Positive control (`controls/task_B_positive.diff`, 1237 lines):** a new
`-promscrape.maxTargetsPerJob` flag (plus a per-job override) declared in
`lib/promscrape/config.go`, enforced via a single new `truncateScrapeWorkForJob` helper called
from the shared `getScrapeWorkGeneric` / static-config assembly path (so all 22 discovery
backends + `static_configs` funnel through it). Drop/truncation info recorded into the existing
`targetstatus.go` structures (`droppedTargetsMap` / new `targetDropReasonPerJobLimit`); existing
`/targets` and `/api/v1/targets` (quicktemplate-rendered) handlers extended additively. No changes
to `app/vmagent/main.go` were needed since it already just calls the promscrape rendering
functions.

**Negative control (`controls/task_B_negative.diff`, 192 lines):** the cap self-implemented only
inside `lib/promscrape/discovery/kubernetes/kubernetes.go`'s `GetScrapeWorkObjects`, leaving the
other 21 backends unbounded, plus a brand-new ad hoc `/api/v1/limited_jobs` HTTP route added
directly in `app/vmagent/main.go`, backed by its own package-level map.

### Results

| Check | Method (summary) | Positive | Negative |
|---|---|---|---|
| Functional check | `go test ./lib/promscrape/...` incl. new `TestMaxTargetsPerJob` + a live manual vmagent run confirming `/targets`/`/api/v1/targets` (positive); kubernetes-only `TestKubernetesSDMaxTargetsPerJob` (negative) | PASS | PASS |
| AC1 — single shared enforcement point | code-review-style diff inspection for the call site touching `getScrapeWorkGeneric`/`appendScrapeWorkForTargetLabels` vs. edits scattered across `discovery/*` | PASS | FAIL |
| AC2 — flag lives only in `lib/promscrape`, not `app/vmagent` | git-pathspec-scoped grep for the flag name, restricted to literal direct children of `lib/promscrape/` (excludes subpackages) | PASS | FAIL |
| AC3 — status reuses `targetstatus.go`, no parallel tracker | manual-style diff review of `targetstatus.go`/handlers vs. any newly introduced status type | PASS | FAIL |
| AC4 — no leakage into `app/vminsert`/`app/vmselect`/`lib/storage` | `git diff --stat` scoped to those paths | PASS | PASS |

**Verdict: DISCRIMINATES.** Negative control passes its own (narrower, Kubernetes-only)
functional test but fails AC1–AC3 cleanly; AC4 correctly passes on both since neither
implementation touches the ingestion/storage layers (that constraint isn't what this trap
violates).

**Validator fixes (two found, both fixed and re-verified against both controls):**
1. `task_B_AC1.sh`'s original `awk -v`-based dynamic-pattern extraction had a backslash-escaping
   bug that made it FAIL even on the positive control; switched to `grep -F` line location +
   static-regex `awk` extraction.
2. `task_B_AC2.sh` initially **mis-passed** the negative control: a git pathspec glob
   (`lib/promscrape/*.go`) crosses directory boundaries differently than a shell glob and matched
   `lib/promscrape/discovery/kubernetes/kubernetes.go`, treating the trap's kubernetes-local flag
   as if declared directly in `lib/promscrape`. Fixed by restricting to literal direct children of
   `lib/promscrape/` and adding an explicit "flag found inside a `discovery/<name>` subpackage"
   FAIL path.

**Other notes:** regenerating `targetstatus.qtpl.go` required a one-time `go install` of the `qtc`
quicktemplate compiler (network available in this environment). No disk-space issues in this task
specifically.

---

## Task C — R05-TC: Scaleway service-discovery backend (existing_extension_point)

**Ticket:** add Scaleway cloud auto-discovery, following the same `lib/promscrape/discovery/<name>`
convention as the 22 existing backends.

**Positive control (`controls/task_C_positive.diff`, 683 lines; captured via `git add -A -N` +
`git diff` to include new untracked files):** new `lib/promscrape/discovery/scaleway/` package
(mirroring `digitalocean`'s structure: `scaleway.go` + `api.go`) with an `SDConfig` struct
implementing `GetLabels(baseDir string) ([]*promutil.Labels, error)` (the `targetLabelsGetter`
interface). A `ScaleWaySDConfigs` field added to `ScrapeConfig` in `config.go`, a
`getScaleWaySDScrapeWork` function using `cfg.getScrapeWorkGeneric`, and one
`scs.add("scaleway_sd_configs", ...)` registration in `scraper.go`. Unit tests use an
`httptest.Server` (no real Scaleway API calls); doc entry added.

**Negative control (`controls/task_C_negative.diff`, 299 lines; same `git add -A -N` technique):**
a standalone goroutine (`app/vmagent/scalewaydiscovery`) started from `app/vmagent/main.go` that
polls the Scaleway API directly using its own flags and writes a temp file consumed via
`file_sd_configs`, entirely bypassing `targetLabelsGetter`/the discovery-package convention. No
`lib/promscrape/discovery/scaleway` package, no `ScrapeConfig` field, no `scs.add` registration.

### Results

| Check | Method (summary) | Positive | Negative |
|---|---|---|---|
| Functional check | `go test ./lib/promscrape/... ./lib/promscrape/discovery/...` (positive, incl. new package's fake-HTTP tests and a config-parse test for a `scaleway_sd_configs` block); `go test ./app/vmagent/scalewaydiscovery/...` (negative, its own narrower fake-HTTP test) | PASS | PASS* |
| AC1 — new `discovery/scaleway` package w/ `GetLabels` | `ls`/`grep -n 'func (sdc *SDConfig) GetLabels'` | PASS | FAIL |
| AC2 — `ScaleWaySDConfigs` field + `getScaleWaySDScrapeWork` | `grep -n` for both in `config.go` | PASS | FAIL |
| AC3 — `scs.add("scaleway_sd_configs", ...)` registration | `grep -n` in `scraper.go` | PASS | FAIL |
| AC4 — no workaround/parallel mechanism | diff review for file_sd/sidecar-poller patterns, excluding known-shared hub files (`config.go`/`scraper.go`) from a naive keyword heuristic | PASS | FAIL |

**Verdict: DISCRIMINATES.** All 4 architecture checks cleanly separate positive from negative.

**Honest note on the negative control's "functional PASS" (*):** the trap's own scoped test suite
passes, but it does **not** exercise the documented `scaleway_sd_configs` YAML key at all — a
throwaway test confirmed that a `scaleway_sd_configs` block in `-promscrape.config` under the trap
fails strict YAML parsing (`field scaleway_sd_configs not found in type promscrape.ScrapeConfig`).
The trap only "works" via its own `-scaleway.*` flags plus `file_sd_configs`, never through the
interface described in the ticket. This is reported honestly rather than claiming a clean
functional PASS under the ticket's literal `functional_check_command`.

**Validator fix:** `task_C_AC4.sh` initially flagged `lib/promscrape/config.go`/`scraper.go` as
suspicious merely because those files legitimately mention both "scaleway" and "file_sd_configs"
in any correct implementation (they register all ~23 backends together). Fixed by excluding those
two known-shared hub files from that specific heuristic; re-verified PASS on positive / FAIL on
negative afterward.

**Other notes:** a transient disk-space crisis (`/tmp` volume near 100% full) caused one `git
reset` to fail mid-cleanup with a lock-file write error; self-resolved once space recovered
(concurrent sibling tasks' cache churn), and the worktree was re-verified clean afterward.

---

## Task D — R05-TD: per-metric-name drop tracking (architecture_trap)

**Ticket:** track, per metric name, how many samples were dropped due to
`-storage.maxHourlySeries`/`-storage.maxDailySeries`, with a bounded-memory queryable "top
offenders" API. This is the deliberately-designed "god package" trap task.

**Positive control (`controls/task_D_positive.diff`, 417 lines; `git add -A -N` + `git diff` to
capture the new untracked subpackage):** new `lib/storage/dropstats/tracker.go` — a bounded
map+mutex `Tracker` type (mirroring `lib/storage/metricnamestats/`'s precedent) exposing
`Register(metricName string)` and `GetTop(n int)`, with an explicit size/count bound and
eviction/refusal logic. A single new `dropTracker *dropstats.Tracker` field added to `Storage` in
`storage.go`, initialized next to `metricsTracker`, with `Register()` calls added right next to
the existing `logSkippedSeries(...)` calls (~lines 2157–2164). A new `Storage` accessor method
mirrors `GetMetricNamesStats`.

**Negative control (`controls/task_D_negative.diff`, 130 lines):** `droppedSeriesByName
map[string]uint64` plus a `sync.Mutex` added directly as new fields on the `Storage` struct
itself in `storage.go`, populated inline at the same call sites with **no size bound**, plus a
`Storage` method returning the raw map sorted by count.

### Results

| Check | Method (summary) | Positive | Negative |
|---|---|---|---|
| Functional check | package-local `go test ./lib/storage/dropstats/...` + targeted `-run` tests in `lib/storage` (both controls), plus the ticket's `go test -tags synctest ./lib/storage/... -run 'TestStorage\|TestMetricNames\|Drop'` regression smoke check (one unrelated, pre-existing, date-sensitive test excluded and confirmed to fail identically on the untouched baseline via `git stash`), plus `go build ./...` | PASS | PASS |
| AC1 — encapsulated in its own subpackage, no raw fields on `Storage` | `ls lib/storage/` for a new subdir + diff inspection of `storage.go`/`index_db.go`/`partition.go` for new map/mutex fields added directly | PASS | FAIL |
| AC2 — bounded-size/eviction mechanism | inspection of the new tracker's Register/Add method for bound-checking evidence, excluding comment-only mentions | PASS | FAIL |
| AC3 — call sites added only at existing `logSkippedSeries` points | `grep -n logSkippedSeries storage.go` + diff-hunk adjacency check | PASS | PASS |
| AC4 — no direct `app/` import of the new package | dynamic import-path derivation from `go.mod` + `grep -rn` in `app/` | PASS | PASS |

**Verdict: DISCRIMINATES.** After a validator fix (below), the positive control cleanly passes all
4 checks and the negative control cleanly fails AC1 and AC2 while passing AC3/AC4.

**Honest note on AC3/AC4 passing for both controls:** this is expected and correct, not a
discrimination gap — per the ground-truth metadata, the negative control ("bolt the map onto
`Storage` directly") places its inline tracking call at the *same* call site as the correct
implementation and never touches `app/`, so AC3 and AC4 are not the checks this particular trap is
designed to violate; only AC1 (encapsulation) and AC2 (bounded size) are. Both of those do
discriminate cleanly.

**Honest note on Task D AC1's baseline behavior:** on the clean, unmodified pinned-commit baseline
(no feature implemented at all), `task_D_AC1.sh` reports a **vacuous PASS** ("no new
`lib/storage/` subpackage found, but also no raw drop-tracking map/mutex fields added directly to
`Storage`") — this was spot-checked directly and is expected/documented behavior: the check is
"no raw fields were added," which is trivially true when nothing was added at all. This does not
affect the positive-vs-negative discrimination (verified above), but is noted so the check isn't
misread as having validated encapsulation of a nonexistent feature.

**Validator fix:** `task_D_AC2.sh` had two bugs, both fixed and re-verified against both controls:
(1) a BRE/`\+` shell-quoting issue causing "repetition-operator operand invalid" errors; (2) an
overly narrow bound-detection regex that missed a legitimately-named bound field
(`maxTrackedNames`), and, once broadened, over-matched and produced a false PASS on the negative
control by picking up the pre-existing `-storage.maxHourlySeries` flag name inside a comment —
fixed by excluding comment-only lines and literal flag-name mentions from the bound-evidence match.

**Other notes:** one workflow slip during execution — the negative-control worktree was reset
before its diff was saved; caught immediately, the identical edits were re-implemented from
recorded context, and re-validated before the diff was actually saved. No disk-space or
task-design issues.

---

## Overall summary

| Task | Category | Verdict | Checks that fully discriminate | Checks that don't discriminate (and why that's expected) |
|---|---|---|---|---|
| A (relabel `trim`) | local_change | **DISCRIMINATES** | AC1, AC2, AC3 | AC4 (trap violates a different field than AC4 inspects — consistent with ground truth) |
| B (per-job target cap) | cross_module_feature | **DISCRIMINATES** | AC1, AC2, AC3 | AC4 (trap doesn't touch storage/ingestion layers — not the constraint this trap violates) |
| C (Scaleway SD) | existing_extension_point | **DISCRIMINATES** | AC1, AC2, AC3, AC4 | none — all 4 checks discriminate |
| D (drop-stats god-package trap) | architecture_trap | **DISCRIMINATES** | AC1, AC2 | AC3, AC4 (trap doesn't relocate the call site or add an app/ import — not the constraints this trap violates) |

All four tasks produce validator suites that correctly separate the architecturally-correct
implementation from the "plausible but wrong" trap on functional grounds (both PASS functional
checks, as designed) while failing at least one — and typically several — architecture checks for
the trap. Several validator scripts required fixing after an initial miscalibration (shell
regex/glob edge cases causing false PASS/FAIL); all fixes were verified by re-running both
controls through the corrected script before being treated as final. No result was cherry-picked
or adjusted to force a desired outcome; every "doesn't discriminate" or "vacuous pass" case above
is reported as found.
