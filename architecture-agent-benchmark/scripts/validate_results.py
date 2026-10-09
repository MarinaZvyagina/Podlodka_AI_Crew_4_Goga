#!/usr/bin/env python3
"""
Phase 11 (PROTOCOL.md Sec.19): validation pass over results/runs.csv before aggregation.

For every one of the 800 rows in experiment_plan.csv, picks exactly one usable row from
results/runs.csv (the VALID row for that run_id, or its VALID -RETRYn replacement if the
original was INVALID/ERROR/TIMEOUT), and sanity-checks the resulting 800-row analysis set.

Never edits results/runs.csv (append-only, raw data preserved per PROTOCOL.md Sec.15/16).
Writes the resolved 800-row analysis set to results/analysis_set.csv and a text report to
results/VALIDATION_REPORT.md.
"""
import csv
import statistics
from collections import defaultdict
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parent.parent


def to_bool(s):
    if s in ("True", "true", "1"):
        return True
    if s in ("False", "false", "0", ""):
        return False
    return None


def main():
    plan_rows = []
    with open(BENCH_ROOT / "experiment_plan.csv") as f:
        plan_rows = list(csv.DictReader(f))
    assert len(plan_rows) == 800, f"expected 800 plan rows, got {len(plan_rows)}"

    rows_by_base = defaultdict(list)
    with open(BENCH_ROOT / "results" / "runs.csv") as f:
        for row in csv.DictReader(f):
            base = row["run_id"].split("-RETRY")[0]
            rows_by_base[base].append(row)

    resolved = []
    problems = []
    for plan_row in plan_rows:
        run_id = plan_row["run_id"]
        candidates = rows_by_base.get(run_id, [])
        valid_candidates = [r for r in candidates if r["status"] == "VALID"]
        if len(valid_candidates) == 0:
            problems.append(f"MISSING: {run_id} -- no VALID row found ({len(candidates)} attempt(s) recorded, "
                             f"statuses: {[r['status'] for r in candidates]})")
            continue
        if len(valid_candidates) > 1:
            problems.append(f"DUPLICATE: {run_id} -- {len(valid_candidates)} VALID rows found: "
                             f"{[r['run_id'] for r in valid_candidates]}")
            continue
        chosen = valid_candidates[0]

        # Cross-check the chosen row's own fields against the experiment_plan.csv row it
        # resolves to -- these must never drift (they're supposed to describe the same cell).
        for field in ("repository", "task", "task_type", "condition", "repetition"):
            if chosen[field] != plan_row[field]:
                problems.append(f"MISMATCH: {run_id} -- field '{field}' plan={plan_row[field]!r} "
                                 f"vs runs.csv={chosen[field]!r}")

        # Basic sanity bounds on the metrics that feed aggregation.
        try:
            acr = float(chosen["architecture_conformance_rate"]) if chosen["architecture_conformance_rate"] else None
            if acr is not None and not (0.0 <= acr <= 1.0):
                problems.append(f"RANGE: {run_id} -- architecture_conformance_rate={acr} outside [0,1]")
        except ValueError:
            problems.append(f"PARSE: {run_id} -- architecture_conformance_rate={chosen['architecture_conformance_rate']!r} not a float")

        func = to_bool(chosen["functional_success"])
        full_arch = to_bool(chosen["full_architecture_conformance"])
        dangerous = to_bool(chosen["dangerous_success"])
        if func is None or full_arch is None or dangerous is None:
            problems.append(f"BOOL: {run_id} -- unparseable boolean field "
                             f"(functional_success={chosen['functional_success']!r}, "
                             f"full_architecture_conformance={chosen['full_architecture_conformance']!r}, "
                             f"dangerous_success={chosen['dangerous_success']!r})")
        else:
            expected_dangerous = func and not full_arch
            if dangerous != expected_dangerous:
                problems.append(f"LOGIC: {run_id} -- dangerous_success={dangerous} but "
                                 f"functional_success={func} AND NOT full_architecture_conformance={full_arch} "
                                 f"implies {expected_dangerous}")

        try:
            cost = float(chosen["cost_usd"]) if chosen["cost_usd"] else None
            if cost is not None and not (0 < cost <= 8.5):
                problems.append(f"COST: {run_id} -- cost_usd={cost} outside expected (0, 8.5] "
                                 f"(budget ceiling is $8)")
        except ValueError:
            problems.append(f"PARSE: {run_id} -- cost_usd={chosen['cost_usd']!r} not a float")

        resolved.append(chosen)

    # Write the resolved analysis set (800 rows expected).
    out_path = BENCH_ROOT / "results" / "analysis_set.csv"
    fieldnames = list(resolved[0].keys()) if resolved else []
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(resolved)

    # Distributional sanity: per-condition counts should be 400/400, per-repo 80/80, etc.
    by_condition = defaultdict(int)
    by_repo = defaultdict(int)
    by_repo_task_condition = defaultdict(int)
    costs = []
    durations = []
    for r in resolved:
        by_condition[r["condition"]] += 1
        by_repo[r["repository"]] += 1
        by_repo_task_condition[(r["repository"], r["task"], r["condition"])] += 1
        if r["cost_usd"]:
            costs.append(float(r["cost_usd"]))
        if r["duration_ms"]:
            durations.append(float(r["duration_ms"]) / 1000)

    cells_not_10 = {k: v for k, v in by_repo_task_condition.items() if v != 10}

    report_lines = []
    report_lines.append("# Phase 11 — Validation Report\n")
    report_lines.append(f"Resolved analysis set: **{len(resolved)} / 800** rows.\n")
    report_lines.append(f"Problems found: **{len(problems)}**\n")
    if problems:
        report_lines.append("## Problems\n")
        for p in problems:
            report_lines.append(f"- {p}")
        report_lines.append("")
    report_lines.append("## Distribution checks\n")
    report_lines.append(f"- By condition: {dict(by_condition)} (expected baseline=400, goga=400)")
    report_lines.append(f"- By repository: {dict(sorted(by_repo.items()))} (expected 80 each)")
    report_lines.append(f"- Cells (repository, task, condition) not exactly 10 repetitions: {len(cells_not_10)}")
    if cells_not_10:
        for k, v in sorted(cells_not_10.items()):
            report_lines.append(f"  - {k}: {v}")
    if costs:
        report_lines.append(f"- Cost: n={len(costs)}, mean=${statistics.mean(costs):.3f}, "
                             f"median=${statistics.median(costs):.3f}, total=${sum(costs):.2f}, "
                             f"max=${max(costs):.3f}")
    if durations:
        report_lines.append(f"- Duration: n={len(durations)}, mean={statistics.mean(durations):.1f}s, "
                             f"median={statistics.median(durations):.1f}s, max={max(durations):.1f}s")

    report_path = BENCH_ROOT / "results" / "VALIDATION_REPORT.md"
    report_path.write_text("\n".join(report_lines) + "\n")

    print("\n".join(report_lines))
    print(f"\nWrote {out_path} and {report_path}")


if __name__ == "__main__":
    main()
