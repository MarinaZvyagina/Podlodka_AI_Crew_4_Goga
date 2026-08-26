# PILOT_REPORT.md — Phase 6

**Purpose:** infrastructure-only pilot per `Research.md` §62/§63. Confirms that (1) a real, autonomous Claude Code agent can be launched non-interactively against a clean isolated worktree of a pinned commit, (2) it can complete a real task end-to-end with no manual rescue, (3) artifacts (diff, JSON result with tokens/cost/turns/duration) are capturable, and (4) the Phase 4/5 validator scripts produce correct, actionable verdicts against genuine (not hand-authored) LLM output.

**These 4 runs are NOT part of the 800-run main sample** and must not be pooled with it, per `Research.md` §63.

## Scope

| Cell | Repo | Task | Condition | Reps |
|---|---|---|---|---|
| R01-TA | freqtrade/freqtrade | Task A (Local Change) | Baseline | 2 |
| R06-TA | etcd-io/etcd | Task A (Local Change) | Baseline | 2 |

Only the **Baseline** condition was piloted. Per `Research.md`'s own phase ordering (§62), Goga architecture-forest preparation is Phase 8 — after protocol freeze (Phase 7), which comes after this pilot (Phase 6). No real Goga treatment artifacts exist yet, so there is nothing authentic to pilot for Condition B at this point; testing it here with a placeholder would not be a meaningful infrastructure test and was deliberately skipped rather than faked.

## Execution mechanics (what this proves)

Each run:
1. Started from a fresh `git worktree` checked out at the exact pinned commit (`936f28e28cbcd4e9e146cbc076c54933517a92eb` for R01, `23a4e406a2e70a807486b4c40a9e24da493886bf` for R06) — clean-room execution confirmed (`PROTOCOL.md` §10).
2. Invoked `claude -p "<task prompt>" --output-format json --permission-mode bypassPermissions --model sonnet --no-session-persistence --max-budget-usd 3` — a real, fully autonomous, non-interactive session with no human intervention (`PROTOCOL.md` §11).
3. Produced a real code diff plus a structured JSON result containing `duration_ms`, `num_turns`, `total_cost_usd`, and token usage — confirming the metrics pipeline in `PROTOCOL.md` §17 is capturable exactly as designed.
4. Was validated by re-running the actual Phase 4 validator scripts (`tasks/R0X/validators/task_A_*.sh`) against the real diff, not a hand-authored one — the first time these scripts have been tested against organic model output rather than the Phase 5 hand-written positive/negative controls.

## Results

### R01-TA-01 (freqtrade, rep 1)
- 57 turns, 667.6s, $1.56.
- Solution: `_validate_available_capital()`, checking the **raw, pre-schema-default** config dict — correctly avoiding a false positive from `tradable_balance_ratio`'s schema default (0.99). Also fixed 3 existing tests whose fixtures had genuinely combined both settings.
- Validators: **5/5 architecture checks PASS** (including AC5, confirmed via an actual `pytest tests/test_wallets.py` run inside the validator).

### R01-TA-02 (freqtrade, rep 2)
- 21 turns, 281.8s, $0.73.
- Solution: `_validate_capital_settings()`, checking mere key **presence** in the processed config dict (post-defaulting).
- Validators: 4/5 architecture checks auto-PASS; AC5 flagged `MANUAL REVIEW REQUIRED`.
- **Manual follow-up (performed by the orchestrating session, not simulated):** built a venv, installed dev requirements, ran `pytest tests/test_wallets.py::test_get_starting_balance` — **4 of 8 parametrized cases FAIL** with the new `ConfigurationError`, because `default_conf`'s test fixture always includes `tradable_balance_ratio: 0.99` (`tests/conftest.py:607`), and `FreqtradeBot.__init__` calls `validate_config_consistency()` (`freqtradebot.py:103`). This is a genuine, empirically confirmed regression — this run introduced the exact "presence-vs-explicitly-set" bug that rep 1 discovered and avoided.

**R01-TA-01 vs R01-TA-02 is the single most useful pilot finding**: two independent sessions of the literal same task, same repository, same commit, same model, produced two different architectural approaches to "how do I know the user explicitly set this config key" — one correct, one subtly wrong in a way that only surfaces when the existing test suite is actually run. This is a live, small-scale instance of exactly the "architectural instability across repetitions" phenomenon `Research.md` §58 calls one of the most illustrative possible pieces of evidence for the main study, and it also validates that `existing_test_regressions` (a metric named in `PROTOCOL.md` §17) is a real, catchable signal, not a theoretical one.

