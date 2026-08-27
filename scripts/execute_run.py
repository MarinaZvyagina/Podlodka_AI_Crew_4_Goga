#!/usr/bin/env python3
"""
Phase 10 execution engine: runs exactly one row of experiment_plan.csv end-to-end.

Usage: python3 execute_run.py <run_number>

Per PROTOCOL.md / experiment.yaml:
- Clean-room worktree from the pinned commit (git worktree add, from the shared base clone).
- Goga condition: overlay that repository's frozen architecture/R0X/**/CODEMANIFEST forest +
  the shared ARCHITECTURE_CONTRACTS.md pointer file. Baseline condition: neither.
- Launch `claude -p` non-interactively, bypassPermissions, pinned model/timeout/budget.
- Run the task's functional validator + all its architecture validators against the real diff.
- Save all raw artifacts under runs/<run_id>/. Append one row to results/runs.csv.
- Clean up the worktree unconditionally (even on failure).
"""
import csv
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

BENCH_ROOT = Path("/Users/marinaoreshina/UK_Talant_Visa/Highload/architecture-agent-benchmark")
SCRATCH_ROOT = Path("/tmp/benchmark-runs")
BASE_CLONES = {
    "R01": Path("/tmp/benchmark-repos/R01"),
    "R02": Path("/tmp/benchmark-repos/R02"),
    "R03": Path("/tmp/benchmark-repos/R03/base"),
    "R04": Path("/tmp/benchmark-repos/R04"),
    "R05": Path("/tmp/benchmark-repos/R05"),
    "R06": Path("/tmp/benchmark-repos/R06"),
    "R07": Path("/tmp/benchmark-repos/R07"),
    "R08": Path("/tmp/benchmark-repos/R08"),
    "R09": Path("/tmp/benchmark-repos/R09"),
    "R10": Path("/tmp/benchmark-repos/R10"),
}
COMMITS = {
    "R01": "936f28e28cbcd4e9e146cbc076c54933517a92eb",
    "R02": "dd3fe66070a465d045efd6120e0f34e47f3672c2",
    "R03": "f94e9eb15ba2a22f69aef234cb81333764d0b298",
    "R04": "e160ff7ba0641fba729c528482de5277ffb19c58",
    "R05": "f65ae841ace8f686ddc0dc17fe936d0bf38e568c",
    "R06": "23a4e406a2e70a807486b4c40a9e24da493886bf",
    "R07": "ac249e3668a57f24782a49218834064459ba2d09",
    "R08": "441ba42c3f3175476a1f54eba8e72d8d6d304db7",
    "R09": "de940072da700c2af7d74348b5775674d106d503",
    "R10": "6e3a059f752785b349d5938dfa4c36f216fb0ae3",
}
# Per-repo extra env vars needed for validators/build tools
EXTRA_ENV = {
    "R07": {
        "JAVA_HOME": "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
        "ANDROID_SDK_ROOT": "/opt/homebrew/share/android-commandlinetools",
        "ANDROID_HOME": "/opt/homebrew/share/android-commandlinetools",
    },
    "R08": {
        "JAVA_HOME": "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
        "ANDROID_SDK_ROOT": "/opt/homebrew/share/android-commandlinetools",
        "ANDROID_HOME": "/opt/homebrew/share/android-commandlinetools",
    },
}

TIMEOUT_SECONDS = 3600
MAX_BUDGET_USD = "8"
MODEL = "claude-sonnet-5"


def sh(cmd, cwd=None, env=None, timeout=None, check=True):
    result = subprocess.run(
        cmd, cwd=cwd, env=env, shell=isinstance(cmd, str),
        capture_output=True, text=True, timeout=timeout,
    )
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed ({result.returncode}): {cmd}\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}")
    return result


def load_plan_row(run_number):
    with open(BENCH_ROOT / "experiment_plan.csv") as f:
        for row in csv.DictReader(f):
            if int(row["run_number"]) == run_number:
                return row
    raise ValueError(f"run_number {run_number} not found in experiment_plan.csv")


def build_env(repo_id):
    env = os.environ.copy()
    extra = EXTRA_ENV.get(repo_id, {})
    for k, v in extra.items():
        env[k] = v
        if k == "JAVA_HOME":
            env["PATH"] = f"{v}/bin:" + env.get("PATH", "")
    env["PATH"] = f"{os.path.expanduser('~/.local/bin')}:" + env.get("PATH", "")
    return env


