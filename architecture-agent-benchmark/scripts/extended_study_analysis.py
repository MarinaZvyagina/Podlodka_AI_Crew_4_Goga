#!/usr/bin/env python3
"""
Extended-study statistical analysis: pairs Condition B'' (Goga Forced Workflow) and Condition C
(Goga-Native Architecture) -- both complete at 400/400 valid, exactly 10 repetitions per cell --
against the PRIMARY study's Condition A (Baseline) cells for the same (repository, task), using
the identical methodology as scripts/statistical_analysis.py (Phase 13): paired Wilcoxon signed-
rank (zero_method='pratt'), exact sign test, paired t-test, percentile bootstrap 95% CI on the
40 cell-level deltas, and cluster-robust GEE logistic regression at the run level.

This is explicitly NOT a pooling of the extended study into the primary result
(TREATMENT_DESIGN_EXPERIMENT_B.md Sec.3's non-pooling rule refers to not merging these conditions'
data into the primary A-vs-B comparison's own statistics) -- each extended condition is compared
against Baseline as its own separate, clearly-labeled test, mirroring how Sec.11 of
report/final_report.md already presents them descriptively. Condition B' is excluded from this
formal pairing: it was stopped by design at 91/400 with uneven, often-zero repetitions per cell,
which cannot support a valid 10-repetition cell rate -- see report/final_report.md Sec.11 for why
it is reported descriptively (pooled) only.

Output: results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md
"""
import numpy as np
import pandas as pd
from scipy import stats
import statsmodels.api as sm
import statsmodels.formula.api as smf

np.random.seed(42)
BENCH_ROOT = __file__.rsplit("/scripts/", 1)[0]
N_BOOT = 20000

CONDITIONS = [
    ("results/runs_experiment_b2.csv", "goga_forced_workflow", "Condition B″ (Goga Forced Workflow)"),
    ("results/runs_experiment_c.csv", "goga_native_architecture", "Condition C (Goga-Native Architecture)"),
]


def load_extended(path):
    df = pd.read_csv(path)
    valid = df[df["status"] == "VALID"].copy()
    valid["base_id"] = valid["run_id"].str.replace(r"-RETRY\d+$", "", regex=True)
    valid = valid.sort_values("timestamp").drop_duplicates("base_id", keep="last")
    return valid


def load_baseline_runs():
    runs = pd.read_csv(f"{BENCH_ROOT}/results/analysis_set.csv")
    return runs[runs["condition"] == "baseline"].copy()


def cell_rates(df, metric):
    g = df.groupby(["repository", "task"])[metric]
    return g.mean().rename(metric).reset_index()


def bootstrap_ci_mean_delta(deltas, n_boot=N_BOOT):
    deltas = np.asarray(deltas, dtype=float)
    n = len(deltas)
    idx_pool = np.arange(n)
    boot_means = np.empty(n_boot)
    for i in range(n_boot):
        idx = np.random.choice(idx_pool, size=n, replace=True)
        boot_means[i] = deltas[idx].mean()
    lo, hi = np.percentile(boot_means, [2.5, 97.5])
    return deltas.mean(), lo, hi


def paired_test(base_rates, ext_rates, label, metric):
    merged = base_rates.merge(ext_rates, on=["repository", "task"], suffixes=("_base", "_ext"))
    assert len(merged) == 40, f"expected 40 paired cells, got {len(merged)}"
    deltas = (merged[f"{metric}_ext"] - merged[f"{metric}_base"]).to_numpy()
    n_pos = int((deltas > 0).sum())
    n_neg = int((deltas < 0).sum())
    n_tied = int((deltas == 0).sum())
    mean_delta, ci_lo, ci_hi = bootstrap_ci_mean_delta(deltas)

    lines = [f"#### {label}", ""]
    lines.append(
        f"Baseline mean: {merged[f'{metric}_base'].mean():.4f}  |  "
        f"Extended-condition mean: {merged[f'{metric}_ext'].mean():.4f}  |  "
        f"Mean delta: {mean_delta:+.4f} (95% bootstrap CI [{ci_lo:+.4f}, {ci_hi:+.4f}])"
    )
    lines.append(
        f"Direction: condition > Baseline in {n_pos}/40, condition < Baseline in {n_neg}/40, "
        f"tied in {n_tied}/40."
    )
    if (deltas != 0).any():
        w = stats.wilcoxon(deltas, zero_method="pratt", mode="auto")
        lines.append(f"Wilcoxon signed-rank (pratt): W={w.statistic:.2f}, p={w.pvalue:.4f}")
        t = stats.ttest_rel(merged[f"{metric}_ext"], merged[f"{metric}_base"])
        lines.append(f"Paired t-test: t(39)={t.statistic:.3f}, p={t.pvalue:.4f}")
        nz = deltas[deltas != 0]
        sign = stats.binomtest(n_neg, n_neg + n_pos, p=0.5)
        lines.append(
            f"Exact sign test (excludes ties): {n_neg}/{n_neg+n_pos} favor Baseline "
            f"(condition<Baseline), p={sign.pvalue:.4f}"
        )
    else:
        lines.append("All 40 deltas are exactly zero.")
    lines.append("")
    return "\n".join(lines), {"metric": metric, "mean_delta": mean_delta, "ci_lo": ci_lo, "ci_hi": ci_hi,
                               "n_pos": n_pos, "n_neg": n_neg, "n_tied": n_tied}


