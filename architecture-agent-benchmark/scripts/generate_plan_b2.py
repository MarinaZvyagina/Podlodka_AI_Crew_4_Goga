#!/usr/bin/env python3
"""
Generates experiment_plan_b2.csv: the 400-row plan for Condition B'' (Goga Forced Workflow).

Condition B' (goga_full_workflow, experiment_plan_b.csv, seed=43) gave the agent Goga tooling
with a neutral, optional-use prompt sentence -- see TREATMENT_DESIGN_EXPERIMENT_B.md Sec.1. That
batch was run to 79/400 before being intentionally stopped (not discarded -- results/
runs_experiment_b.csv is kept as-is, a real, valid measurement of organic tool-adoption rate) once
it became clear engagement was very low (1/79 runs showed any sign of the agent actually invoking
Goga tooling). Per explicit user request (2026-09-14), a second, distinct condition (B'', "Goga
Forced Workflow") is added with an explicit instruction to use the tooling, rather than mutating
B' mid-batch (which would silently mix two different treatments within one condition label and
break comparability across its own 400 repetitions).

Same repos/tasks/reps/seed-generation-logic as B', deliberately reusing seed 43 was considered and
rejected -- a different seed (44) is used so the two conditions' execution orders are both
independently reproducible and never confused with each other or with the primary study's seed 42.
"""
import csv
import random
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parent.parent
SEED = 44
REPOS = [f"R{i:02d}" for i in range(1, 11)]
TASKS = ["A", "B", "C", "D"]
TASK_TYPE_BY_LETTER = {
    "A": "local_change",
    "B": "cross_module_feature",
    "C": "existing_extension_point",
    "D": "architecture_trap",
}
REPETITIONS = 10


def main():
    random.seed(SEED)

    rows = []
    for repo in REPOS:
        for task in TASKS:
            for rep in range(1, REPETITIONS + 1):
                run_id = f"{repo}-T{task}-BF-{rep:02d}"
                rows.append({
                    "repository": repo,
                    "task": task,
                    "task_type": TASK_TYPE_BY_LETTER[task],
                    "condition": "goga_forced_workflow",
                    "repetition": rep,
                    "run_id": run_id,
                })

    assert len(rows) == 400, f"expected 400 rows, got {len(rows)}"

    random.shuffle(rows)
    for i, row in enumerate(rows, start=1):
        row["run_number"] = i

    out_path = BENCH_ROOT / "experiment_plan_b2.csv"
    fieldnames = ["run_number", "run_id", "repository", "task", "task_type", "condition", "repetition"]
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row[k] for k in fieldnames})

    print(f"Wrote {out_path}: {len(rows)} rows, seed={SEED}")


if __name__ == "__main__":
    main()
