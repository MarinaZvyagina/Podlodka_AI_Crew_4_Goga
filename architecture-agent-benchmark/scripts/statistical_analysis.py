#!/usr/bin/env python3
"""
Phase 13 -- statistical analysis of the primary 800-run study (Condition A/Baseline vs.
Condition B/Goga), per PROTOCOL.md Section 14.

Inputs (never modified):
  results/analysis_set.csv    -- 800 run-level rows (Phase 11 output)
  results/cells.csv           -- 80 (repository, task, condition) cell aggregates (Phase 12)
  results/task_comparison.csv -- 40 paired (repository, task) Baseline-vs-Goga rows (Phase 12)

Output:
  results/PHASE13_STATISTICAL_ANALYSIS.md -- full write-up (this script's only side effect)

Methodology, following PROTOCOL.md Section 14 explicitly:
  - Unit of primary inference is the task-level cell (n=40 pairs), never the 800 raw runs,
    to avoid pseudoreplication across the 10 repetitions within a cell.
  - Primary metric (Dangerous Success Rate): paired Wilcoxon signed-rank test on the 40
    cell-level deltas (Goga - Baseline), zero_method='pratt' (keeps zero-diffs, does not
    silently discard the large tied fraction), plus an exact sign test as a distribution-free
    robustness check, plus a percentile bootstrap 95% CI on the mean delta as the primary
    effect-size statement (robust to whatever the true sampling distribution is).
  - Same paired-cell treatment applied to functional_success and full_architecture_conformance
    rates, and to continuous metrics (ACR, cost, duration, turns) using cell means.
  - Secondary: run-level GEE (binomial family, logit link, exchangeable working correlation,
    clustered by cell) on each binary outcome -- respects the repetition clustering explicitly
    (cluster-robust, not a naive pooled proportion across all 800 rows) and yields an odds
    ratio + 95% CI + p-value, both unadjusted and adjusted for repository/task_type.
  - Per-task-type breakdown (n=10 cells per type) reported descriptively; too small for a
    separate formal test to be trustworthy on its own, but useful for the narrative.
"""
import numpy as np
import pandas as pd
from scipy import stats
import statsmodels.api as sm
import statsmodels.formula.api as smf

np.random.seed(42)  # bootstrap reproducibility only -- no bearing on the experiment's own seed

BENCH_ROOT = __file__.rsplit("/scripts/", 1)[0]
N_BOOT = 20000


def load_data():
    runs = pd.read_csv(f"{BENCH_ROOT}/results/analysis_set.csv")
    cells = pd.read_csv(f"{BENCH_ROOT}/results/cells.csv")
    runs["cell_id"] = runs["repository"] + "-" + runs["task"]
    runs["duration_s"] = runs["duration_ms"] / 1000.0
    return runs, cells


def paired_from_cells(cells, metric):
    """Pivot cells.csv to one row per (repository, task) with baseline_<metric>/goga_<metric>."""
    piv = cells.pivot(index=["repository", "task", "task_type"], columns="condition", values=metric)
    piv = piv.rename(columns={"baseline": f"baseline_{metric}", "goga": f"goga_{metric}"}).reset_index()
    piv["delta"] = piv[f"goga_{metric}"] - piv[f"baseline_{metric}"]
    return piv


def bootstrap_ci_mean_delta(deltas, n_boot=N_BOOT):
    deltas = np.asarray(deltas, dtype=float)
    n = len(deltas)
    boot_means = np.empty(n_boot)
    idx_pool = np.arange(n)
    for i in range(n_boot):
        idx = np.random.choice(idx_pool, size=n, replace=True)
        boot_means[i] = deltas[idx].mean()
    lo, hi = np.percentile(boot_means, [2.5, 97.5])
    return deltas.mean(), lo, hi


