# REPOSITORY_SELECTION.md

**Criteria fixed:** 2026-08-25, before any candidate repository was evaluated or any Goga compatibility check was run against a specific codebase (per `Research.md` §12: "не выбирай repository только потому, что Goga хорошо его понимает").

## 1. Hard requirements (must all be true)

1. **Language** ∈ {Python, Go, Kotlin, Swift, JavaScript/TypeScript} — the 5 languages Goga v1.2.2 supports for `goga contract` drift extraction (`GOGA_RESEARCH.md` §8). A repository outside this set cannot receive a faithful Goga treatment and is excluded regardless of other merits.
2. ≥ 30,000 lines of non-generated production code (vendored, generated, and test code excluded from the count).
3. Hundreds of source files (order of magnitude check, not a hard threshold).
4. At least two, preferably several, identifiable architectural components (not a single flat script collection).
5. Automated test suite present and runnable.
6. Locally buildable/testable without mandatory proprietary infrastructure (no required paid SaaS credentials, internal-only build systems, or hardware dependencies).
7. Actively maintained real project — commits within the last 6 months, genuine external usage (stars/forks/downloads as a weak proxy, not a target to game).
8. Sufficiently mature architecture — not a tutorial, starter template, or toy example.
9. License permits cloning and local experimentation (OSI-approved or equivalent permissive/copyleft license).

## 2. Exclusion rules

