# Phase 13 -- Statistical Analysis

Formal significance testing on the primary 800-run study (Condition A/Baseline vs. Condition B/Goga), per `PROTOCOL.md` Section 14. This is descriptive analysis of already-frozen, already-validated data (`results/analysis_set.csv`, 800/800 VALID) -- no runs are re-executed or re-scored here. The primary unit of inference throughout is the task-level cell (10 repetitions aggregated into one rate/mean per `repository x task x condition`), never the 800 raw runs treated as independent observations, per the project's own no-pseudoreplication rule (`PROTOCOL.md` Section 14 / `Research.md` Section 68).

## 1. Primary metric -- Dangerous Success Rate

`dangerous_success = functional_success AND NOT full_architecture_conformance` (`PROTOCOL.md` Section 18) -- the agent's change worked, but violated the codebase's real architectural boundaries in a way that would bite later. Lower is better.

### Pooled (all 40 cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 0.2925  |  Goga mean: 0.2825  |  Mean delta (Goga - Baseline): -0.0100  (95% bootstrap CI [-0.0425, 0.0200], 20000 resamples)
Direction: Goga > Baseline in 7/40 cells, Goga < Baseline in 8/40, tied in 25/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 222.00, p = 0.6922; matched-pairs rank-biserial r = -0.217 (n_ranked=15)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 25 tied cells as a robustness check): W = 47.00, p = 0.4561 (n=15)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 8/15 favor Goga, p = 1.0000, 95% CI on proportion [0.266, 0.787]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = -0.612, p = 0.5438

#### Per-task-type breakdown -- dangerous_success_rate

| Task type | n cells | Baseline mean | Goga mean | Mean delta | Goga<Base | Goga>Base | Tied |
|---|---|---|---|---|---|---|---|
| architecture_trap | 10 | 0.2100 | 0.2100 | -0.0000 | 2 | 2 | 6 |
| cross_module_feature | 10 | 0.2400 | 0.1900 | -0.0500 | 2 | 1 | 7 |
| existing_extension_point | 10 | 0.3300 | 0.3400 | +0.0100 | 1 | 2 | 7 |
| local_change | 10 | 0.3900 | 0.3900 | -0.0000 | 3 | 2 | 5 |

n=10 cells per task type is too small for a standalone significance test to be trustworthy (a single flipped cell swings the result); shown descriptively only, to see whether any one task type is driving the pooled 40-cell result.

### Secondary run-level model (respects repetition clustering)

#### Dangerous Success -- GEE logistic regression (cluster-robust by task cell)

Unadjusted (`dangerous_success ~ condition`): OR(Goga vs Baseline) = 0.952 (95% CI [0.816, 1.111]), Wald p = 0.5352
Adjusted for repository + task_type (`dangerous_success ~ condition + repository + task_type`): OR(Goga vs Baseline) = 0.940 (95% CI [0.774, 1.142]), Wald p = 0.5334

## 2. Secondary binary outcomes

### Functional Success Rate (pooled, 40 cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 0.4800  |  Goga mean: 0.4400  |  Mean delta (Goga - Baseline): -0.0400  (95% bootstrap CI [-0.0700, -0.0125], 20000 resamples)
Direction: Goga > Baseline in 4/40 cells, Goga < Baseline in 13/40, tied in 23/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 119.50, p = 0.0220; matched-pairs rank-biserial r = -0.641 (n_ranked=17)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 23 tied cells as a robustness check): W = 27.50, p = 0.0175 (n=17)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 13/17 favor Goga, p = 0.0490, 95% CI on proportion [0.501, 0.932]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = -2.648, p = 0.0116

#### Per-task-type breakdown -- functional_success_rate

| Task type | n cells | Baseline mean | Goga mean | Mean delta | Goga<Base | Goga>Base | Tied |
|---|---|---|---|---|---|---|---|
| architecture_trap | 10 | 0.5200 | 0.4400 | -0.0800 | 5 | 0 | 5 |
| cross_module_feature | 10 | 0.2600 | 0.2200 | -0.0400 | 2 | 1 | 7 |
| existing_extension_point | 10 | 0.4400 | 0.4200 | -0.0200 | 3 | 2 | 5 |
| local_change | 10 | 0.7000 | 0.6800 | -0.0200 | 3 | 1 | 6 |