def link_shared_deps(worktree, base_clone):
    """
    Git worktrees only share .git (objects/refs) -- each worktree gets a fresh working
    directory with no node_modules/.venv/etc. Re-installing dependencies from scratch for
    every one of 800 runs is far too slow and, for large repos, disk-prohibitive. Since
    dependencies for a given pinned commit are identical across every run of that repo,
    hard-link-copy any already-installed dependency directory from the shared base clone
    into the fresh worktree: `cp -al` creates new directory entries pointing at the same
    underlying inodes, so this costs almost no extra disk space, while still giving each
    worktree its own directory tree (a `rm`/rename-and-replace inside the worktree, which is
    how npm/pip/etc. normally update a file, safely diverges from the shared original;
    only an in-place truncate+rewrite of the exact same inode would leak across worktrees,
    which is not how these package managers operate).
    """
    for dep_dir in ("node_modules", ".venv", "Pods"):
        src = base_clone / dep_dir
        if src.is_dir():
            dest = worktree / dep_dir
            subprocess.run(["cp", "-al", str(src), str(dest)], check=False)


def overlay_goga_treatment(worktree, repo_id):
    arch_dir = BENCH_ROOT / "architecture" / repo_id
    count = 0
    for codemanifest in arch_dir.rglob("CODEMANIFEST"):
        rel = codemanifest.relative_to(arch_dir)
        dest = worktree / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(codemanifest, dest)
        count += 1
    shutil.copy2(BENCH_ROOT / "architecture" / "ARCHITECTURE_CONTRACTS.md", worktree / "ARCHITECTURE_CONTRACTS.md")
    return count


def parse_verdict(out):
    """
    Validator scripts print diagnostic output first, then a final verdict line
    starting with PASS:/FAIL:/MANUAL REVIEW REQUIRED. Scan from the end for the last
    line that actually declares a verdict -- do NOT just check out.startswith(...),
    since the diagnostic preamble routinely contains the substring "PASS" (e.g.
    quoting a class name found, or a PASS-in-context sentence) before the real
    verdict line appears.
    """
    for line in reversed(out.splitlines()):
        stripped = line.strip()
        upper = stripped.upper()
        if upper.startswith("PASS"):
            return "PASS"
        if upper.startswith("MANUAL REVIEW"):
            return "MANUAL_REVIEW"
        if upper.startswith("FAIL"):
            return "FAIL"
    return "FAIL"  # no recognizable verdict line at all -> treat conservatively as FAIL


def run_validators(worktree, repo_id, task_letter, env):
    val_dir = BENCH_ROOT / "tasks" / repo_id / "validators"
    results = {}
    # architecture checks
    for script in sorted(val_dir.glob(f"task_{task_letter}_AC*.sh")):
        name = script.stem
        try:
            r = sh(["bash", str(script), str(worktree)], env=env, timeout=600, check=False)
            out = (r.stdout + r.stderr).strip()
            verdict = parse_verdict(out)
        except subprocess.TimeoutExpired:
            verdict, out = "TIMEOUT", "validator timed out"
        results[name] = {"verdict": verdict, "output": out[:4000]}
    # functional check
    func_script = val_dir / f"task_{task_letter}_functional.sh"
    if func_script.exists():
        try:
            r = sh(["bash", str(func_script), str(worktree)], env=env, timeout=1800, check=False)
            out = (r.stdout + r.stderr).strip()
            fverdict = parse_verdict(out)
        except subprocess.TimeoutExpired:
            fverdict, out = "TIMEOUT", "functional validator timed out"
        results["functional"] = {"verdict": fverdict, "output": out[:4000]}
    else:
        results["functional"] = {"verdict": "MISSING", "output": "no functional validator found"}
    return results


def free_disk_gb():
    total, used, free = shutil.disk_usage("/")
    return free / (1024 ** 3)


def clean_xcode_caches():
    """
    Xcode DerivedData/CoreSimulator regrow every time an R09/R10 (Swift) run does a real
    build, and are by far the largest recurring disk consumer on this machine (repeatedly
    observed at 15-25GB each). The user explicitly approved clearing these as the standing
    fix for low disk space; automate it here so the 800-run batch is self-sufficient rather
    than needing a manual cleanup pass every time a Swift-heavy run pushes disk to the edge.
    Safe: DerivedData/simulator state is a rebuildable cache, never the user's own data.
    """
    subprocess.run(["rm", "-rf", os.path.expanduser("~/Library/Developer/Xcode/DerivedData")],
                    check=False)
    subprocess.run(["xcrun", "simctl", "delete", "unavailable"], check=False, capture_output=True)


