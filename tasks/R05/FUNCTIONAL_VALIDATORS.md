# R05 (VictoriaMetrics/VictoriaMetrics) — Functional Validators

Repository: `VictoriaMetrics/VictoriaMetrics`, pinned commit `f65ae841ace8f686ddc0dc17fe936d0bf38e568c`.

This closes the gap left after Phase 4/5: each task's `functional_check_command` in
`metadata_X.yaml` was previously only a prose description. This phase adds a real,
standalone, runnable functional validator per task:

- `validators/task_A_functional.sh`, fixture `validators/fixtures/task_A_test.go`
- `validators/task_B_functional.sh`, fixture `validators/fixtures/task_B_test.go`
- `validators/task_C_functional.sh`, fixture `validators/fixtures/task_C_test.go`
- `validators/task_D_functional.sh`, fixture `validators/fixtures/task_D_test.go`

Each script takes a repo path as `$1` (default `.`): it copies its fixture `_test.go` file
into the appropriate package, runs `go test` scoped to a single test name, prints
`PASS: ...` / `FAIL: ...` (with the full `go test` output appended for diagnosis), exits
`0`/`1` accordingly, and removes the injected fixture file (and any test-generated data) via
a `trap ... EXIT` cleanup handler, so the target repo is left exactly as it was regardless of
whether the test passed, failed, or the script errored out early.

## Design principle: black-box, implementation-agnostic entry points

Per the task brief, every fixture is written against a stable entry point that *any*
correct implementation of the ticket must go through — not a helper specific to one
candidate's internal design:

- **Task A**: only `lib/promrelabel`'s public API (`ParseRelabelConfigsData`,
  `ParsedConfigs.Apply`, `SortLabels`, `LabelsToString`) — the exact API every relabel_configs
  consumer (scrape-time or remote-write) already uses.
- **Task B**: the new `-promscrape.*` flag is *discovered by name pattern* (must live under
  `-promscrape.` and mention both "target" and "job"), never hardcoded to
  `-promscrape.maxTargetsPerJob`. Everything else touched (`Config.parseData`,
  `Config.getStaticScrapeWork`, `droppedTargetsMap`, `WriteAPIV1Targets`) is pre-existing
  production code that predates any candidate's change.
- **Task C**: only `promscrape.CheckConfig()` plus the `-promscrape.config` flag — the same
  config-loading path used by `-promscrape.config.dryRun` in every VictoriaMetrics binary.
- **Task D**: the ticket explicitly leaves the query API "exact shape... up to you", so there
  is no fixed symbol to call. The fixture uses reflection: it force-enables any *new*
  (non-baseline) boolean `OpenOptions` field, induces drops for thousands of distinct,
  uniquely-prefixed metric names via the pre-existing `MustOpenStorage`/`AddRows`/
  `DebugFlush`/`UpdateMetrics` entry points, then scans every *new* (non-baseline) exported
  `*Storage` method's return value for a metric name paired with a positive drop count,
  regardless of what the method or its result type is called. The baseline method/field
  sets are hardcoded from the pinned commit (verified by direct source inspection), so
  "new" is well-defined and doesn't depend on any candidate's naming.

## Verification method

For each task: ran the validator against (1) the clean pinned-commit baseline (expect FAIL —
feature absent), (2) `controls/task_X_positive.diff` applied (expect PASS), and (3)
`controls/task_X_negative.diff` applied (result compared against `CONTROL_RESULTS.md`, with
divergences investigated and, where legitimate, explained below rather than "fixed" to force
agreement). The repo was reset (`git checkout -- . && git clean -fd`) between every run and
confirmed clean (`git status --porcelain` empty) after each task.

---

## Task A — relabeling `trim` action

**Checks:** a relabel_configs action named `trim` or `trim_space` is accepted by
`lib/promrelabel.ParseRelabelConfigsData`; applying it trims leading/trailing whitespace on
both a single `source_labels` entry and a multi-label, separator-joined concatenation
(mirroring `uppercase`/`lowercase`); and config validation rejects the action at load time
when `source_labels` or `target_label` is missing.

**Command:**
```
validators/task_A_functional.sh <repo_path>
# internally: go test ./lib/promrelabel/... -run '^TestFunctional_TrimRelabelAction$' -v
```

**Observed results:**

