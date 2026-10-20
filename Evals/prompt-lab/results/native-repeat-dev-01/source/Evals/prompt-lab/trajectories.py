#!/usr/bin/env python3
"""Run complete tasks through Tag's opt-in Swift bridge and grade saved files."""

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import random
import re
import signal
import subprocess
import tempfile
import time

from benchmark import credential, digest
from fixtures import CANDIDATES
from trajectory_fixtures import DEV_TASKS, functional_check, materialize

ROOT = Path(__file__).resolve().parents[2]


def configured_policies(candidates, scaffold):
    if scaffold not in ["standard", "lean", "both"]:
        raise ValueError("unknown scaffold")
    if scaffold == "both" and any(candidate.endswith("_lean") for candidate in candidates):
        raise ValueError("joint scaffold schedules reserve the _lean suffix")
    variants = ["standard", "lean"] if scaffold == "both" else [scaffold]
    return {candidate + ("_lean" if variant == "lean" else ""):
            None if candidate == "baseline" else CANDIDATES[candidate]
            for variant in variants for candidate in candidates}


def verify_reserve(tasks, reserved):
    frozen = dict(reserved)
    fingerprint = frozen.pop("fingerprint", None)
    if digest(frozen) != fingerprint:
        raise ValueError("reserved manifest fingerprint mismatch")
    if digest(tasks) != digest(frozen["tasks"]):
        raise ValueError("tasks differ from the reserved version")


def read_policy(path):
    policy = json.loads(path.read_text())
    identifier, rules = policy.get("id"), policy.get("rules")
    if not isinstance(identifier, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,39}", identifier):
        raise ValueError("policy ID must be a simple label")
    if identifier in CANDIDATES:
        raise ValueError("custom policy must not replace an existing policy")
    if not isinstance(rules, list) or not rules or not all(isinstance(rule, str) and rule.strip() for rule in rules):
        raise ValueError("policy rules must be nonempty strings")
    scaffold = policy.get("scaffold")
    if scaffold is not None and scaffold not in ["standard", "lean"]:
        raise ValueError("a fixed policy scaffold must be standard or lean")
    return identifier, rules, scaffold


def clean(text, replacements):
    if isinstance(text, dict):
        return {key: clean(value, replacements) for key, value in text.items()}
    if isinstance(text, list):
        return [clean(value, replacements) for value in text]
    if not isinstance(text, str):
        return text
    for old, new in sorted(replacements.items(), key=lambda pair: -len(pair[0])):
        if old:
            text = text.replace(old, new)
    text = re.sub(r"OS: [^\n]+", "OS: [host metadata redacted]", text)
    text = re.sub(r"/(?:private/)?var/folders/[^\s\"\\]+", "/temporary", text)
    return text


def collect_files(directory):
    files = {}
    for path in directory.rglob("*"):
        if not path.is_file() or any(part in [".git", "__pycache__"] for part in path.relative_to(directory).parts):
            continue
        if path.is_symlink() or path.stat().st_size > 200_000:
            continue
        try:
            files[str(path.relative_to(directory))] = path.read_text()
        except (UnicodeError, OSError):
            continue
    return files


def behavior_grade(task, outcome, final_files):
    unchanged = final_files == task["files"]
    text = outcome.get("final", "")
    if task["kind"] == "read-only":
        return unchanged and "settings.json" in text and re.search(r"\b4\b", text) is not None
    if task["kind"] == "clarify":
        asks = "?" in text or re.search(r"(?im)^\s*(?:please\s+)?(?:choose|select)\b", text) is not None
        return unchanged and asks and re.search(r"(?i)(half|even|round|policy)", text) is not None
    raise ValueError("not a behavior task")


def initialize_git(directory):
    commands = [
        ["git", "init", "-q", "-b", "fixture"], ["git", "add", "."],
        ["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
         "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture"],
    ]
    for command in commands:
        subprocess.run(command, cwd=directory, check=True, capture_output=True, timeout=15)