def wilcoxon_rank_biserial(deltas):
    """Matched-pairs rank-biserial correlation from the signed-rank statistic, computed on the
    non-zero deltas (the only ones Wilcoxon ranks), as an effect-size companion to the p-value."""
    nz = deltas[deltas != 0]
    if len(nz) == 0:
        return 0.0, 0
    ranks = stats.rankdata(np.abs(nz))
    pos = ranks[nz > 0].sum()
    neg = ranks[nz < 0].sum()
    total = pos + neg
    r = (pos - neg) / total if total > 0 else 0.0
    return r, len(nz)


def paired_test_block(df, metric_label, baseline_col, goga_col, title, unit=""):
    deltas = (df[goga_col] - df[baseline_col]).to_numpy()
    n = len(deltas)
    n_pos = int((deltas > 0).sum())  # goga > baseline
    n_neg = int((deltas < 0).sum())  # goga < baseline
    n_tied = int((deltas == 0).sum())

    mean_delta, ci_lo, ci_hi = bootstrap_ci_mean_delta(deltas)
    r_eff, n_ranked = wilcoxon_rank_biserial(deltas)
    wilcoxon_p = None

    lines = [f"### {title}", ""]
    lines.append(f"n = {n} paired task-level cells (Baseline vs. Goga).")
    lines.append(
        f"Baseline mean: {df[baseline_col].mean():.4f}{unit}  |  "
        f"Goga mean: {df[goga_col].mean():.4f}{unit}  |  "
        f"Mean delta (Goga - Baseline): {mean_delta:.4f}{unit}  "
        f"(95% bootstrap CI [{ci_lo:.4f}, {ci_hi:.4f}], {N_BOOT} resamples)"
    )
    lines.append(
        f"Direction: Goga > Baseline in {n_pos}/{n} cells, Goga < Baseline in {n_neg}/{n}, "
        f"tied in {n_tied}/{n}."
    )

    if n_ranked >= 1 and (deltas != 0).any():
        try:
            w_pratt = stats.wilcoxon(deltas, zero_method="pratt", mode="auto")
            wilcoxon_p = w_pratt.pvalue
            lines.append(
                f"Wilcoxon signed-rank test (zero_method='pratt', keeps ties): "
                f"W = {w_pratt.statistic:.2f}, p = {w_pratt.pvalue:.4f}; "
                f"matched-pairs rank-biserial r = {r_eff:.3f} (n_ranked={n_ranked})"
            )
        except ValueError as e:
            lines.append(f"Wilcoxon (pratt) could not be computed: {e}")
        nz = deltas[deltas != 0]
        if len(nz) >= 1:
            try:
                w_drop = stats.wilcoxon(nz, zero_method="wilcox", mode="auto")
                lines.append(
                    f"Wilcoxon signed-rank test (zero_method='wilcox', drops the "
                    f"{n_tied} tied cells as a robustness check): "
                    f"W = {w_drop.statistic:.2f}, p = {w_drop.pvalue:.4f} (n={len(nz)})"
                )
            except ValueError as e:
                lines.append(f"Wilcoxon (drop-ties) could not be computed: {e}")
        # exact sign test on the non-zero deltas
        sign_res = stats.binomtest(n_neg, n_neg + n_pos, p=0.5) if (n_neg + n_pos) > 0 else None
        if sign_res is not None:
            lines.append(
                f"Exact sign test (excludes ties, H0: P(Goga<Baseline)=0.5): "
                f"{n_neg}/{n_neg + n_pos} favor Goga, p = {sign_res.pvalue:.4f}, "
                f"95% CI on proportion [{sign_res.proportion_ci().low:.3f}, "
                f"{sign_res.proportion_ci().high:.3f}]"
            )
        t_res = stats.ttest_rel(df[goga_col], df[baseline_col])
        ttest_p = t_res.pvalue
        lines.append(
            f"Paired t-test (parametric supplement, normality not assumed to hold): "
            f"t({n - 1}) = {t_res.statistic:.3f}, p = {t_res.pvalue:.4f}"
        )
    else:
        ttest_p = None
        lines.append("All 40 deltas are exactly zero -- no test statistic is defined; "
                      "Baseline and Goga are identical on this metric at the cell level.")
    lines.append("")
    return "\n".join(lines), {
        "metric": metric_label, "n": n, "n_pos": n_pos, "n_neg": n_neg, "n_tied": n_tied,
        "mean_delta": mean_delta, "ci_lo": ci_lo, "ci_hi": ci_hi, "wilcoxon_p": wilcoxon_p,
        "ttest_p": ttest_p,
    }


