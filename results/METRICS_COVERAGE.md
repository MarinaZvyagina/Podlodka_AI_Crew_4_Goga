# Metrics coverage — planned (`experiment.yaml`) vs actually captured (Phase 10 harness)

`experiment.yaml`'s `metrics` section (reproduced from `Research.md` §35-45) is an aspirational
full schema. `scripts/execute_run.py` did not implement all of it — this is disclosed here
rather than silently presenting `results/cells.csv` as if it did, per this project's own
no-silent-gaps rule (see `PROTOCOL.md` "Protocol amendments").

Legend: **captured** = in `results/analysis_set.csv` / `results/cells.csv` today. **derivable**
= not computed, but the raw artifact needed to compute it later is preserved per-run under
`runs/<run_id>/` (`git.diff`, `git.status`, `agent.log`, `changed_files.txt`) — a follow-up pass
could add it without re-running anything. **not captured** = the raw data needed doesn't exist
(would have required instrumenting the harness before execution).

| Category | Metric | Status |
|---|---|---|
| correctness | functional_success, full_architecture_conformance, architecture_conformance_rate, dangerous_success | **captured** |
| correctness | existing_test_regressions | not captured (functional validators check task-specific behavior, not a full pre-existing-suite regression sweep) |
| agent_activity | input_tokens, output_tokens, total_tokens | **captured** |
| agent_activity | tool_calls | **captured**, as `tool_calls_num_turns` — Claude Code's own turn count, a proxy, not a raw tool-invocation count |
| agent_activity | shell_commands, searches, file_reads, unique_files_read | derivable from `agent.log` (full JSON transcript preserved per run), not parsed |
| change | files_added / files_modified / files_deleted | derivable from `git.status` (preserved per run); only the aggregate `files_changed` count was captured |
| change | lines_added, lines_deleted | derivable from `git.diff` (preserved per run, standard unified diff, `--numstat`-parseable) |
| change | modules_touched, dependencies_added, dependencies_removed | derivable from `git.diff`/`changed_files.txt` with per-repo module-boundary knowledge; not parsed |
| time | agent_time | **captured** (`duration_ms`) |
| time | build_time, test_time, validation_time | not captured as separate timings — validators ran within a single wall-clock call, not individually timed |
| architecture_discovery_cost | files_read_before_first_edit, unique_files_read_before_first_edit, searches_before_first_edit, tool_calls_before_first_edit, tokens_before_first_edit, seconds_before_first_edit | derivable from `agent.log` (would need to locate the first file-write tool call in the transcript and count everything before it); not parsed |
| stability_per_cell | functional_success_rate, full_architecture_conformance_rate, dangerous_success_rate, acr_mean/median/sd/iqr/min/max | **captured** (`results/cells.csv`) |
| stability_per_cell | dominant_strategy_share, module_jaccard_mean/median | not captured — would require clustering the 10 repetitions' diffs by which files/modules they touched; not implemented |
| stability_per_cell | extension_point_usage_rate (task type C) | not captured — would require a task-C-specific check of whether the solution used the intended extension point vs a parallel implementation |
| cost | goga_setup_* (initial generation time, manual review/correction time and count, artifact size, maintenance steps) | **captured separately**, not per-run — see `architecture/R0X/SETUP_COST.md` per repository (Phase 8 artifacts), not part of `runs.csv`/`cells.csv` |

## Bottom line for Phase 13/14

The primary metric (**Dangerous Success Rate**, `PROTOCOL.md` §18) and its required aggregation
(§14: per-cell rates with repeated-observations-aware CIs, not naive pooled proportions) are
fully captured and computed in `results/cells.csv` / `results/task_comparison.csv`. Several
*secondary* metrics from the original full wishlist are not — some are recoverable in a later
pass from preserved raw artifacts (marked "derivable" above) if the analysis benefits from them;
others (dominant strategy share, module Jaccard stability, extension-point usage rate, granular
architecture-discovery-cost timing) were never instrumented and are not recoverable. This is a
real scope limitation of the executed harness relative to the original plan and should be listed
in the final report's threats-to-validity section (`PROTOCOL.md` §20).
