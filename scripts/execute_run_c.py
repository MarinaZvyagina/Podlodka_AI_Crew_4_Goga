#!/usr/bin/env python3
"""
Experiment C execution engine: runs exactly one row of experiment_plan_c.csv end-to-end
for Condition C (Goga-Native Architecture -- real cell restructuring), per
TREATMENT_DESIGN_EXPERIMENT_B.md Sec.1 step 7.

Usage: python3 execute_run_c.py <run_number>

Differences from scripts/execute_run.py (primary Condition A/B) and execute_run_b2.py:
- The worktree is checked out from each repo's condition-c-rXX-v1 tag (the physically
  restructured, already-committed CODEMANIFEST forest -- see architecture_v2/<repo>/
  RESTRUCTURE_REPORT.md) instead of the original pinned commit. No overlay step is needed or
  performed: the treatment IS the base commit itself, not a copy layered on top of it.
- No live Goga tooling exposure (build_env, not build_env_b's PATH-with-~/.local/bin):
  Condition C isolates "does a physically real, fully realized architecture change outcomes",
  matching Condition B's "structure present but not actively prompted" treatment intensity --
  not B'/B''s "live tool access" axis, which is a separate, already-answered question.
- The task prompt is used verbatim, with no added sentence, matching primary Condition B.
- Writes to results/runs_experiment_c.csv and runs_experiment_c/<run_id>/, entirely separate
  from every other condition's results, per TREATMENT_DESIGN_EXPERIMENT_B.md Sec.3's "never
  pooled" rule.
- Gracefully SKIPs (not VALID, not ERROR -- a distinct, cheap, zero-cost status) any row whose
  repo doesn't yet have a condition-c-rXX-v1 tag in its base clone, rather than crashing the
  whole batch. R08 and R10's tags were lost mid-session (git-clone/worktree mixup: their
  restructuring work was done in an independent `git clone`, not a `git worktree add` like every
  other repo, so the commits/tags never became reachable from the shared base clone, and were
  destroyed when that clone's directory was deleted during a disk-space cleanup) and are being
  reconstructed separately from the batch-agent transcripts that authored them (see STATUS.md).
  Once a repo's tag exists, re-running scripts/run_batch_c.sh picks its rows up automatically --
  a SKIPPED status (unlike VALID) does not satisfy run_batch_c.sh's resume-skip grep, so already
  "skipped" rows are retried for free on every subsequent pass until the tag is there.

Everything else (worktree-per-run, no manual rescue, timeout, budget, validator re-use,
disk-space guard, rate-limit/transport-error retry, flock'd CSV writes) is identical to
scripts/execute_run.py and its pure helper functions are imported directly from there.
"""
import csv
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from execute_run import (  # noqa: E402
    sh, parse_verdict, free_disk_gb, clean_xcode_caches, wait_for_disk_space,
    link_shared_deps, run_validators, build_env, acquire_xcode_lock, release_xcode_lock,
    BASE_CLONES, TIMEOUT_SECONDS, MAX_BUDGET_USD, MODEL,
)

BENCH_ROOT = Path(__file__).resolve().parent.parent
SCRATCH_BASE = Path("/Users/marinaoreshina/UK_Talant_Visa/Highload/benchmark-scratch")
SCRATCH_ROOT = SCRATCH_BASE / "runs_c"

CONDITION_C_TAGS = {f"R{i:02d}": f"condition-c-r{i:02d}-v1" for i in range(1, 11)}


def load_plan_row_c(run_number):
    with open(BENCH_ROOT / "experiment_plan_c.csv") as f:
        for row in csv.DictReader(f):
            if int(row["run_number"]) == run_number:
                return row
    raise ValueError(f"run_number {run_number} not found in experiment_plan_c.csv")


def tag_exists(base_clone, tag):
    r = subprocess.run(["git", "rev-parse", "--verify", "-q", f"{tag}^{{commit}}"],
                        cwd=base_clone, capture_output=True, text=True)
    return r.returncode == 0


