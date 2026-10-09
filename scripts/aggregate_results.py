#!/usr/bin/env python3
"""
Phase 12 (PROTOCOL.md Sec.14/19): aggregation over results/analysis_set.csv (the 800-row
resolved set produced by scripts/validate_results.py).

Produces:
- results/cells.csv: one row per (repository, task, condition) cell (80 rows), aggregating
  the 10 repetitions in that cell -- the stability_per_cell metrics that the actual Phase 10
  harness captured (see results/METRICS_COVERAGE.md for what was NOT captured and why).
- results/task_comparison.csv: one row per (repository, task) pair (40 rows), pairing the
  Baseline and Goga cells for that task per PROTOCOL.md Sec.14's "40 paired task-level
  comparisons" primary analysis. Binary rates get a Wilson score 95% CI (n=10 per cell is too
  small for a normal approximation to be trustworthy; Wilson score doesn't need scipy and
  behaves reasonably at small n) -- this is the "account for repeated observations per cell"
  requirement, not a naive pooled proportion across all 800 rows.

No dependencies beyond the stdlib (this machine has no numpy/pandas/scipy installed).
"""
import csv
import math
import statistics
from collections import defaultdict
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parent.parent
Z_95 = 1.959963985


def to_bool(s):
    return s in ("True", "true", "1")


def wilson_ci(successes, n, z=Z_95):
    if n == 0:
        return (None, None)
    phat = successes / n
    denom = 1 + z * z / n
    center = (phat + z * z / (2 * n)) / denom
    margin = z * math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, center - margin), min(1.0, center + margin))


