#!/usr/bin/env python3
"""
Generates experiment_plan_b.csv: the 400-row plan for Condition B' (Goga Full Workflow),
per TREATMENT_DESIGN_EXPERIMENT_B.md Sec.1/2.

Unlike the original experiment_plan.csv (which interleaves Baseline/Goga pairs for blocked
randomization), this plan has only ONE condition (B' reuses the existing 400 Condition-A rows
in results/runs.csv as its comparison group -- see TREATMENT_DESIGN_EXPERIMENT_B.md Sec.2).
So there's no pairing to block-randomize; only the overall execution order is shuffled, to
avoid confounding repository/task order with any temporal drift (model updates, account
state, etc.) over the run.

Fixed seed 43 (deliberately different from the original plan's seed 42, so the two seeds are
never confused with each other) -- recorded here and in TREATMENT_DESIGN_EXPERIMENT_B.md.
"""
import csv
import random
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parent.parent
SEED = 43
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
                run_id = f"{repo}-T{task}-BP-{rep:02d}"
                rows.append({
                    "repository": repo,
                    "task": task,
                    "task_type": TASK_TYPE_BY_LETTER[task],
                    "condition": "goga_full_workflow",
                    "repetition": rep,
                    "run_id": run_id,
                })

    assert len(rows) == 400, f"expected 400 rows, got {len(rows)}"

    random.shuffle(rows)
    for i, row in enumerate(rows, start=1):
        row["run_number"] = i

    out_path = BENCH_ROOT / "experiment_plan_b.csv"
    fieldnames = ["run_number", "run_id", "repository", "task", "task_type", "condition", "repetition"]
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row[k] for k in fieldnames})

    print(f"Wrote {out_path}: {len(rows)} rows, seed={SEED}")


if __name__ == "__main__":
    main()