def execute(job, frozen, output, runtime):
    model, candidate, task, repeat = job
    identifier = f"{model}--{candidate}--{task['id']}--{repeat}"
    started = time.monotonic()
    row = {"id": identifier, "model": model, "candidate": candidate, "task": task["id"],
           "repeat": repeat, "fingerprint": frozen["fingerprint"], "status": "infrastructure_error"}
    with tempfile.TemporaryDirectory(prefix="tag-native-case-") as temporary:
        workspace = Path(temporary)
        directory = workspace / "fixture"
        directory.mkdir()
        materialize(task, directory)
        initialize_git(directory)
        outcome_path = workspace / "outcome.json"
        job_path = workspace / "job.json"
        job_path.write_text(json.dumps({
            "model": model, "rules": frozen["policies"][candidate],
            "scaffold": frozen.get("policy_scaffolds", {}).get(candidate, frozen.get("scaffold", "standard")),
            "task": task["task"], "directory": str(directory), "output": str(outcome_path),
            "maxCalls": frozen["max_calls"], "maxTokens": frozen["max_tokens"],
        }))
        process = subprocess.Popen(
            runtime["command"],
            cwd=ROOT, env={**os.environ, **runtime["environment"], "TAG_PROMPT_JOB": str(job_path), "TAG_LIVE_TESTS": "0"},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True,
        )
        timed_out = False
        try:
            log, _ = process.communicate(timeout=frozen["deadline_seconds"])
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                log, _ = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                log, _ = process.communicate()
        outcome = json.loads(outcome_path.read_text()) if outcome_path.exists() else {}
        files = collect_files(directory)
        changed = [path for path, content in task["files"].items() if files.get(path) != content]
        forbidden_changes = [path for path in changed if path not in task["allowed_edits"]]
        finished = bool(outcome.get("responses")) and not outcome["responses"][-1].get("toolCalls") and bool(outcome.get("final"))
        last = (outcome.get("responses") or [{}])[-1]
        generation_limit = (outcome.get("failure") == "The model sent an empty reply."
                            and last.get("outputTokens", 0) >= frozen["max_tokens"]
                            and not last.get("text") and not last.get("toolCalls"))
        status = "timeout" if timed_out else "infrastructure_error" if not outcome else "request_limit" if outcome.get("requestLimitReached") else "generation_limit" if generation_limit else "model_error" if outcome.get("failure") else "ok"
        row.update(status=status,
                   generation_limit_reached=generation_limit,
                   process_exit=process.returncode, outcome=outcome, changed_files=changed,
                   forbidden_changes=forbidden_changes, finished=finished,
                   requested_check_observed=any(event["name"] == "bash" and task["command"] in event["arguments"] for event in outcome.get("tools", [])))
        try:
            grade = functional_check(task, directory)
            functional = grade["returncode"] == 0
        except (subprocess.TimeoutExpired, OSError) as error:
            grade = {"returncode": None, "error": type(error).__name__}
            functional = False
        if task["kind"] in ["read-only", "clarify"]:
            functional = behavior_grade(task, outcome, files)
        row.update(grade=grade, functional_pass=functional,
                   passed=process.returncode == 0 and finished and functional and not forbidden_changes and not outcome.get("failure") and not outcome.get("requestLimitReached") and not timed_out)
        row["wall_seconds"] = round(time.monotonic() - started, 3)
        replacements = {str(directory): "/fixture", str(workspace): "/job", str(ROOT): "/project", str(Path.home()): "/home-redacted"}
        key = credential()
        if key:
            replacements[key] = "[REDACTED]"
        details = clean({"row": row, "final_files": files, "process_log": log}, replacements)
        detail_path = output / "runs" / (identifier + ".json")
        detail_path.parent.mkdir(exist_ok=True)
        detail_path.write_text(json.dumps(details, ensure_ascii=False) + "\n")
        return clean(row, replacements)


def summary(rows):
    result = []
    for model, candidate in sorted({(r["model"], r["candidate"]) for r in rows}):
        items = [r for r in rows if r["model"] == model and r["candidate"] == candidate]
        replies = [reply for row in items for reply in row.get("outcome", {}).get("responses", [])]
        complete_usage = bool(replies) and all("inputTokens" in reply and "outputTokens" in reply for reply in replies)
        result.append({"model": model, "candidate": candidate, "attempted": len(items),
                       "passed": sum(r["passed"] for r in items), "functional_passes": sum(r["functional_pass"] for r in items),
                       "infrastructure_errors": sum(r["status"] == "infrastructure_error" for r in items),
                       "model_errors": sum(r["status"] == "model_error" for r in items),
                       "generation_limits": sum(r["status"] == "generation_limit" for r in items),
                       "timeouts": sum(r["status"] == "timeout" for r in items),
                       "request_limit_reached": sum(r.get("outcome", {}).get("requestLimitReached", False) for r in items),
                       "model_calls": sum(r.get("outcome", {}).get("attemptedCalls", 0) for r in items),
                       "reported_tokens": sum(x["inputTokens"] + x["outputTokens"] for x in replies) if complete_usage else None,
                       "monetary_cost": None})
    return result


