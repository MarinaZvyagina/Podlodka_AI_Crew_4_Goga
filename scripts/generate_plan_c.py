#!/usr/bin/env python3
"""
Generates experiment_plan_c.csv: the 400-row plan for Condition C (Goga-Native Architecture --
real cell restructuring), per TREATMENT_DESIGN_EXPERIMENT_B.md Sec.1 step 7.

Same repos/tasks/reps/generation-logic as the primary plan and B'/B''; a fresh seed (45, next
in the documented sequence after 42/43/44) keeps this condition's execution order independently
reproducible and never confused with any other condition's shuffle.

All 10 repos are included even though, at generation time, only 8 (R01-R07, R09) have a valid
condition-c-rXX-v1 tag in their base clone -- R08 and R10's tags were lost to a git-clone/
worktree mixup mid-session and are being reconstructed separately (see STATUS.md). execute_run_c.py
checks for the tag's existence before spending any budget and writes a SKIPPED (not VALID) row if
missing, so scripts/run_batch_c.sh's normal "skip if already VALID" resume logic will keep
retrying those 80 rows for free until the tags exist, with no need to regenerate this plan or
maintain a second one.
"""
import csv
import random
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parent.parent
SEED = 45
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
                run_id = f"{repo}-T{task}-GC-{rep:02d}"
                rows.append({
                    "repository": repo,
                    "task": task,
                    "task_type": TASK_TYPE_BY_LETTER[task],
                    "condition": "goga_native_architecture",
                    "repetition": rep,
                    "run_id": run_id,
                })

    assert len(rows) == 400, f"expected 400 rows, got {len(rows)}"

    random.shuffle(rows)
    for i, row in enumerate(rows, start=1):
        row["run_number"] = i

    out_path = BENCH_ROOT / "experiment_plan_c.csv"
    fieldnames = ["run_number", "run_id", "repository", "task", "task_type", "condition", "repetition"]
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row[k] for k in fieldnames})

    print(f"Wrote {out_path}: {len(rows)} rows, seed={SEED}")


if __name__ == "__main__":
    main()