| Repo state | Result | Notes |
|---|---|---|
| Clean baseline | **FAIL** | `unknown action "trim_space"` (neither name recognized) — correct, feature absent |
| `task_A_positive.diff` applied | **PASS** | trims correctly, multi-label concat correct, missing-field configs rejected at load |
| `task_A_negative.diff` applied | **FAIL** | see note below |

**Divergence from `CONTROL_RESULTS.md` (documented, not a bug):** `CONTROL_RESULTS.md`
reports the negative control's *functional* check as PASS, but only by using a bespoke
`lib/promscrape` table test written specifically for that trap ("since the trap never
touches lib/promrelabel"). That is a per-implementation test, not a reusable
implementation-agnostic one. This validator instead tests the ticket's literal, stated
requirement — "a relabeling rule ... configured ... via source label(s) and a target
label", i.e. a `relabel_configs` action — through `lib/promrelabel`'s public API. The
negative control bypasses `relabel_configs` entirely (a `trim_labels` field on
`ScrapeConfig`, applied as a post-processing step outside promrelabel), so it correctly
does **not** satisfy this test: it doesn't implement the feature as the ticket actually
specifies it, only a functionally-similar side mechanism. This is considered a strict
improvement in rigor over the ad hoc Phase-5 check, not a miscalibration.

**Implementation-agnosticism:** does not assume which of "trim"/"trim_space" was chosen;
does not touch any internal helper (`concatLabelValues`, `relabelBufPool`, etc.) — only
`ParseRelabelConfigsData`/`ParsedConfigs.Apply` and other exported `promrelabel` functions.

---

## Task B — per-job max-scrape-targets cap

**Checks:** a `-promscrape.*` flag exists that caps active targets per `job_name`; a job
under the limit is unaffected; a job over the limit (via `static_configs`) is truncated to
exactly the limit; the excluded targets become visible through the *existing*
`droppedTargetsMap` / `WriteAPIV1Targets(state="dropped")` surface; and restoring the flag to
its documented default leaves jobs unaffected (unlimited).

**Command:**
```
validators/task_B_functional.sh <repo_path>
# internally: go test ./lib/promscrape/ -run '^TestFunctional_MaxTargetsPerJob$' -v
```

**Observed results:**

| Repo state | Result | Notes |
|---|---|---|
| Clean baseline | **FAIL** | no `-promscrape.*` flag found mentioning both "target" and "job" |
| `task_B_positive.diff` applied | **PASS** | `-promscrape.maxTargetsPerJob` discovered dynamically; under/over/default all correct; drop visible in `droppedTargetsMap`/API JSON |
| `task_B_negative.diff` applied | **FAIL** | see note below |

**Divergence from `CONTROL_RESULTS.md` (documented, not a bug):** `CONTROL_RESULTS.md`
reports the negative control's functional check as PASS via a Kubernetes-only test
(`TestKubernetesSDMaxTargetsPerJob`) scoped to the trap's own narrow flag
(`-promscrape.kubernetesSD.maxTargetsPerJob`). This validator's flag-discovery step *does*
find that flag (it matches the "target"+"job" name pattern) and sets it, but then tests it
against a `static_configs`-based job (a discovery-agnostic scenario, exactly what the ticket
requires — "regardless of which discovery mechanism produced the targets"). Since the trap
only truncates inside `lib/promscrape/discovery/kubernetes`, `static_configs` targets remain
completely unbounded under it, so the test correctly reports FAIL. This is a strict
improvement over the ad hoc per-backend Phase-5 check: it directly demonstrates the
functional gap the negative control's real-world limitation would cause (the cap silently
not applying to 21 of 22 discovery mechanisms plus `static_configs`), rather than validating
only the one mechanism the trap happens to cover.

**Implementation-agnosticism:** the flag name is discovered by pattern
(`^promscrape\..*target.*` + name contains "job" + "max"/"limit"), not hardcoded; truncation
is tested through pre-existing `Config.parseData`/`Config.getStaticScrapeWork`, not any
candidate-specific function like `truncateScrapeWorkForJob`.

---

## Task C — Scaleway service-discovery backend

**Checks:** a `scaleway_sd_configs` block inside a `scrape_configs` entry is accepted (not
rejected as an unknown field) by `promscrape.CheckConfig()` — the same strict, first-class
config-parsing path used by `-promscrape.config.dryRun` in every VictoriaMetrics binary.

**Command:**
```
validators/task_C_functional.sh <repo_path>
# internally: go test ./lib/promscrape/ -run '^TestFunctional_ScalewaySDConfigsIsFirstClass$' -v
```