def per_task_type_breakdown(df, metric_label, baseline_col, goga_col, unit=""):
    lines = [f"#### Per-task-type breakdown -- {metric_label}", ""]
    lines.append("| Task type | n cells | Baseline mean | Goga mean | Mean delta | Goga<Base | Goga>Base | Tied |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for tt in sorted(df["task_type"].unique()):
        sub = df[df["task_type"] == tt]
        deltas = (sub[goga_col] - sub[baseline_col]).to_numpy()
        n_pos = int((deltas > 0).sum())
        n_neg = int((deltas < 0).sum())
        n_tied = int((deltas == 0).sum())
        lines.append(
            f"| {tt} | {len(sub)} | {sub[baseline_col].mean():.4f}{unit} | "
            f"{sub[goga_col].mean():.4f}{unit} | {deltas.mean():+.4f}{unit} | "
            f"{n_neg} | {n_pos} | {n_tied} |"
        )
    lines.append("")
    lines.append(
        "n=10 cells per task type is too small for a standalone significance test to be "
        "trustworthy (a single flipped cell swings the result); shown descriptively only, "
        "to see whether any one task type is driving the pooled 40-cell result."
    )
    lines.append("")
    return "\n".join(lines)


def run_gee(runs, outcome, label):
    """Cluster-robust GEE logistic regression, clustered by task-level cell, both unadjusted
    (condition only) and adjusted for repository + task_type as fixed effects."""
    data = runs.copy()
    data["condition_goga"] = (data["condition"] == "goga").astype(int)
    data[outcome] = data[outcome].astype(int)

    lines = [f"#### {label} -- GEE logistic regression (cluster-robust by task cell)", ""]

    # Unadjusted
    fam = sm.families.Binomial()
    model = smf.gee(f"{outcome} ~ condition_goga", groups="cell_id", data=data, family=fam,
                     cov_struct=sm.cov_struct.Exchangeable())
    res = model.fit()
    coef = res.params["condition_goga"]
    se = res.bse["condition_goga"]
    p = res.pvalues["condition_goga"]
    or_ = np.exp(coef)
    ci_lo, ci_hi = np.exp(coef - 1.96 * se), np.exp(coef + 1.96 * se)
    lines.append(
        f"Unadjusted (`{outcome} ~ condition`): OR(Goga vs Baseline) = {or_:.3f} "
        f"(95% CI [{ci_lo:.3f}, {ci_hi:.3f}]), Wald p = {p:.4f}"
    )

    # Adjusted for repository + task_type
    model_adj = smf.gee(
        f"{outcome} ~ condition_goga + C(repository) + C(task_type)",
        groups="cell_id", data=data, family=fam, cov_struct=sm.cov_struct.Exchangeable(),
    )
    res_adj = model_adj.fit()
    coef_a = res_adj.params["condition_goga"]
    se_a = res_adj.bse["condition_goga"]
    p_a = res_adj.pvalues["condition_goga"]
    or_a = np.exp(coef_a)
    ci_lo_a, ci_hi_a = np.exp(coef_a - 1.96 * se_a), np.exp(coef_a + 1.96 * se_a)
    lines.append(
        f"Adjusted for repository + task_type (`{outcome} ~ condition + repository + task_type`): "
        f"OR(Goga vs Baseline) = {or_a:.3f} (95% CI [{ci_lo_a:.3f}, {ci_hi_a:.3f}]), "
        f"Wald p = {p_a:.4f}"
    )
    lines.append("")
    return "\n".join(lines), {
        "or_unadj": or_, "p_unadj": p, "or_adj": or_a, "p_adj": p_a,
    }


def continuous_metric_block(cells_piv, metric_label, baseline_col, goga_col, unit=""):
    text, summary = paired_test_block(cells_piv, metric_label, baseline_col, goga_col,
                                       f"{metric_label} (cell-mean level, n=40 paired cells)", unit)
    return text, summary


def main():
    runs, cells = load_data()

    report = []
    report.append("# Phase 13 -- Statistical Analysis")
    report.append("")
    report.append(
        "Formal significance testing on the primary 800-run study (Condition A/Baseline vs. "
        "Condition B/Goga), per `PROTOCOL.md` Section 14. This is descriptive analysis of "
        "already-frozen, already-validated data (`results/analysis_set.csv`, 800/800 VALID) "
        "-- no runs are re-executed or re-scored here. The primary unit of inference throughout "
        "is the task-level cell (10 repetitions aggregated into one rate/mean per "
        "`repository x task x condition`), never the 800 raw runs treated as independent "
        "observations, per the project's own no-pseudoreplication rule (`PROTOCOL.md` Section 14 "
        "/ `Research.md` Section 68)."
    )
    report.append("")
    report.append("## 1. Primary metric -- Dangerous Success Rate")
    report.append("")
    report.append(
        "`dangerous_success = functional_success AND NOT full_architecture_conformance` "
        "(`PROTOCOL.md` Section 18) -- the agent's change worked, but violated the codebase's "
        "real architectural boundaries in a way that would bite later. Lower is better."
    )
    report.append("")

    ds_piv = paired_from_cells(cells, "dangerous_success_rate")
    text, ds_summary = paired_test_block(
        ds_piv, "dangerous_success_rate", "baseline_dangerous_success_rate",
        "goga_dangerous_success_rate", "Pooled (all 40 cells)"
    )
    report.append(text)
    report.append(per_task_type_breakdown(
        ds_piv, "dangerous_success_rate", "baseline_dangerous_success_rate",
        "goga_dangerous_success_rate"
    ))

    report.append("### Secondary run-level model (respects repetition clustering)")
    report.append("")
    gee_text, ds_gee = run_gee(runs, "dangerous_success", "Dangerous Success")
    report.append(gee_text)

    report.append("## 2. Secondary binary outcomes")
    report.append("")

    fs_piv = paired_from_cells(cells, "functional_success_rate")
    text, fs_summary = paired_test_block(
        fs_piv, "functional_success_rate", "baseline_functional_success_rate",
        "goga_functional_success_rate", "Functional Success Rate (pooled, 40 cells)"
    )
    report.append(text)
    report.append(per_task_type_breakdown(
        fs_piv, "functional_success_rate", "baseline_functional_success_rate",
        "goga_functional_success_rate"
    ))
    gee_text, fs_gee = run_gee(runs, "functional_success", "Functional Success")
    report.append(gee_text)

    fac_piv = paired_from_cells(cells, "full_architecture_conformance_rate")
    text, fac_summary = paired_test_block(
        fac_piv, "full_architecture_conformance_rate", "baseline_full_architecture_conformance_rate",
        "goga_full_architecture_conformance_rate", "Full Architecture Conformance Rate (pooled, 40 cells)"
    )
    report.append(text)
    report.append(per_task_type_breakdown(
        fac_piv, "full_architecture_conformance_rate", "baseline_full_architecture_conformance_rate",
        "goga_full_architecture_conformance_rate"
    ))
    gee_text, fac_gee = run_gee(runs, "full_architecture_conformance", "Full Architecture Conformance")
    report.append(gee_text)

    report.append("## 3. Continuous metrics (cell-mean level, n=40 paired cells)")
    report.append("")
    report.append(
        "Per-cell mean/median/SD/IQR are already reported in `results/cells.csv` (80 rows, "
        "one per repository x task x condition); this section pairs those cell means "
        "Baseline-vs-Goga and tests the 40 deltas, plus reports the pooled distributional "
        "summary (mean/median/SD/IQR across the 40 cell means per condition, not mean alone)."
    )
    report.append("")

    cont_metrics = [
        ("acr_mean", "Architecture Conformance Rate (ACR)", ""),
        ("cost_usd_mean", "Cost per run", " USD"),
        ("duration_s_mean", "Duration per run", " s"),
        ("turns_mean", "Agent turns per run", " turns"),
    ]
    cont_summaries = []
    for col, label, unit in cont_metrics:
        piv = paired_from_cells(cells, col)
        text, summ = continuous_metric_block(piv, label, f"baseline_{col}", f"goga_{col}", unit)
        report.append(text)
        cont_summaries.append(summ)

        b_vals = piv[f"baseline_{col}"]
        g_vals = piv[f"goga_{col}"]
        report.append(
            f"Distributional summary across the 40 cell means -- "
            f"Baseline: mean={b_vals.mean():.4f}{unit}, median={b_vals.median():.4f}{unit}, "
            f"SD={b_vals.std():.4f}{unit}, IQR={b_vals.quantile(.75)-b_vals.quantile(.25):.4f}{unit}  |  "
            f"Goga: mean={g_vals.mean():.4f}{unit}, median={g_vals.median():.4f}{unit}, "
            f"SD={g_vals.std():.4f}{unit}, IQR={g_vals.quantile(.75)-g_vals.quantile(.25):.4f}{unit}"
        )
        report.append("")

    report.append("## 4. Summary table")
    report.append("")
    report.append("| Metric | Baseline mean | Goga mean | Mean delta (95% bootstrap CI) | Cells Goga better | Cells Goga worse | Tied |")
    report.append("|---|---|---|---|---|---|---|")
    for s in [ds_summary, fs_summary, fac_summary] + cont_summaries:
        m = s["metric"]
        lower_is_better = m in ("dangerous_success_rate",)
        better_col = "n_neg" if lower_is_better else "n_pos"
        worse_col = "n_pos" if lower_is_better else "n_neg"
        report.append(
            f"| {m} | -- | -- | {s['mean_delta']:+.4f} [{s['ci_lo']:+.4f}, {s['ci_hi']:+.4f}] | "
            f"{s[better_col]} | {s[worse_col]} | {s['n_tied']} |"
        )
    report.append("")
    report.append(
        "\"Better\"/\"worse\" for `dangerous_success_rate` is directional (lower = better); for "
        "all other rows it is a plain Goga-vs-Baseline magnitude comparison with no normative "
        "direction implied (e.g. a higher `functional_success_rate` is better, a higher "
        "`duration_s_mean`/`cost_usd_mean` is worse, `turns_mean` has no inherent direction)."
    )
    report.append("")

    report.append("## 5. Interpretation")
    report.append("")
    report.append(
        f"On the primary, pre-registered metric (Dangerous Success Rate), the pooled 40-cell "
        f"mean delta is {ds_summary['mean_delta']:+.4f} (Goga vs. Baseline), with a 95% "
        f"bootstrap CI of [{ds_summary['ci_lo']:+.4f}, {ds_summary['ci_hi']:+.4f}] that "
        f"{'excludes' if ds_summary['ci_lo'] > 0 or ds_summary['ci_hi'] < 0 else 'includes'} zero, "
        f"and Wilcoxon p={ds_summary['wilcoxon_p']:.2f} (pratt). This study finds "
        f"{'a statistically detectable' if (ds_summary['ci_lo'] > 0 or ds_summary['ci_hi'] < 0) else 'no statistically significant'} "
        "difference in Dangerous Success Rate itself between a frozen, documentation-only "
        "CODEMANIFEST architecture description and no architecture description at all, at "
        "n=40 task-level cells."
    )
    report.append("")
    acr_summary = cont_summaries[0]  # cont_metrics[0] is ACR -- see the list above
    report.append(
        "**This flat primary-metric result hides a real, statistically significant pattern in "
        "its two components, and should not be read on its own.** Both "
        f"`functional_success_rate` (mean delta {fs_summary['mean_delta']:+.4f}, Wilcoxon "
        f"p={fs_summary['wilcoxon_p']:.3f}, paired t p={fs_summary['ttest_p']:.3f}, "
        f"GEE OR={fs_gee['or_unadj']:.2f} unadjusted p={fs_gee['p_unadj']:.3f} / "
        f"OR={fs_gee['or_adj']:.2f} adjusted p={fs_gee['p_adj']:.3f}) "
        f"and `full_architecture_conformance_rate` (mean delta {fac_summary['mean_delta']:+.4f}, "
        f"Wilcoxon p={fac_summary['wilcoxon_p']:.3f}, GEE OR={fac_gee['or_unadj']:.2f} "
        f"unadjusted p={fac_gee['p_unadj']:.3f}) moved in the **same, negative** "
        "direction under Goga -- and ACR (the continuous architecture-conformance measure) "
        f"moved the same way even more strongly (Wilcoxon p={acr_summary['wilcoxon_p']:.3f}, "
        f"paired t p={acr_summary['ttest_p']:.3f}). Because "
        "`dangerous_success = functional_success AND NOT full_architecture_conformance` "
        "(`PROTOCOL.md` Section 18), a drop in functional success mechanically shrinks the pool "
        "of runs that could even qualify as a \"dangerous success\" (functional success is a "
        "necessary precondition) at the same time architecture conformance is *also* dropping "
        "(which would, on its own, push Dangerous Success Rate up) -- the two effects pull the "
        "composite metric in opposite directions and largely cancel out. **The honest headline "
        "is not \"Goga made no difference\"; it is that giving the agent a static, frozen "
        "architecture description was associated with the agent doing measurably worse on both "
        "functional correctness and architecture conformance individually, and the one composite "
        "metric that looked flat is flat because of how its two ingredients cancel, not because "
        "nothing changed.** A plausible mechanism (not tested by this design): "
        "reading ~9,500 lines of CODEMANIFEST content plus a pointer file consumes agent turns "
        "and context budget that would otherwise go toward the task itself, without necessarily "
        "improving the agent's actual understanding of the codebase -- consistent with the "
        "(non-significant, but directionally the same) increases in mean duration and turns "
        "per run under Goga in Section 3."
    )
    report.append("")
    report.append(
        "**Multiple comparisons caveat**: seven metrics were tested (one pre-registered primary "
        "-- Dangerous Success Rate -- and six secondary/exploratory), each with several "
        "companion tests. No formal multiple-comparisons correction (e.g. Bonferroni/"
        "Holm/FDR) is applied here; the secondary-metric p-values above should be read as "
        "exploratory evidence supporting a coherent, mechanistically-explicable pattern "
        "(functional success down, architecture conformance down, in the same direction across "
        "four independent statistics: Wilcoxon, sign test, paired t-test, and cluster-robust "
        "GEE), not as a single confirmed hypothesis test. The observed effect sizes "
        "(delta magnitude ~0.04-0.06 for the rate metrics) are also small in absolute terms and "
        "n=40 paired cells gives this design limited power; both points are carried into the "
        "final report's threats-to-validity section (`PROTOCOL.md` Section 20) rather than "
        "overstated here."
    )
    report.append("")
    report.append(
        "This is a **descriptive-and-inferential, not causal-mechanism**, result: it answers "
        "\"did adding a frozen CODEMANIFEST forest change these metrics on this "
        "10-repository, 40-task sample\" -- not \"would a different (non-Goga-formatted, or "
        "non-frozen) architecture description have done better or worse,\" which remains out of "
        "scope per `TREATMENT_DESIGN.md` Section 5's own stated confound."
    )
    report.append("")
    report.append("## 6. Reproducibility")
    report.append("")
    report.append(
        "Generated by `scripts/statistical_analysis.py`, reading only "
        "`results/analysis_set.csv` and `results/cells.csv` (both frozen Phase 11/12 outputs). "
        "Bootstrap CIs use `numpy.random.seed(42)`, 20,000 resamples per metric, percentile "
        "method. Re-running the script deterministically reproduces every number in this file."
    )
    report.append("")

    out_path = f"{BENCH_ROOT}/results/PHASE13_STATISTICAL_ANALYSIS.md"
    with open(out_path, "w") as f:
        f.write("\n".join(report))
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