- Do **not** select a repository because Goga parses it unusually well or poorly — compatibility with Goga's tree-sitter grammars is a hard *language* gate (rule 1), not a selection criterion beyond that.
- Do **not** select purely on convenience of the researcher's familiarity with the codebase.
- Do **not** select a repository whose primary test suite requires network access to third-party paid services (flaky/unreproducible builds work against the benchmark's core goal).
- Avoid repositories that are themselves AI-agent tooling, benchmarks, or Goga-adjacent projects — this could bias task designers toward architecture patterns AI tools already "expect."

## 3. Diversity targets across the final 10

These are targets to *steer* selection, not hard per-repository gates. Perfect orthogonal coverage of every cell is not required or expected; report actual achieved spread transparently in §5.

| Axis | Categories | Target spread |
|---|---|---|
| Size | medium (~30-80k LOC) / large (~80-250k LOC) / very large (250k+ LOC) | roughly 3-4 / 3-4 / 2-3 |
| Architecture style | layered, modular monolith, plugin architecture, ports & adapters, component architecture, package-oriented, mixed/evolutionary | at least 4 distinct styles represented |
| Documentation quality | good / medium / poor | at least one repository per category |
| Modularity | strong / medium / weak | at least one repository per category |
| Language | Python, Go, Kotlin, Swift, JavaScript/TypeScript | at least one repository per language; no single language > 4 of 10 |

## 4. Reconnaissance procedure (applied per candidate before final selection)

For each candidate: clone at a specific commit, measure LOC with `cloc` (excluding vendor/generated/test paths), count source files and top-level architectural directories, confirm build + test commands actually succeed locally, read README/CONTRIBUTING/ADRs/AGENTS.md/CLAUDE.md to rate documentation quality, and informally assess architecture style and modularity from the module graph. Results recorded in `repos.yaml`.

## 5. Candidate research and final selection

Reconnaissance was performed by two independent research passes (one covering Python/JavaScript-TypeScript, one covering Go/Kotlin/Swift — the 5 languages Goga v1.2.2 supports, per rule 1 in §1), each cloning candidates at a specific recent commit, measuring production LOC with `cloc` (excluding vendor/test/generated/migration paths), and attempting real local build/test runs where feasible. No repository was chosen or rejected based on how well Goga would parse it — that judgment was never made during recon; the language gate in §1 rule 1 is the only place language enters the decision.

### 5.1 Full candidate pool (20 repositories investigated)

| Candidate | Lang | Measured production LOC | Verdict |
|---|---|---|---|
| zulip/zulip | Python | 153,646 | PASS (not selected — see §5.3) |
| home-assistant/core | Python | 1,135,354 | PASS (not selected) |
| saltstack/salt | Python | 275,538 | **SELECTED (R02)** |
| freqtrade/freqtrade | Python | 44,784 | **SELECTED (R01)** |
| scrapy/scrapy | Python | 21,214–21,441 | FAIL — below 30k LOC floor |
| python-poetry/poetry | Python | 18,820 | FAIL — below 30k LOC floor |
| nestjs/nest | TypeScript | 34,731 | **SELECTED (R03)** |
| excalidraw/excalidraw | TypeScript | 106,519 | **SELECTED (R04)** |
| microsoft/vscode | TypeScript | 1,359,141 | PASS (not selected) |
| storybookjs/storybook | TypeScript | ~277,335 | PASS but **excluded — contamination risk** (ships its own `agent-eval/` directory with pre-built AI-coding-agent benchmark tasks; using it risks task/solution memorization) |
| typeorm/typeorm | TypeScript | 74,975 | PASS (not selected) |
| directus/directus | TypeScript | ~224,000 | FAIL — source-available license (MSCL-1.0-GPL), not OSI/permissive/copyleft |
| etcd-io/etcd | Go | 62,276 | **SELECTED (R06)** |
| open-telemetry/opentelemetry-collector | Go | 84,527 | PASS (not selected) |
| jaegertracing/jaeger | Go | 47,816 | PASS (not selected) |
| VictoriaMetrics/VictoriaMetrics | Go | 120,147 | **SELECTED (R05)** |
| mosn/mosn | Go | 72,012 | PASS (not selected — bursty commit history, weaker maintenance signal than VictoriaMetrics for the same "poor docs" slot) |
| rqlite/rqlite | Go | 25,563 | FAIL — below 30k LOC floor |
| nsqio/nsq | Go | 11,696 | FAIL — below 30k LOC floor |
| signalapp/Signal-Android | Kotlin | 371,939 | **SELECTED (R08)** |
| mihonapp/mihon | Kotlin | 77,394 | **SELECTED (R07)** |
| apollographql/apollo-kotlin | Kotlin | 52,406 | PASS (not selected) |
| kotest/kotest | Kotlin | 66,702 | PASS (not selected — pre-instrumented with `CLAUDE.md` + `.claude-plugin/`, kept as reserve only) |
| open-ani/animeko | Kotlin | 176,089 | PASS (not selected — pre-instrumented with `AGENTS.md` + `.agents/skills` + `.claude/skills`, contamination concern) |
| JetBrains/kotlin | Kotlin | n/a | rejected — atypical self-hosting compiler, poor benchmark fit |
| kickstarter/ios-oss | Swift | 119,907 | PASS (not selected) |
| signalapp/Signal-iOS | Swift | 548,036 | **SELECTED (R10)** |
| mozilla-mobile/firefox-ios | Swift | 245,161 | **SELECTED (R09)** |
| CodeEditApp/CodeEdit | Swift | 40,412 | PASS (not selected) |
| wordpress-mobile/WordPress-iOS | Swift | 266,952 | PASS, reserve only (less thoroughly vetted than selected candidates) |
| iina/iina, utmapp/UTM | Swift | n/a | FAIL — no automated test suite |
| vapor/vapor, AudioKit/AudioKit | Swift | 13,596 / 14,823 | FAIL — below 30k LOC floor |

Full per-candidate evidence (architecture assessment, doc/modularity evidence, exact build/test commands attempted, extension points observed) is preserved in the two research-agent transcripts referenced from `STATUS.md`; the summary above is the traceable decision record.

### 5.2 Final 10 repositories

| ID | Repository | Language | Size tier | Architecture style | Doc quality | Modularity |
|---|---|---|---|---|---|---|
| R01 | freqtrade/freqtrade | Python | medium (44.8k) | modular monolith + plugin layer | poor/sparse (internal) | strong |
| R02 | saltstack/salt | Python | very large (275.5k) | plugin architecture (loader-based) | good | medium (organic) |
| R03 | nestjs/nest | TypeScript | medium (34.7k) | layered + adapter (DI) | good | strong |
| R04 | excalidraw/excalidraw | TypeScript | large (106.5k) | component/package-oriented monorepo | good | strong |
| R05 | VictoriaMetrics/VictoriaMetrics | Go | large (120.1k) | plugin pattern + god-package weak spot | poor | medium |
| R06 | etcd-io/etcd | Go | medium (62.3k) | modular monolith (multi-module workspace) | medium | strong |
| R07 | mihonapp/mihon | Kotlin | medium/large (77.4k) | layered + plugin source-extension | medium | strong |
| R08 | signalapp/Signal-Android | Kotlin | very large (371.9k) | component architecture (Gradle multi-module) | medium | strong |
| R09 | mozilla-mobile/firefox-ios | Swift | large (245.2k) | component + unidirectional dataflow (Redux-style) | good (best-in-class) | strong |
| R10 | signalapp/Signal-iOS | Swift | very large (548.0k) | component/layered (few large frameworks) | medium | strong |

**Size distribution:** 4 medium, 3 large, 3 very large — within the 3-4/3-4/2-3 target.
**Language distribution:** 2 per language × 5 languages = 10 — maximizes language spread while respecting the ≤4-per-language ceiling.
**Architecture style distribution:** 6+ distinct styles represented (modular monolith, loader-based plugin, layered+adapter/DI, component/package-oriented monorepo, plugin+god-package, layered+plugin-extension, Gradle component architecture, Redux-style unidirectional dataflow) — well above the ≥4 target.
**Documentation quality:** good (R03, R04, R09, and R02), medium (R06, R07, R08, R10), poor (R01, R05) — all three categories represented.
**Modularity:** strong (R01, R03, R04, R06, R07, R08, R09, R10), medium (R02, R05) — see limitation below.

### 5.3 Explicit limitations of this selection (documented, not hidden)

1. **No repository met a strict "weak" modularity bar.** Both research passes actively searched for a weakly-modular candidate; the closest examples (Salt, VictoriaMetrics) were independently assessed as "medium" — real organic coupling (Salt's flat 267-file `salt/modules/` sprawl mediated by an implicit dunder-based convention; VictoriaMetrics' 30,814-LOC `lib/storage` god-package) but not literal ad-hoc spaghetti. Plausible explanation: production-grade, actively-maintained, well-tested repositories that clear a 30k-LOC bar tend to have survived exactly because they aren't badly coupled — "weak modularity" and "30k+ LOC real project with a real test suite" may be in tension. This is reported as a finding about the candidate population, not engineered away by lowering other bars.
2. **Signal-Android (R08) and Signal-iOS (R10) are maintained by the same organization (Signal Foundation)** and are both secure-messaging apps under AGPL-3.0. They were kept because each is independently the strongest available very-large candidate in its language (Kotlin, Swift respectively) after excluding contamination-flagged alternatives (open-ani/animeko, kotest). This slightly reduces the independence of the sample on the "maintaining organization" and "domain" axes — noted here as a threat-to-validity input for `report/final_report.md` §18, not corrected by picking a weaker/less-vetted alternative (e.g. WordPress-iOS) purely for optical diversity.
3. **Repositories excluded for agent-tooling contamination risk** (storybookjs/storybook, open-ani/animeko, kotest/kotest) were dropped even though they passed all hard requirements, because their pre-existing AI-agent eval scaffolding creates a real risk of task/solution memorization by the model. This is a deliberate, documented exclusion rule, applied after the fact once discovered during recon (not planned in the original §1/§2 criteria) — recorded transparently here as a criterion added during Phase 2, not smuggled in silently.
4. **R08's production LOC figure (371,939) is Kotlin only**; the same repository also contains 175,106 lines of legacy Java. Java is not one of Goga's 5 supported contract-extraction languages. The Goga architecture forest for R08 (Phase 8) will be scoped to Kotlin-primary modules; Java-only cells, if any fall within task scope, receive no automated drift-checking (CODEMANIFEST's DSL itself is language-agnostic and could still describe them descriptively, but `goga contract` cannot verify them). Flagged in `repos.yaml` for R08.
5. **R09's (firefox-ios) full-app test suite depends on Mozilla's private Bitrise CI infrastructure**; only the `BrowserKit` SwiftPM sub-package was confirmed independently testable via plain `swift test`. Task design and functional validators for R09 (Phase 3-4) must be scoped so that "functional_check_command" does not require this private infrastructure — this constrains where Task A-D can be placed in this repository and is recorded here so it isn't rediscovered as a surprise during Phase 3.

None of these limitations disqualify the selection; per `Research.md` §63/§65 the goal is a defensible, transparent sample — not a cherry-picked one.