n=10 cells per task type is too small for a standalone significance test to be trustworthy (a single flipped cell swings the result); shown descriptively only, to see whether any one task type is driving the pooled 40-cell result.

#### Functional Success -- GEE logistic regression (cluster-robust by task cell)

Unadjusted (`functional_success ~ condition`): OR(Goga vs Baseline) = 0.851 (95% CI [0.757, 0.957]), Wald p = 0.0068
Adjusted for repository + task_type (`functional_success ~ condition + repository + task_type`): OR(Goga vs Baseline) = 0.817 (95% CI [0.704, 0.948]), Wald p = 0.0076

### Full Architecture Conformance Rate (pooled, 40 cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 0.2975  |  Goga mean: 0.2400  |  Mean delta (Goga - Baseline): -0.0575  (95% bootstrap CI [-0.1225, -0.0075], 20000 resamples)
Direction: Goga > Baseline in 2/40 cells, Goga < Baseline in 9/40, tied in 29/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 67.00, p = 0.0313; matched-pairs rank-biserial r = -0.727 (n_ranked=11)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 29 tied cells as a robustness check): W = 9.00, p = 0.0322 (n=11)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 9/11 favor Goga, p = 0.0654, 95% CI on proportion [0.482, 0.977]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = -1.907, p = 0.0639

#### Per-task-type breakdown -- full_architecture_conformance_rate

| Task type | n cells | Baseline mean | Goga mean | Mean delta | Goga<Base | Goga>Base | Tied |
|---|---|---|---|---|---|---|---|
| architecture_trap | 10 | 0.3500 | 0.2800 | -0.0700 | 4 | 0 | 6 |
| cross_module_feature | 10 | 0.1200 | 0.1500 | +0.0300 | 0 | 1 | 9 |
| existing_extension_point | 10 | 0.2800 | 0.2000 | -0.0800 | 3 | 0 | 7 |
| local_change | 10 | 0.4400 | 0.3300 | -0.1100 | 2 | 1 | 7 |

n=10 cells per task type is too small for a standalone significance test to be trustworthy (a single flipped cell swings the result); shown descriptively only, to see whether any one task type is driving the pooled 40-cell result.

#### Full Architecture Conformance -- GEE logistic regression (cluster-robust by task cell)

Unadjusted (`full_architecture_conformance ~ condition`): OR(Goga vs Baseline) = 0.746 (95% CI [0.557, 0.997]), Wald p = 0.0480
Adjusted for repository + task_type (`full_architecture_conformance ~ condition + repository + task_type`): OR(Goga vs Baseline) = 0.650 (95% CI [0.413, 1.022]), Wald p = 0.0623

## 3. Continuous metrics (cell-mean level, n=40 paired cells)

Per-cell mean/median/SD/IQR are already reported in `results/cells.csv` (80 rows, one per repository x task x condition); this section pairs those cell means Baseline-vs-Goga and tests the 40 deltas, plus reports the pooled distributional summary (mean/median/SD/IQR across the 40 cell means per condition, not mean alone).

### Architecture Conformance Rate (ACR) (cell-mean level, n=40 paired cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 0.6678  |  Goga mean: 0.6272  |  Mean delta (Goga - Baseline): -0.0406  (95% bootstrap CI [-0.0731, -0.0125], 20000 resamples)
Direction: Goga > Baseline in 4/40 cells, Goga < Baseline in 17/40, tied in 19/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 115.50, p = 0.0044; matched-pairs rank-biserial r = -0.658 (n_ranked=21)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 19 tied cells as a robustness check): W = 39.50, p = 0.0081 (n=21)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 17/21 favor Goga, p = 0.0072, 95% CI on proportion [0.581, 0.946]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = -2.587, p = 0.0135

Distributional summary across the 40 cell means -- Baseline: mean=0.6678, median=0.7375, SD=0.2947, IQR=0.4438  |  Goga: mean=0.6272, median=0.7500, SD=0.2911, IQR=0.4542