def iqr(values):
    if len(values) < 2:
        return 0.0
    sv = sorted(values)
    q1 = statistics.median(sv[: len(sv) // 2])
    upper_half = sv[(len(sv) + 1) // 2:]
    q3 = statistics.median(upper_half) if upper_half else sv[-1]
    return q3 - q1


def load_analysis_set():
    with open(BENCH_ROOT / "results" / "analysis_set.csv") as f:
        return list(csv.DictReader(f))


def aggregate_cell(rows):
    """rows: the (exactly 10, validated in Phase 11) rows for one (repository, task, condition) cell."""
    n = len(rows)
    func = [to_bool(r["functional_success"]) for r in rows]
    full_arch = [to_bool(r["full_architecture_conformance"]) for r in rows]
    dangerous = [to_bool(r["dangerous_success"]) for r in rows]
    acr = [float(r["architecture_conformance_rate"]) for r in rows if r["architecture_conformance_rate"]]
    cost = [float(r["cost_usd"]) for r in rows if r["cost_usd"]]
    duration_s = [float(r["duration_ms"]) / 1000 for r in rows if r["duration_ms"]]
    tokens_in = [float(r["tokens_input"]) for r in rows if r["tokens_input"]]
    tokens_out = [float(r["tokens_output"]) for r in rows if r["tokens_output"]]
    turns = [float(r["tool_calls_num_turns"]) for r in rows if r["tool_calls_num_turns"]]
    files_changed = [float(r["files_changed"]) for r in rows if r["files_changed"]]

    n_func = sum(func)
    n_full_arch = sum(full_arch)
    n_dangerous = sum(dangerous)

    return {
        "n": n,
        "n_functional_success": n_func,
        "functional_success_rate": n_func / n,
        "n_full_architecture_conformance": n_full_arch,
        "full_architecture_conformance_rate": n_full_arch / n,
        "n_dangerous_success": n_dangerous,
        "dangerous_success_rate": n_dangerous / n,
        "acr_mean": statistics.mean(acr) if acr else None,
        "acr_median": statistics.median(acr) if acr else None,
        "acr_sd": statistics.stdev(acr) if len(acr) > 1 else 0.0,
        "acr_iqr": iqr(acr) if acr else None,
        "acr_min": min(acr) if acr else None,
        "acr_max": max(acr) if acr else None,
        "cost_usd_mean": statistics.mean(cost) if cost else None,
        "cost_usd_median": statistics.median(cost) if cost else None,
        "cost_usd_total": sum(cost) if cost else None,
        "duration_s_mean": statistics.mean(duration_s) if duration_s else None,
        "duration_s_median": statistics.median(duration_s) if duration_s else None,
        "tokens_input_mean": statistics.mean(tokens_in) if tokens_in else None,
        "tokens_output_mean": statistics.mean(tokens_out) if tokens_out else None,
        "turns_mean": statistics.mean(turns) if turns else None,
        "files_changed_mean": statistics.mean(files_changed) if files_changed else None,
    }


def main():
    rows = load_analysis_set()
    assert len(rows) == 800, f"expected 800 rows in analysis_set.csv, got {len(rows)}"

    by_cell = defaultdict(list)
    for r in rows:
        by_cell[(r["repository"], r["task"], r["condition"])].append(r)

    assert len(by_cell) == 80, f"expected 80 cells, got {len(by_cell)}"
    for key, cell_rows in by_cell.items():
        assert len(cell_rows) == 10, f"cell {key} has {len(cell_rows)} rows, expected 10"

    # results/cells.csv -- 80 rows.
    cell_records = []
    for (repo, task, condition), cell_rows in sorted(by_cell.items()):
        agg = aggregate_cell(cell_rows)
        task_type = cell_rows[0]["task_type"]
        cell_records.append({"repository": repo, "task": task, "task_type": task_type,
                              "condition": condition, **agg})

    cells_path = BENCH_ROOT / "results" / "cells.csv"
    fieldnames = list(cell_records[0].keys())
    with open(cells_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(cell_records)

    # results/task_comparison.csv -- 40 paired (repository, task) Baseline vs Goga rows.
    by_repo_task = defaultdict(dict)
    for (repo, task, condition), cell_rows in by_cell.items():
        by_repo_task[(repo, task)][condition] = aggregate_cell(cell_rows)

    assert len(by_repo_task) == 40, f"expected 40 (repository, task) pairs, got {len(by_repo_task)}"

    comparison_records = []
    for (repo, task), conditions in sorted(by_repo_task.items()):
        b = conditions["baseline"]
        g = conditions["goga"]
        task_type = next(r["task_type"] for r in by_cell[(repo, task, "baseline")])

        b_dsr_lo, b_dsr_hi = wilson_ci(b["n_dangerous_success"], b["n"])
        g_dsr_lo, g_dsr_hi = wilson_ci(g["n_dangerous_success"], g["n"])
        b_fsr_lo, b_fsr_hi = wilson_ci(b["n_functional_success"], b["n"])
        g_fsr_lo, g_fsr_hi = wilson_ci(g["n_functional_success"], g["n"])
        b_acr_lo, b_acr_hi = wilson_ci(b["n_full_architecture_conformance"], b["n"])
        g_acr_lo, g_acr_hi = wilson_ci(g["n_full_architecture_conformance"], g["n"])

        comparison_records.append({
            "repository": repo, "task": task, "task_type": task_type,
            "baseline_dangerous_success_rate": b["dangerous_success_rate"],
            "baseline_dangerous_success_ci95_lo": b_dsr_lo, "baseline_dangerous_success_ci95_hi": b_dsr_hi,
            "goga_dangerous_success_rate": g["dangerous_success_rate"],
            "goga_dangerous_success_ci95_lo": g_dsr_lo, "goga_dangerous_success_ci95_hi": g_dsr_hi,
            "delta_dangerous_success_rate": g["dangerous_success_rate"] - b["dangerous_success_rate"],
            "baseline_functional_success_rate": b["functional_success_rate"],
            "baseline_functional_success_ci95_lo": b_fsr_lo, "baseline_functional_success_ci95_hi": b_fsr_hi,
            "goga_functional_success_rate": g["functional_success_rate"],
            "goga_functional_success_ci95_lo": g_fsr_lo, "goga_functional_success_ci95_hi": g_fsr_hi,
            "delta_functional_success_rate": g["functional_success_rate"] - b["functional_success_rate"],
            "baseline_full_architecture_conformance_rate": b["full_architecture_conformance_rate"],
            "baseline_full_arch_ci95_lo": b_acr_lo, "baseline_full_arch_ci95_hi": b_acr_hi,
            "goga_full_architecture_conformance_rate": g["full_architecture_conformance_rate"],
            "goga_full_arch_ci95_lo": g_acr_lo, "goga_full_arch_ci95_hi": g_acr_hi,
            "delta_full_architecture_conformance_rate": g["full_architecture_conformance_rate"] - b["full_architecture_conformance_rate"],
            "baseline_acr_mean": b["acr_mean"], "goga_acr_mean": g["acr_mean"],
            "delta_acr_mean": (g["acr_mean"] - b["acr_mean"]) if (g["acr_mean"] is not None and b["acr_mean"] is not None) else None,
            "baseline_cost_usd_mean": b["cost_usd_mean"], "goga_cost_usd_mean": g["cost_usd_mean"],
            "baseline_duration_s_mean": b["duration_s_mean"], "goga_duration_s_mean": g["duration_s_mean"],
            "baseline_turns_mean": b["turns_mean"], "goga_turns_mean": g["turns_mean"],
        })

    comparison_path = BENCH_ROOT / "results" / "task_comparison.csv"
    fieldnames = list(comparison_records[0].keys())
    with open(comparison_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(comparison_records)

    # Overall summary print.
    overall_baseline_dsr = statistics.mean([r["baseline_dangerous_success_rate"] for r in comparison_records])
    overall_goga_dsr = statistics.mean([r["goga_dangerous_success_rate"] for r in comparison_records])
    deltas = [r["delta_dangerous_success_rate"] for r in comparison_records]
    n_goga_lower = sum(1 for d in deltas if d < 0)
    n_goga_higher = sum(1 for d in deltas if d > 0)
    n_tied = sum(1 for d in deltas if d == 0)

    print(f"Wrote {cells_path} (80 rows) and {comparison_path} (40 rows)\n")
    print("== Primary metric: Dangerous Success Rate (mean across 40 task-level cells) ==")
    print(f"  Baseline: {overall_baseline_dsr:.3f}")
    print(f"  Goga:     {overall_goga_dsr:.3f}")
    print(f"  Delta (Goga - Baseline): {overall_goga_dsr - overall_baseline_dsr:+.3f}")
    print(f"  Task-level cells where Goga < Baseline (lower danger): {n_goga_lower}/40")
    print(f"  Task-level cells where Goga > Baseline (higher danger): {n_goga_higher}/40")
    print(f"  Task-level cells tied: {n_tied}/40")


if __name__ == "__main__":
    main()