def write_skipped_row(results_csv, run_id, repo_id, task_letter, row, reason):
    import fcntl
    lock_path = results_csv.parent / f".{results_csv.name}.lock"
    fieldnames = ["run_id", "repository", "task", "task_type", "condition", "repetition",
                  "functional_success", "architecture_conformance_rate", "full_architecture_conformance",
                  "dangerous_success", "architecture_checks_passed", "architecture_checks_failed",
                  "goga_engagement_signal", "duration_ms", "tokens_input", "tokens_output",
                  "tool_calls_num_turns", "files_changed", "cost_usd", "model_used", "timeout",
                  "invalid", "status", "timestamp"]
    results_csv.parent.mkdir(parents=True, exist_ok=True)
    lock_file = open(lock_path, "w")
    fcntl.flock(lock_file, fcntl.LOCK_EX)
    is_new = not results_csv.exists() or results_csv.stat().st_size == 0
    with open(results_csv, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if is_new:
            writer.writeheader()
        writer.writerow({
            "run_id": run_id, "repository": repo_id, "task": task_letter,
            "task_type": row["task_type"], "condition": "goga_native_architecture",
            "repetition": row["repetition"],
            "functional_success": None, "architecture_conformance_rate": None,
            "full_architecture_conformance": None, "dangerous_success": None,
            "architecture_checks_passed": None, "architecture_checks_failed": None,
            "goga_engagement_signal": None, "duration_ms": None,
            "tokens_input": None, "tokens_output": None, "tool_calls_num_turns": None,
            "files_changed": None, "cost_usd": 0, "model_used": None,
            "timeout": False, "invalid": False, "status": "SKIPPED",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        })
    fcntl.flock(lock_file, fcntl.LOCK_UN)
    lock_file.close()
    print(f"[{run_id}] SKIPPED -- {reason}")


def main():
    run_number = int(sys.argv[1])
    row = load_plan_row_c(run_number)
    repo_id = row["repository"]
    task_letter = row["task"]
    run_id = row["run_id"]
    condition = "goga_native_architecture"

    if len(sys.argv) > 2 and sys.argv[2] == "--replacement":
        suffix = sys.argv[3] if len(sys.argv) > 3 else "1"
        run_id = f"{run_id}-RETRY{suffix}"

    results_csv = BENCH_ROOT / "results" / "runs_experiment_c.csv"
    base_clone = BASE_CLONES[repo_id]
    tag = CONDITION_C_TAGS[repo_id]

    # Check tag existence BEFORE the (up to 30-minute) disk-space wait: a row whose repo's
    # tag doesn't exist yet (R08/R10, mid-reconstruction) should skip instantly, not pay the
    # same disk-wait cost as a real run only to skip anyway.
    if not tag_exists(base_clone, tag):
        write_skipped_row(results_csv, run_id, repo_id, task_letter, row,
                           f"tag {tag} not found in {base_clone} yet")
        return

    wait_for_disk_space(min_gb=10.0)

    run_dir = BENCH_ROOT / "runs_experiment_c" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "environment.json").write_text(json.dumps({
        "run_id": run_id, "repository": repo_id, "task": task_letter,
        "condition": condition, "model_requested": MODEL, "timeout_seconds": TIMEOUT_SECONDS,
        "max_budget_usd": MAX_BUDGET_USD, "base_tag": tag,
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }, indent=2))

    worktree = SCRATCH_ROOT / run_id
    SCRATCH_ROOT.mkdir(parents=True, exist_ok=True)
    if worktree.exists():
        shutil.rmtree(worktree, ignore_errors=True)

    status = "UNKNOWN"
    metrics = {}
    func_res = {}
    arch_res = {}
    xcode_lock = acquire_xcode_lock(repo_id)
    try:
        sh(["git", "worktree", "prune"], cwd=base_clone, check=False)
        if worktree.exists():
            shutil.rmtree(worktree, ignore_errors=True)
        sh(["git", "worktree", "add", "--detach", str(worktree), tag], cwd=base_clone)
        link_shared_deps(worktree, base_clone)

        prompt_path = BENCH_ROOT / "tasks" / repo_id / f"task_{task_letter}.md"
        prompt_text = prompt_path.read_text()
        (run_dir / "prompt.txt").write_text(prompt_text)

        env = build_env(repo_id)
        max_retries = 66
        retry_wait_s = 300
        for attempt in range(max_retries):
            t0 = time.time()
            proc = subprocess.run(
                ["claude", "-p", prompt_text,
                 "--model", MODEL,
                 "--permission-mode", "bypassPermissions",
                 "--output-format", "json",
                 "--no-session-persistence",
                 "--max-budget-usd", MAX_BUDGET_USD],
                cwd=worktree, env=env, capture_output=True, text=True, timeout=TIMEOUT_SECONDS,
            )
            agent_time = time.time() - t0
            try:
                agent_json = json.loads(proc.stdout)
            except json.JSONDecodeError:
                agent_json = {"is_error": True, "result": "PARSE_ERROR", "raw_stdout_tail": proc.stdout[-2000:]}

            result_text = str(agent_json.get("result", "")).lower()
            hit_rate_limit = (
                agent_json.get("is_error")
                and agent_json.get("total_cost_usd", 0) == 0
                and ("session limit" in result_text or agent_json.get("api_error_status") == 429)
            )
            hit_transport_error = (
                agent_json.get("is_error")
                and ("connection closed" in result_text or "api error" in result_text)
                and not hit_rate_limit
            )
            max_transport_retries = 3
            if hit_rate_limit and attempt < max_retries - 1:
                print(f"[{run_id}] hit session/usage limit ('{agent_json.get('result')}'), "
                      f"waiting {retry_wait_s}s before retry {attempt + 1}/{max_retries}...")
                time.sleep(retry_wait_s)
                continue
            if hit_transport_error and attempt < max_transport_retries:
                print(f"[{run_id}] transport error ('{agent_json.get('result')}'), "
                      f"resetting worktree and retrying ({attempt + 1}/{max_transport_retries})...")
                sh(["git", "checkout", "--", "."], cwd=worktree, check=False)
                sh(["git", "clean", "-fd"], cwd=worktree, check=False)
                time.sleep(20)
                continue
            break

        (run_dir / "agent.log").write_text(proc.stdout)
        (run_dir / "stderr.log").write_text(proc.stderr)

        status_res_uall = sh(["git", "status", "--short", "--untracked-files=all"], cwd=worktree, check=False)
        sh(["git", "add", "-A"], cwd=worktree, check=False)
        diff_res = sh(["git", "diff", "--cached"], cwd=worktree, check=False)
        (run_dir / "git.diff").write_text(diff_res.stdout)
        (run_dir / "git.status").write_text(status_res_uall.stdout)
        changed_files = [l[3:] for l in status_res_uall.stdout.splitlines() if l.strip()]
        (run_dir / "changed_files.txt").write_text("\n".join(changed_files))

        val_env = build_env(repo_id)
        all_res = run_validators(worktree, repo_id, task_letter, val_env)
        func_res = {"functional": all_res.pop("functional")}
        arch_res = all_res

        arch_checks_total = len(arch_res)
        arch_checks_passed = sum(1 for v in arch_res.values() if v["verdict"] == "PASS")
        arch_checks_manual = sum(1 for v in arch_res.values() if v["verdict"] == "MANUAL_REVIEW")
        full_arch_conformance = (arch_checks_total > 0) and all(v["verdict"] in ("PASS",) for v in arch_res.values())
        acr = (arch_checks_passed / arch_checks_total) if arch_checks_total else None

        functional_success = func_res["functional"]["verdict"] == "PASS"
        dangerous_success = bool(functional_success and arch_checks_total and not full_arch_conformance)

        result_lower = str(agent_json.get("result", "")).lower()
        goga_engagement_signal = any(kw in result_lower for kw in (
            "goga lint", "goga schema", "goga contract", "goga brainstorm", "goga build",
            "goga apply", "goga pipeline", "goga-brainstorm", "goga-apply", "goga-change",
        ))

        metrics = {
            "is_error": agent_json.get("is_error"),
            "duration_ms": agent_json.get("duration_ms"),
            "num_turns": agent_json.get("num_turns"),
            "total_cost_usd": agent_json.get("total_cost_usd"),
            "usage": agent_json.get("usage", {}),
            "model_used": list(agent_json.get("modelUsage", {}).keys()),
            "session_id": agent_json.get("session_id"),
            "agent_wall_time_s": agent_time,
            "files_changed": len(changed_files),
            "architecture_checks_total": arch_checks_total,
            "architecture_checks_passed": arch_checks_passed,
            "architecture_checks_manual_review": arch_checks_manual,
            "architecture_conformance_rate": acr,
            "full_architecture_conformance": full_arch_conformance,
            "functional_success": functional_success,
            "dangerous_success": dangerous_success,
            "goga_engagement_signal": goga_engagement_signal,
        }
        (run_dir / "metrics.json").write_text(json.dumps(metrics, indent=2, default=str))
        (run_dir / "functional_results.json").write_text(json.dumps(func_res, indent=2))
        (run_dir / "architecture_results.json").write_text(json.dumps(arch_res, indent=2))
        (run_dir / "result.md").write_text(
            f"# {run_id}\n\nCondition: {condition}\nBase tag: {tag}\n"
            f"Functional success: {functional_success}\n"
            f"Full architecture conformance: {full_arch_conformance}\nACR: {acr}\n"
            f"Dangerous success: {dangerous_success}\nGoga engagement signal: {goga_engagement_signal}\n"
            f"Cost: ${agent_json.get('total_cost_usd')}\n"
            f"Duration: {agent_json.get('duration_ms')}ms, turns: {agent_json.get('num_turns')}\n\n"
            f"## Agent's own summary\n\n{agent_json.get('result', '')}\n"
        )
        status = "ERROR" if agent_json.get("is_error") else "VALID"

    except subprocess.TimeoutExpired:
        status = "TIMEOUT"
        (run_dir / "result.md").write_text(f"# {run_id}\n\nSTATUS: TIMEOUT after {TIMEOUT_SECONDS}s\n")
    except Exception as e:
        status = "INVALID"
        (run_dir / "result.md").write_text(f"# {run_id}\n\nSTATUS: INVALID\nREASON: {e}\n")
    finally:
        try:
            sh(["git", "worktree", "remove", "--force", str(worktree)], cwd=base_clone, check=False)
        except Exception:
            shutil.rmtree(worktree, ignore_errors=True)
        release_xcode_lock(xcode_lock)

    results_csv.parent.mkdir(parents=True, exist_ok=True)
    lock_path = results_csv.parent / ".runs_experiment_c.csv.lock"
    fieldnames = ["run_id", "repository", "task", "task_type", "condition", "repetition",
                  "functional_success", "architecture_conformance_rate", "full_architecture_conformance",
                  "dangerous_success", "architecture_checks_passed", "architecture_checks_failed",
                  "goga_engagement_signal", "duration_ms", "tokens_input", "tokens_output",
                  "tool_calls_num_turns", "files_changed", "cost_usd", "model_used", "timeout",
                  "invalid", "status", "timestamp"]
    import fcntl
    lock_file = open(lock_path, "w")
    fcntl.flock(lock_file, fcntl.LOCK_EX)
    is_new = not results_csv.exists() or results_csv.stat().st_size == 0
    with open(results_csv, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if is_new:
            writer.writeheader()
        writer.writerow({
            "run_id": run_id, "repository": repo_id, "task": task_letter,
            "task_type": row["task_type"], "condition": condition, "repetition": row["repetition"],
            "functional_success": metrics.get("functional_success"),
            "architecture_conformance_rate": metrics.get("architecture_conformance_rate"),
            "full_architecture_conformance": metrics.get("full_architecture_conformance"),
            "dangerous_success": metrics.get("dangerous_success"),
            "architecture_checks_passed": metrics.get("architecture_checks_passed"),
            "architecture_checks_failed": (metrics.get("architecture_checks_total", 0) - metrics.get("architecture_checks_passed", 0)) if metrics.get("architecture_checks_total") is not None else None,
            "goga_engagement_signal": metrics.get("goga_engagement_signal"),
            "duration_ms": metrics.get("duration_ms"),
            "tokens_input": metrics.get("usage", {}).get("input_tokens"),
            "tokens_output": metrics.get("usage", {}).get("output_tokens"),
            "tool_calls_num_turns": metrics.get("num_turns"),
            "files_changed": metrics.get("files_changed"),
            "cost_usd": metrics.get("total_cost_usd"),
            "model_used": ",".join(metrics.get("model_used", [])) if metrics.get("model_used") else None,
            "timeout": status == "TIMEOUT",
            "invalid": status == "INVALID",
            "status": status,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        })
    fcntl.flock(lock_file, fcntl.LOCK_UN)
    lock_file.close()

    print(f"[{run_id}] status={status} functional_success={metrics.get('functional_success')} "
          f"full_arch_conformance={metrics.get('full_architecture_conformance')} "
          f"dangerous_success={metrics.get('dangerous_success')} cost=${metrics.get('total_cost_usd')}")


if __name__ == "__main__":
    main()