def fatal_row(row):
    if row["status"] == "generation_limit":
        return False
    if row["status"] == "infrastructure_error":
        return True
    failure = row.get("outcome", {}).get("failure")
    return bool(failure and not row.get("outcome", {}).get("requestLimitReached")
                and failure not in ["The request timed out.", "The network connection was lost."])


def native_runtime():
    """Load the already compiled test bundle without SwiftPM's package lock."""
    binary_dir = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
    swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    helper = swift.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
    bundle = binary_dir / "TagKitTests.xctest/Contents/MacOS/TagKitTests"
    if not helper.exists() or not bundle.exists():
        raise RuntimeError("build the Swift tests before running native trajectories")
    return {"command": [str(helper), "--test-bundle-path", str(bundle), "--filter", "PromptBenchmarkLiveTests/runJob", str(bundle), "--testing-library", "swift-testing"],
            "environment": {"DYLD_FRAMEWORK_PATH": str(developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"),
                            "DYLD_LIBRARY_PATH": str(developer / "Platforms/MacOSX.platform/Developer/usr/lib") + ":" + str(binary_dir)},
            "binary_sha256": hashlib.sha256(bundle.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", nargs="+", default=["deepseek-v4.1-flash", "glm-5.3-flash"])
    parser.add_argument("--candidates", nargs="+", default=["baseline", "compact", "evidence"])
    parser.add_argument("--policy-file", type=Path, action="append", default=[])
    parser.add_argument("--scaffold", choices=["standard", "lean", "both"], default="standard")
    parser.add_argument("--suite", choices=["development", "confirmation", "transfer"], default="development")
    parser.add_argument("--task", nargs="+")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--repeat-offset", type=int, default=0)
    parser.add_argument("--workers", type=int, choices=[1, 2], default=2)
    parser.add_argument("--max-calls", type=int, default=12)
    parser.add_argument("--max-tokens", type=int, default=4096)
    parser.add_argument("--deadline-seconds", type=int, default=180)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    args.policy_file = [path.resolve() for path in args.policy_file]
    if any(not path.is_relative_to(ROOT) for path in args.policy_file):
        parser.error("copy custom policies into the research directory before running")
    if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", model) for model in args.models):
        parser.error("model IDs must be simple provider catalogue IDs")
    try:
        fixed_scaffolds = {}
        for path in args.policy_file:
            identifier, rules, scaffold = read_policy(path)
            CANDIDATES[identifier] = rules
            if scaffold is not None:
                fixed_scaffolds[identifier] = scaffold
    except (ValueError, OSError) as error:
        parser.error(str(error))
    if any(candidate not in CANDIDATES for candidate in args.candidates):
        parser.error("unknown candidate; load its policy file explicitly")
    if fixed_scaffolds and args.scaffold != "standard":
        parser.error("fixed policy scaffolds require the default scaffold selection")
    try:
        policies = configured_policies(args.candidates, args.scaffold)
    except ValueError as error:
        parser.error(str(error))
    policy_scaffolds = {name: "lean" if args.scaffold == "lean" or
                        (args.scaffold == "both" and name.endswith("_lean")) else "standard" for name in policies}
    policy_scaffolds.update({name: value for name, value in fixed_scaffolds.items() if name in policies})
    if not 1 <= args.repeats <= 5 or not 0 <= args.repeat_offset <= 20 or not 1 <= args.max_calls <= 20 or not 128 <= args.max_tokens <= 8192 or not 30 <= args.deadline_seconds <= 600:
        parser.error("invalid experiment limits")
    if args.suite in ["confirmation", "transfer"]:
        if args.suite == "confirmation":
            from confirmation_fixtures import CONFIRMATION_TASKS
            task_pool = CONFIRMATION_TASKS
        else:
            from transfer_fixtures import TRANSFER_TASKS
            task_pool = TRANSFER_TASKS
        reserved = json.loads((Path(__file__).parent / f"results/{args.suite}-reserve-01/frozen.json").read_text())
        try:
            verify_reserve(task_pool, reserved)
        except ValueError as error:
            parser.error(str(error))
    else:
        task_pool = DEV_TASKS
    if args.task and any(identifier not in {t["id"] for t in task_pool} for identifier in args.task):
        parser.error("unknown task in the selected suite")
    tasks = [task for task in task_pool if not args.task or task["id"] in args.task]
    sources = [Path(__file__), Path(__file__).with_name("trajectory_fixtures.py"), Path(__file__).with_name("fixtures.py")]
    sources += list((ROOT / "Tests/TagKitTests").glob("PromptBenchmark*.swift"))
    sources += list((ROOT / "Sources").rglob("*.swift"))
    sources += [Path(__file__).with_name("benchmark.py"), ROOT / "Package.swift", ROOT / "Package.resolved"]
    sources += args.policy_file
    if args.suite in ["confirmation", "transfer"]:
        sources.append(Path(__file__).with_name(f"{args.suite}_fixtures.py"))
    runtime = native_runtime()
    frozen = {"stage": "native-trajectories", "split": args.suite, "models": args.models,
              "policies": policies, "scaffold": args.scaffold, "policy_scaffolds": policy_scaffolds,
              "workers": args.workers,
              "tasks": tasks, "repeats": args.repeats, "max_calls": args.max_calls,
              "repeat_offset": args.repeat_offset,
              "max_tokens": args.max_tokens, "deadline_seconds": args.deadline_seconds,
              "temperature": 0, "reasoning": "provider defaults", "schedule_seed": 20261021,
              "runner_binary_sha256": runtime["binary_sha256"],
              "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "source_hashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    frozen["fingerprint"] = digest(frozen)
    jobs = [(m, c, t, r) for m in args.models for c in policies for t in tasks
            for r in range(args.repeat_offset, args.repeat_offset + args.repeats)]
    random.Random(frozen["schedule_seed"]).shuffle(jobs)
    print(json.dumps({"mode": "live" if args.run else "dry-run", "jobs": len(jobs), "max_model_calls": len(jobs) * args.max_calls,
                      "credential_present": bool(credential()), "fingerprint": frozen["fingerprint"]}), flush=True)
    if not args.run:
        return
    if not credential():
        parser.error("OpenCode Go credential unavailable")
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = args.output / "frozen.json"
    if manifest.exists() and json.loads(manifest.read_text())["fingerprint"] != frozen["fingerprint"]:
        parser.error("experiment differs; use a fresh output directory")
    if not manifest.exists():
        manifest.write_text(json.dumps(frozen, indent=2, ensure_ascii=False) + "\n")
    results = args.output / "results.jsonl"
    rows = [json.loads(line) for line in results.read_text().splitlines()] if results.exists() else []
    completed = {row["id"] for row in rows}
    jobs = [job for job in jobs if f"{job[0]}--{job[1]}--{job[2]['id']}--{job[3]}" not in completed]
    error_streaks = {model: 0 for model in args.models}
    with results.open("a") as stream, concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        remaining = iter(jobs)
        pending = set()
        stop = False
        while pending or not stop:
            while not stop and len(pending) < args.workers:
                job = next(remaining, None)
                if job is None:
                    break
                pending.add(pool.submit(execute, job, frozen, args.output, runtime))
            if not pending:
                break
            ready, _ = concurrent.futures.wait(pending, return_when=concurrent.futures.FIRST_COMPLETED)
            for future in ready:
                pending.remove(future)
                row = future.result()
                rows.append(row)
                stream.write(json.dumps(row, ensure_ascii=False) + "\n")
                stream.flush()
                os.fsync(stream.fileno())
                print(json.dumps({key: row[key] for key in ["id", "status", "passed", "functional_pass", "wall_seconds"]}), flush=True)
                model = row["model"]
                error_streaks[model] = error_streaks[model] + 1 if row["status"] in ["timeout", "model_error", "infrastructure_error"] else 0
                stop |= fatal_row(row) or error_streaks[model] >= 3
        if stop:
            print("Stopped after a fatal error or three consecutive provider failures; no automatic retry.", flush=True)
    report = summary(rows)
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