### Cost per run (cell-mean level, n=40 paired cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 3.2066 USD  |  Goga mean: 3.2535 USD  |  Mean delta (Goga - Baseline): 0.0469 USD  (95% bootstrap CI [-0.1219, 0.2099], 20000 resamples)
Direction: Goga > Baseline in 25/40 cells, Goga < Baseline in 15/40, tied in 0/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 335.00, p = 0.3203; matched-pairs rank-biserial r = 0.183 (n_ranked=40)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 0 tied cells as a robustness check): W = 335.00, p = 0.3203 (n=40)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 15/40 favor Goga, p = 0.1539, 95% CI on proportion [0.227, 0.542]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = 0.546, p = 0.5883

Distributional summary across the 40 cell means -- Baseline: mean=3.2066 USD, median=2.9316 USD, SD=1.7559 USD, IQR=2.9540 USD  |  Goga: mean=3.2535 USD, median=3.1088 USD, SD=1.7148 USD, IQR=2.8404 USD

### Duration per run (cell-mean level, n=40 paired cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 489.1832 s  |  Goga mean: 508.2304 s  |  Mean delta (Goga - Baseline): 19.0472 s  (95% bootstrap CI [-6.6763, 44.8951], 20000 resamples)
Direction: Goga > Baseline in 22/40 cells, Goga < Baseline in 18/40, tied in 0/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 299.00, p = 0.1387; matched-pairs rank-biserial r = 0.271 (n_ranked=40)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 0 tied cells as a robustness check): W = 299.00, p = 0.1387 (n=40)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 18/40 favor Goga, p = 0.6358, 95% CI on proportion [0.293, 0.615]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = 1.417, p = 0.1644

Distributional summary across the 40 cell means -- Baseline: mean=489.1832 s, median=478.5537 s, SD=253.0943 s, IQR=302.3547 s  |  Goga: mean=508.2304 s, median=483.2821 s, SD=269.1963 s, IQR=327.1242 s

### Agent turns per run (cell-mean level, n=40 paired cells)

n = 40 paired task-level cells (Baseline vs. Goga).
Baseline mean: 56.7350 turns  |  Goga mean: 58.4400 turns  |  Mean delta (Goga - Baseline): 1.7050 turns  (95% bootstrap CI [-0.7775, 4.2600], 20000 resamples)
Direction: Goga > Baseline in 23/40 cells, Goga < Baseline in 17/40, tied in 0/40.
Wilcoxon signed-rank test (zero_method='pratt', keeps ties): W = 322.00, p = 0.2369; matched-pairs rank-biserial r = 0.215 (n_ranked=40)
Wilcoxon signed-rank test (zero_method='wilcox', drops the 0 tied cells as a robustness check): W = 322.00, p = 0.2369 (n=40)
Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): 17/40 favor Goga, p = 0.4296, 95% CI on proportion [0.270, 0.591]
Paired t-test (parametric supplement, normality not assumed to hold): t(39) = 1.308, p = 0.1984

Distributional summary across the 40 cell means -- Baseline: mean=56.7350 turns, median=53.1500 turns, SD=22.9031 turns, IQR=31.7750 turns  |  Goga: mean=58.4400 turns, median=55.8500 turns, SD=23.3844 turns, IQR=35.3750 turns

## 4. Summary table

| Metric | Baseline mean | Goga mean | Mean delta (95% bootstrap CI) | Cells Goga better | Cells Goga worse | Tied |
|---|---|---|---|---|---|---|
| dangerous_success_rate | -- | -- | -0.0100 [-0.0425, +0.0200] | 8 | 7 | 25 |
| functional_success_rate | -- | -- | -0.0400 [-0.0700, -0.0125] | 4 | 13 | 23 |
| full_architecture_conformance_rate | -- | -- | -0.0575 [-0.1225, -0.0075] | 2 | 9 | 29 |
| Architecture Conformance Rate (ACR) | -- | -- | -0.0406 [-0.0731, -0.0125] | 4 | 17 | 19 |
| Cost per run | -- | -- | +0.0469 [-0.1219, +0.2099] | 25 | 15 | 0 |
| Duration per run | -- | -- | +19.0472 [-6.6763, +44.8951] | 22 | 18 | 0 |
| Agent turns per run | -- | -- | +1.7050 [-0.7775, +4.2600] | 23 | 17 | 0 |