**Observed results:**

| Repo state | Result | Notes |
|---|---|---|
| Clean baseline | **FAIL** | `field scaleway_sd_configs not found in type promscrape.ScrapeConfig` |
| `task_C_positive.diff` applied | **PASS** | minimal `scaleway_sd_configs: - {}` block parses cleanly |
| `task_C_negative.diff` applied | **FAIL** | same "field not found" error — matches `CONTROL_RESULTS.md`'s own honest note |

**Agreement with `CONTROL_RESULTS.md`:** the Phase-5 report already flagged, as an "honest
note", that the negative control's own scoped test never actually exercises the documented
`scaleway_sd_configs` YAML key and in fact fails strict parsing if you try. This validator
formalizes exactly that observation as an automated, reusable check, so Task C is the one
task where the rigorous implementation-agnostic functional check reproduces the same
verdict Phase 5 already anticipated (PASS/FAIL split cleanly matches the "honest note", not
the loose "PASS*" headline number).

**Implementation-agnosticism:** does not assume any Scaleway-specific sub-field name
(project ID, zone, etc.) — only that the top-level `scaleway_sd_configs` key itself is
recognized. A secondary, non-fatal check (`bearer_token`/`proxy_url`, the field names shared
by every other cloud backend's `promauth.HTTPClientConfig`/`proxy.URL` inline fields) is
logged as informational only, since the ticket doesn't fix Scaleway's own field names.

---

## Task D — per-metric-name drop tracking

**Checks:** after `-storage.maxHourlySeries` is exceeded while ingesting samples for many
distinct metric names, some newly-added, queryable mechanism reports per-metric-name drop
counts.

**Command:**
```
validators/task_D_functional.sh <repo_path>
# internally: go test ./lib/storage/ -run '^TestFunctional_PerMetricNameDropTracking$' -v
```

**Observed results:**

| Repo state | Result | Notes |
|---|---|---|
| Clean baseline | **FAIL** | zero new exported `*Storage` methods found beyond the pinned-commit baseline |
| `task_D_positive.diff` applied | **PASS** | reflection found `Storage.GetTopDroppedSeries`, matched an injected metric name with nonzero `DropCount` |
| `task_D_negative.diff` applied | **PASS** | reflection found `Storage.GetTopDroppedSeriesByName`, matched an injected metric name with nonzero `DropCount` |

**Agreement with `CONTROL_RESULTS.md`:** matches exactly — Phase 5 explicitly designed this
task so that *both* controls pass functionally (the trap is a purely architectural failure:
an unbounded `map[string]uint64` bolted directly onto the `Storage` struct, vs. a bounded,
encapsulated `dropstats.Tracker` subpackage). Task D is the one task in this set where a
`functional_success=PASS` + `architecture_success=FAIL` combination — i.e. "Dangerous
Success" — is expected and reproducible by this validator in combination with the existing
`task_D_AC1.sh`/`task_D_AC2.sh` architecture checks.

**Implementation-agnosticism:** this is the task with the least name-stability by design
(ticket: "exact API shape is up to you"), so the fixture never references a method or type
name directly. It hardcodes only the *baseline* (pre-existing) exported `Storage` method
names and `OpenOptions` field names (verified directly against the pinned commit's source),
and treats anything beyond that baseline as a candidate for the query API, checking its
*shape* (a metric-name string paired with a positive count, at any nesting depth) rather than
its name. Residual limitation: a zero-output "reset"-style new method is skipped for safety
(so it can't clobber tracked state before the real getter is tried), but a new method that
both mutates state *and* returns a value, sorted alphabetically before the real getter, could
in principle interfere — not observed with either control, noted here for transparency.

---

## Summary

| Task | Baseline | Positive | Negative | Matches `CONTROL_RESULTS.md`? |
|---|---|---|---|---|
| A (relabel `trim`) | FAIL | PASS | FAIL | Diverges (documented improvement — stricter, spec-literal check) |
| B (per-job target cap) | FAIL | PASS | FAIL | Diverges (documented improvement — discovery-agnostic check) |
| C (Scaleway SD) | FAIL | PASS | FAIL | Matches the report's own "honest note" |
| D (drop-stats trap) | FAIL | PASS | PASS | Matches exactly (by design — trap is architecture-only) |

All four validators were re-verified clean (`git status --porcelain` empty) in their
respective repos after every run.