def gee_vs_baseline(base_runs, ext_df, ext_condition_label, outcome):
    base = base_runs[["repository", "task", "task_type", outcome]].copy()
    base["is_extended"] = 0
    ext = ext_df[["repository", "task", "task_type", outcome]].copy()
    ext["is_extended"] = 1
    combined = pd.concat([base, ext], ignore_index=True)
    combined["cell_id"] = combined["repository"] + "-" + combined["task"]
    combined[outcome] = combined[outcome].astype(int)

    fam = sm.families.Binomial()
    model = smf.gee(f"{outcome} ~ is_extended", groups="cell_id", data=combined, family=fam,
                     cov_struct=sm.cov_struct.Exchangeable())
    res = model.fit()
    coef, se, p = res.params["is_extended"], res.bse["is_extended"], res.pvalues["is_extended"]
    or_, ci_lo, ci_hi = np.exp(coef), np.exp(coef - 1.96 * se), np.exp(coef + 1.96 * se)
    return (f"GEE logistic regression (cluster-robust by cell, `{outcome} ~ condition`): "
            f"OR({ext_condition_label} vs Baseline) = {or_:.3f} (95% CI [{ci_lo:.3f}, {ci_hi:.3f}]), "
            f"Wald p = {p:.4f}")


def main():
    base_runs = load_baseline_runs()
    base_runs["functional_success"] = base_runs["functional_success"].astype(str).str.lower().eq("true")
    base_runs["full_architecture_conformance"] = base_runs["full_architecture_conformance"].astype(str).str.lower().eq("true")
    base_runs["dangerous_success"] = base_runs["dangerous_success"].astype(str).str.lower().eq("true")

    report = []
    report.append("# Extended Study Statistical Analysis — B″ and C vs. Primary Baseline")
    report.append("")
    report.append(
        "Formal paired comparison of Condition B″ (Goga Forced Workflow, 400/400 valid) and "
        "Condition C (Goga-Native Architecture, 400/400 valid) against the primary study's "
        "Condition A (Baseline) cells for the same (repository, task), using the identical "
        "methodology as `results/PHASE13_STATISTICAL_ANALYSIS.md`: paired Wilcoxon signed-rank "
        "(zero_method='pratt'), paired t-test, exact sign test, percentile bootstrap 95% CI on "
        "the 40 cell-level deltas (n=40 paired cells each, 10 repetitions per cell, never "
        "pseudoreplicated), and cluster-robust GEE logistic regression at the run level "
        "(clustered by task cell). Condition B′ is excluded (stopped by design at 91/400 with "
        "uneven, often-zero repetitions per cell -- see `report/final_report.md` §11 for its "
        "pooled descriptive numbers instead)."
    )
    report.append("")
    report.append(
        "**This is a separate test from the primary A-vs-B comparison, not a pooling of data "
        "into it**, per `TREATMENT_DESIGN_EXPERIMENT_B.md` §3's explicit non-pooling rule. Each "
        "extended condition mixes multiple confounded changes at once (tooling access, prompt "
        "instruction, and/or actual codebase restructuring, on top of the same CODEMANIFEST "
        "format change Condition B already tested) -- a significant result here shows *that* "
        "something changed relative to no-Goga-at-all, not *which* ingredient of that condition "
        "caused it."
    )
    report.append("")

    metrics = [
        ("functional_success_rate", "functional_success", "Functional Success Rate"),
        ("full_architecture_conformance_rate", "full_architecture_conformance", "Full Architecture Conformance Rate"),
        ("dangerous_success_rate", "dangerous_success", "Dangerous Success Rate (lower = better)"),
    ]

    for path, cond_value, label in CONDITIONS:
        report.append(f"## {label}")
        report.append("")
        ext = load_extended(path)
        for col, run_col, metric_label in metrics:
            ext[run_col] = ext[run_col].astype(str).str.lower().eq("true")
            base_rates = cell_rates(base_runs, run_col).rename(columns={run_col: col})
            ext_rates = cell_rates(ext, run_col).rename(columns={run_col: col})
            text, summary = paired_test(base_rates, ext_rates, metric_label, col)
            report.append(text)
            report.append(gee_vs_baseline(base_runs, ext, label, run_col))
            report.append("")
        report.append("")

    out_path = f"{BENCH_ROOT}/results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md"
    with open(out_path, "w") as f:
        f.write("\n".join(report))
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