### R06-TA-01 (etcd, rep 1)
- 60 turns, 295.8s, $2.27.
- Solution: validation in `authStore.UserAdd`/`UserChangePassword` (`server/auth/store.go`) — the required existing abstraction — **plus** an additional defense-in-depth check in `EtcdServer.UserAdd` (`server/etcdserver/v3_server.go`) to reject before the bcrypt-hashing step.
- Validators: 4/5 auto-PASS; AC4 flagged `MANUAL REVIEW REQUIRED` (no test sub-name obviously names the passwordless case) — manually confirmed PASS by reading the test output (`TestUserAddWithEmptyPassword`/`TestUserChangePasswordWithEmptyPassword` present and passing, passwordless path untouched).

### R06-TA-02 (etcd, rep 2)
- 48 turns, 283.7s, $1.76.
- Solution: validation in `authStore.UserAdd`/`UserChangePassword` only (no extra defense-in-depth layer).
- Validators: 4/5 auto-PASS, same AC4 manual-review flag, same manual confirmation.

**R06's two reps landed on the same core architectural decision** (the domain-layer `authStore`, matching `required_existing_abstractions` in `metadata_A.yaml`) — a positive stability signal, with rep 1 simply adding one extra layer of defense that rep 2 didn't. This contrasts instructively with R01's divergence above: not every task shows large repetition-to-repetition variance even at n=2, which is itself worth remembering before the main study — variance should be measured, not assumed.

## What this pilot confirms about infrastructure readiness

1. **Agent launch works**: `claude -p ... --permission-mode bypassPermissions` runs a real, unattended, tool-using session to completion without hanging or requiring interactive approval.
2. **Session isolation works**: each run got a fresh `git worktree`; no cross-contamination observed (verified via `git status` before/after).
3. **Metrics collection works**: JSON output directly provides `duration_ms`, `num_turns`, `total_cost_usd`, `usage.{input,output,cache_read,cache_creation}_tokens`, `session_id`, and `modelUsage` per model — covering most of `PROTOCOL.md` §17's "agent activity" and "time" metrics natively, without needing to instrument the agent separately.
4. **Validators work against real model output**: all 20 validator invocations across the 4 runs produced sensible verdicts (PASS, or an honest `MANUAL REVIEW REQUIRED` rather than a guessed answer) — none crashed, none gave an obviously wrong verdict on inspection.
5. **A real, reproducible functional regression was caught** by combining an honest "manual review required" validator flag with actual follow-up test execution — proving the "no silent false pass" design principle from Phase 4/5 survives contact with genuine LLM output, not just hand-authored diffs.

## Known gaps / follow-ups for Phase 7 (protocol freeze) and beyond

1. **Cost per run varies 3× within the same task and repo** ($0.73–$2.27 observed here) — `experiment.yaml`'s cost tracking (§44/§45 of `Research.md`) must record this per-run, not assume a flat rate; 800 runs at this range could cost roughly $600-$1,800 in API spend alone (Baseline only; Goga condition adds its own setup cost separately) — worth budgeting explicitly before Phase 10.
2. **`--max-budget-usd 3` was set defensively** for this pilot; none of the 4 runs came close to it, but this cap should be a fixed, documented parameter in `experiment.yaml` for the main study, not an ad hoc pilot choice.
3. **`--model sonnet` was used as an alias**, not a pinned dated model identifier — `PROTOCOL.md` §6 requires a pinned model version for the main study; this must be resolved (exact model string, e.g. via `--model claude-sonnet-5` or a more specific dated identifier if the CLI exposes one) before Phase 7 freeze.
4. **Functional-check automation gap**: the pilot's AC5/AC4 manual-review fallbacks both turned out to require a real `pytest`/`go test` run to resolve conclusively (not just static analysis) — for the 800-run execution, the harness should automatically run the relevant test file(s) after every run rather than relying on a human (or a downstream LLM judge) to resolve `MANUAL REVIEW REQUIRED` flags, since this pilot session had to do it by hand.
5. **JDK version note carries over unchanged from Phase 5** (see `experiment.yaml`): not exercised in this pilot (Python/Go only), but still an open action item for Phase 6-continued if a Kotlin pilot cell is added later.

## Cleanup

All 4 pilot worktrees (`/tmp/pilot-R01-TA-01`, `/tmp/pilot-R01-TA-02`, `/tmp/pilot-R06-TA-01`, `/tmp/pilot-R06-TA-02`) were removed via `git worktree remove` after this report was written; raw JSON logs preserved at `/tmp/pilot-logs/*.json` and also copied into this `pilot/` directory for durability (see `pilot/raw/`).