"Better"/"worse" for `dangerous_success_rate` is directional (lower = better); for all other rows it is a plain Goga-vs-Baseline magnitude comparison with no normative direction implied (e.g. a higher `functional_success_rate` is better, a higher `duration_s_mean`/`cost_usd_mean` is worse, `turns_mean` has no inherent direction).

## 5. Interpretation

On the primary, pre-registered metric (Dangerous Success Rate), the pooled 40-cell mean delta is -0.0100 (Goga vs. Baseline), with a 95% bootstrap CI of [-0.0425, +0.0200] that includes zero, and Wilcoxon p=0.69 (pratt). This study finds no statistically significant difference in Dangerous Success Rate itself between a frozen, documentation-only CODEMANIFEST architecture description and no architecture description at all, at n=40 task-level cells.

**This flat primary-metric result hides a real, statistically significant pattern in its two components, and should not be read on its own.** Both `functional_success_rate` (mean delta -0.0400, Wilcoxon p=0.022, paired t p=0.012, GEE OR=0.85 unadjusted p=0.007 / OR=0.82 adjusted p=0.008) and `full_architecture_conformance_rate` (mean delta -0.0575, Wilcoxon p=0.031, GEE OR=0.75 unadjusted p=0.048) moved in the **same, negative** direction under Goga -- and ACR (the continuous architecture-conformance measure) moved the same way even more strongly (Wilcoxon p=0.004, paired t p=0.014). Because `dangerous_success = functional_success AND NOT full_architecture_conformance` (`PROTOCOL.md` Section 18), a drop in functional success mechanically shrinks the pool of runs that could even qualify as a "dangerous success" (functional success is a necessary precondition) at the same time architecture conformance is *also* dropping (which would, on its own, push Dangerous Success Rate up) -- the two effects pull the composite metric in opposite directions and largely cancel out. **The honest headline is not "Goga made no difference"; it is that giving the agent a static, frozen architecture description was associated with the agent doing measurably worse on both functional correctness and architecture conformance individually, and the one composite metric that looked flat is flat because of how its two ingredients cancel, not because nothing changed.** A plausible mechanism (not tested by this design): reading ~9,500 lines of CODEMANIFEST content plus a pointer file consumes agent turns and context budget that would otherwise go toward the task itself, without necessarily improving the agent's actual understanding of the codebase -- consistent with the (non-significant, but directionally the same) increases in mean duration and turns per run under Goga in Section 3.

**Multiple comparisons caveat**: seven metrics were tested (one pre-registered primary -- Dangerous Success Rate -- and six secondary/exploratory), each with several companion tests. No formal multiple-comparisons correction (e.g. Bonferroni/Holm/FDR) is applied here; the secondary-metric p-values above should be read as exploratory evidence supporting a coherent, mechanistically-explicable pattern (functional success down, architecture conformance down, in the same direction across four independent statistics: Wilcoxon, sign test, paired t-test, and cluster-robust GEE), not as a single confirmed hypothesis test. The observed effect sizes (delta magnitude ~0.04-0.06 for the rate metrics) are also small in absolute terms and n=40 paired cells gives this design limited power; both points are carried into the final report's threats-to-validity section (`PROTOCOL.md` Section 20) rather than overstated here.

This is a **descriptive-and-inferential, not causal-mechanism**, result: it answers "did adding a frozen CODEMANIFEST forest change these metrics on this 10-repository, 40-task sample" -- not "would a different (non-Goga-formatted, or non-frozen) architecture description have done better or worse," which remains out of scope per `TREATMENT_DESIGN.md` Section 5's own stated confound.

## 6. Reproducibility

Generated by `scripts/statistical_analysis.py`, reading only `results/analysis_set.csv` and `results/cells.csv` (both frozen Phase 11/12 outputs). Bootstrap CIs use `numpy.random.seed(42)`, 20,000 resamples per metric, percentile method. Re-running the script deterministically reproduces every number in this file.