def wait_for_disk_space(min_gb=3.0, max_wait_s=1800, poll_s=30):
    """
    Running two heavy batches concurrently (or one very large repo mid-checkout) can
    exhaust disk fast enough to corrupt an in-flight `git worktree add` (observed: a real
    "No space left on device" mid-checkout failure). Rather than starting a run that's
    likely to fail this way, pause and let concurrent cleanup (other runs finishing) free
    space back up, for up to max_wait_s before proceeding anyway.
    """
    if free_disk_gb() < min_gb:
        print(f"Low disk ({free_disk_gb():.1f}GB free) -- clearing Xcode DerivedData/simulator caches...")
        clean_xcode_caches()
    waited = 0
    while free_disk_gb() < min_gb and waited < max_wait_s:
        print(f"Low disk ({free_disk_gb():.1f}GB free, need >{min_gb}GB) -- waiting {poll_s}s...")
        time.sleep(poll_s)
        waited += poll_s


def main():
    wait_for_disk_space(min_gb=6.0)
    run_number = int(sys.argv[1])
    row = load_plan_row(run_number)
    repo_id = row["repository"]
    task_letter = row["task"]
    condition = row["condition"]
    run_id = row["run_id"]

    # Optional replacement-run suffix (PROTOCOL.md §15): if an original run went INVALID
    # due to an infrastructure problem, re-run the exact same experiment_plan.csv row under
    # a new run_id rather than silently overwriting/deleting the invalid record.
    if len(sys.argv) > 2 and sys.argv[2] == "--replacement":
        suffix = sys.argv[3] if len(sys.argv) > 3 else "1"
        run_id = f"{run_id}-RETRY{suffix}"

    run_dir = BENCH_ROOT / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "environment.json").write_text(json.dumps({
        "run_id": run_id, "repository": repo_id, "task": task_letter,
        "condition": condition, "model_requested": MODEL, "timeout_seconds": TIMEOUT_SECONDS,
        "max_budget_usd": MAX_BUDGET_USD, "started_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }, indent=2))

    base_clone = BASE_CLONES[repo_id]
    commit = COMMITS[repo_id]
    worktree = SCRATCH_ROOT / run_id
    SCRATCH_ROOT.mkdir(parents=True, exist_ok=True)
    if worktree.exists():
        shutil.rmtree(worktree, ignore_errors=True)

    status = "UNKNOWN"
    metrics = {}
    func_res = {}
    arch_res = {}
    try:
        # 1. Clean-room worktree. Self-heal first: if a previous run for this exact run_id
        # was SIGKILLed mid-flight (e.g. the batch process was force-stopped), Python's
        # `finally` cleanup below never got to run, leaving a stale "registered but missing"
        # worktree entry that would otherwise make `git worktree add` fail here every time.
        sh(["git", "worktree", "prune"], cwd=base_clone, check=False)
        if worktree.exists():
            shutil.rmtree(worktree, ignore_errors=True)
        sh(["git", "worktree", "add", "--detach", str(worktree), commit], cwd=base_clone)
        link_shared_deps(worktree, base_clone)

        # 2. Goga treatment overlay — committed as its own throwaway commit so that every
        # later "diff since HEAD" (ours and the validators') isolates the agent's own
        # contribution from the treatment artifacts themselves.
        codemanifest_count = 0
        if condition == "goga":
            codemanifest_count = overlay_goga_treatment(worktree, repo_id)
            sh(["git", "add", "-A"], cwd=worktree)
            sh(["git", "-c", "user.name=Goga Treatment", "-c", "user.email=goga@localhost",
                "commit", "-q", "-m", "Goga condition: apply frozen architecture forest"], cwd=worktree)

        # 3. Task prompt
        prompt_path = BENCH_ROOT / "tasks" / repo_id / f"task_{task_letter}.md"
        prompt_text = prompt_path.read_text()
        (run_dir / "prompt.txt").write_text(prompt_text)

        # 4. Launch claude -p. If the account's own usage/session limit is hit, this fails
        # instantly with zero cost/tokens consumed -- nothing real was attempted, so this is
        # an infrastructure block, not a data point. Retry with backoff (up to ~5.5 hours,
        # comfortably past the observed 5-hour rolling window) rather than recording a
        # spurious $0 ERROR row that would otherwise need a manual replacement run.
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
            # "Connection closed mid-response" is a transport-level failure seen throughout
            # this whole benchmark project (affecting subagents in every prior phase too) --
            # an infrastructure hiccup unrelated to the model's actual task performance, not
            # a real attempt at the task. Unlike the rate-limit case this can strike with
            # real cost already incurred; reset the worktree to a clean state before retrying
            # so the retried attempt is still a genuine, independent clean-room run.
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

        # 5. Capture diff/status. Stage everything first so untracked new files (the norm,
        # not the exception, for real coding tasks) show up in the diff too -- `git diff`
        # alone only shows changes to already-tracked files. Diffing against HEAD isolates
        # just the agent's own work, since the Goga overlay (if any) was already committed
        # as its own commit in step 2, before the agent ever ran.
        status_res_uall = sh(["git", "status", "--short", "--untracked-files=all"], cwd=worktree, check=False)
        sh(["git", "add", "-A"], cwd=worktree, check=False)
        diff_res = sh(["git", "diff", "--cached"], cwd=worktree, check=False)
        (run_dir / "git.diff").write_text(diff_res.stdout)
        (run_dir / "git.status").write_text(status_res_uall.stdout)
        changed_files = [l[3:] for l in status_res_uall.stdout.splitlines() if l.strip()]
        (run_dir / "changed_files.txt").write_text("\n".join(changed_files))

        # 6. Validators
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

        metrics = {
            "is_error": agent_json.get("is_error"),
            "duration_ms": agent_json.get("duration_ms"),
            "num_turns": agent_json.get("num_turns"),
            "total_cost_usd": agent_json.get("total_cost_usd"),
            "usage": agent_json.get("usage", {}),
            "model_used": list(agent_json.get("modelUsage", {}).keys()),
            "session_id": agent_json.get("session_id"),
            "agent_wall_time_s": agent_time,
            "codemanifest_files_overlaid": codemanifest_count,
            "files_changed": len(changed_files),
            "architecture_checks_total": arch_checks_total,
            "architecture_checks_passed": arch_checks_passed,
            "architecture_checks_manual_review": arch_checks_manual,
            "architecture_conformance_rate": acr,
            "full_architecture_conformance": full_arch_conformance,
            "functional_success": functional_success,
            "dangerous_success": dangerous_success,
        }
        (run_dir / "metrics.json").write_text(json.dumps(metrics, indent=2, default=str))
        (run_dir / "functional_results.json").write_text(json.dumps(func_res, indent=2))
        (run_dir / "architecture_results.json").write_text(json.dumps(arch_res, indent=2))
        (run_dir / "result.md").write_text(
            f"# {run_id}\n\nCondition: {condition}\nFunctional success: {functional_success}\n"
            f"Full architecture conformance: {full_arch_conformance}\nACR: {acr}\n"
            f"Dangerous success: {dangerous_success}\nCost: ${agent_json.get('total_cost_usd')}\n"
            f"Duration: {agent_json.get('duration_ms')}ms, turns: {agent_json.get('num_turns')}\n\n"
            f"## Agent's own summary\n\n{agent_json.get('result', '')}\n"
        )
        status = "TIMEOUT" if False else ("ERROR" if agent_json.get("is_error") else "VALID")

    except subprocess.TimeoutExpired:
        status = "TIMEOUT"
        (run_dir / "result.md").write_text(f"# {run_id}\n\nSTATUS: TIMEOUT after {TIMEOUT_SECONDS}s\n")
    except Exception as e:
        status = "INVALID"
        (run_dir / "result.md").write_text(f"# {run_id}\n\nSTATUS: INVALID\nREASON: {e}\n")
    finally:
        # Always clean up the worktree
        try:
            sh(["git", "worktree", "remove", "--force", str(worktree)], cwd=base_clone, check=False)
        except Exception:
            shutil.rmtree(worktree, ignore_errors=True)

    # Append to results/runs.csv
    results_csv = BENCH_ROOT / "results" / "runs.csv"
    results_csv.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["run_id", "repository", "task", "task_type", "condition", "repetition",
                  "functional_success", "architecture_conformance_rate", "full_architecture_conformance",
                  "dangerous_success", "architecture_checks_passed", "architecture_checks_failed",
                  "duration_ms", "tokens_input", "tokens_output", "tool_calls_num_turns",
                  "files_changed", "cost_usd", "model_used", "timeout", "invalid", "status", "timestamp"]
    is_new = not results_csv.exists()
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

    print(f"[{run_id}] status={status} functional_success={metrics.get('functional_success')} "
          f"full_arch_conformance={metrics.get('full_architecture_conformance')} "
          f"dangerous_success={metrics.get('dangerous_success')} cost=${metrics.get('total_cost_usd')}")


if __name__ == "__main__":
    main()
