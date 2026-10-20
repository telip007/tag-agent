#!/usr/bin/env python3
"""Native tool-choice screen. No model-produced tool call is executed."""

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid

from fixtures import CANDIDATES, DEV, HOLDOUT, TOOLS, render

ENDPOINT = "https://opencode.ai/inference/go/openai/v1/chat/completions"
ROOT = Path(__file__).resolve().parents[2]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def credential():
    if os.environ.get("OPENCODE_API_KEY"):
        return os.environ["OPENCODE_API_KEY"]
    config = Path(os.environ.get("TAG_CONFIG_DIR", Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tag"))
    path = config / "credentials.json"
    if path.exists():
        return json.loads(path.read_text()).get("apiKeys", {}).get("opencode-go")
    return None


def grade(message, rubric, finish_reason):
    """Conservative surface rubric; semantic coding success is not measured."""
    if "any_of" in rubric:
        outcomes = [grade(message, alternative, finish_reason) for alternative in rubric["any_of"]]
        return any(x[0] for x in outcomes), "; ".join(x[1] for x in outcomes)
    if finish_reason == "length":
        return False, "truncated response"
    calls = message.get("tool_calls") or []
    text = message.get("content") or ""
    kind = rubric["kind"]
    if kind == "tool":
        if not calls:
            return False, "expected a native tool call"
        if len(calls) > 1:
            outcomes = [grade({"tool_calls": [call]}, rubric, finish_reason) for call in calls]
            companions = rubric.get("companions", [])
            allowed = [result[0] or call.get("function", {}).get("name") in companions
                       for result, call in zip(outcomes, calls)]
            return all(allowed) and any(x[0] for x in outcomes), "required action plus compatible inspection calls"
        call = calls[0].get("function", {})
        if call.get("name") not in rubric["names"]:
            return False, "unexpected tool"
        try:
            args = json.loads(call.get("arguments", ""))
        except (ValueError, TypeError):
            return False, "invalid argument JSON"
        schema = next(x["function"]["parameters"] for x in TOOLS if x["function"]["name"] == call["name"])
        if not isinstance(args, dict) or any(x not in args for x in schema["required"]):
            return False, "missing required arguments"
        for key, value in args.items():
            prop = schema["properties"].get(key)
            if prop is None or (prop["type"] == "string" and not isinstance(value, str)) or (prop["type"] == "boolean" and not isinstance(value, bool)):
                return False, "invalid argument type or unknown key"
        target = str(args.get(rubric.get("argument"), ""))
        if "pattern" in rubric and not re.search(rubric["pattern"], target):
            return False, "required argument pattern missing"
        if "forbidden" in rubric and re.search(rubric["forbidden"], json.dumps(args)):
            return False, "forbidden action in arguments"
        return True, "native tool and argument rubric passed"
    if calls:
        return False, "expected a text answer without tools"
    if kind == "exact":
        return text.strip() == rubric["text"], "exact output comparison"
    if not re.search(rubric["pattern"], text):
        return False, "required answer pattern missing"
    if kind == "ask" and "?" not in text:
        return False, "expected a question"
    return True, "surface answer rubric passed"


def evaluate(job, frozen, key):
    candidate, model, task, repeat = job
    started = time.monotonic()
    body = {
        "model": model, "messages": [{"role": "system", "content": frozen["prompts"][model][candidate]}] + task["messages"],
        "tools": TOOLS, "tool_choice": "auto", "temperature": 0,
        "max_tokens": frozen["max_tokens"], "stream": False,
    }
    row = {"candidate": candidate, "model": model, "task": task["id"], "repeat": repeat,
           "fingerprint": frozen["fingerprint"], "request_sha256": digest(body),
           "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    request = urllib.request.Request(ENDPOINT, data=json.dumps(body).encode(), headers={
        "Authorization": "Bearer " + key, "Content-Type": "application/json",
        "User-Agent": "tag-prompt-lab/0.1", "x-opencode-session": str(uuid.uuid4()),
    })
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            raw = json.load(response)
        choice = raw["choices"][0]
        passed, detail = grade(choice["message"], task["rubric"], choice.get("finish_reason"))
        row.update(status="ok", passed=passed, grade_detail=detail,
                   message=choice["message"], finish_reason=choice.get("finish_reason"),
                   usage=raw.get("usage"), response_model=raw.get("model"),
                   system_fingerprint=raw.get("system_fingerprint"))
    except urllib.error.HTTPError as error:
        # Bodies can echo requests or credentials. Persist only the status.
        row.update(status="http_error", http_status=error.code, passed=False)
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        row.update(status="infrastructure_error", error_type=type(error).__name__, passed=False)
    row["wall_seconds"] = round(time.monotonic() - started, 3)
    return row


def summarize(rows):
    groups = {}
    for row in rows:
        groups.setdefault((row["model"], row["candidate"]), []).append(row)
    summary = []
    for (model, candidate), items in sorted(groups.items()):
        valid = [x for x in items if x["status"] == "ok"]
        usages = [x["usage"] for x in valid if x.get("usage")]
        summary.append({"model": model, "candidate": candidate, "attempted": len(items),
                        "valid": len(valid), "passed": sum(x["passed"] for x in valid),
                        "infra_errors": len(items) - len(valid),
                        "prompt_tokens": sum(x.get("prompt_tokens", 0) for x in usages) if usages else None,
                        "completion_tokens": sum(x.get("completion_tokens", 0) for x in usages) if usages else None,
                        "wall_seconds": round(sum(x["wall_seconds"] for x in items), 3),
                        "cost": None})
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", nargs="+", default=["deepseek-v4.1-flash", "glm-5.3-flash"])
    parser.add_argument("--candidates", nargs="+", choices=list(CANDIDATES), default=list(CANDIDATES))
    parser.add_argument("--split", choices=["dev", "holdout"], default="dev")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--max-tokens", type=int, default=2048)
    parser.add_argument("--task", help="One exact task ID for connectivity smoke tests")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run", action="store_true", help="Without this flag, only print the proposed manifest")
    args = parser.parse_args()
    if not 1 <= args.repeats <= 10 or not 1 <= args.workers <= 4 or args.max_tokens < 128:
        parser.error("repeats must be 1..10, workers 1..4, max tokens >=128")
    tasks = DEV if args.split == "dev" else HOLDOUT
    if args.task:
        tasks = [x for x in tasks if x["id"] == args.task]
        if not tasks:
            parser.error("unknown task ID in this split")
    frozen = {
        "stage": "decision-screen", "split": args.split, "models": args.models,
        "prompts": {m: {c: render(c, m) for c in args.candidates} for m in args.models},
        "tools": TOOLS, "tasks": tasks, "repeats": args.repeats, "max_tokens": args.max_tokens,
        "temperature": 0, "endpoint": ENDPOINT,
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "baseline_source_sha256": hashlib.sha256((ROOT / "Sources/TagKit/SystemPrompt.swift").read_bytes()).hexdigest(),
        "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "fixtures_sha256": hashlib.sha256(Path(__file__).with_name("fixtures.py").read_bytes()).hexdigest(),
        "schedule_seed": 20261020,
    }
    frozen["fingerprint"] = digest(frozen)
    jobs = [(c, m, t, r) for c in args.candidates for m in args.models for t in tasks for r in range(args.repeats)]
    random.Random(frozen["schedule_seed"]).shuffle(jobs)
    print(json.dumps({"mode": "live" if args.run else "dry-run", "requests": len(jobs),
                      "models": args.models, "split": args.split, "fingerprint": frozen["fingerprint"],
                      "credential_present": bool(credential()), "max_completion_tokens": len(jobs) * args.max_tokens,
                      "billing": "existing Go allowance; actual monetary cost unavailable unless returned"}), flush=True)
    if not args.run:
        return
    key = credential()
    if not key:
        parser.error("OpenCode Go credential unavailable")
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = args.output / "frozen.json"
    if manifest.exists():
        if json.loads(manifest.read_text())["fingerprint"] != frozen["fingerprint"]:
            parser.error("output directory belongs to a different experiment; use a fresh output path")
    else:
        manifest.write_text(json.dumps(frozen, indent=2, ensure_ascii=False) + "\n")
    results = args.output / "results.jsonl"
    rows = [json.loads(x) for x in results.read_text().splitlines()] if results.exists() else []
    completed = {(x["candidate"], x["model"], x["task"], x["repeat"]) for x in rows}
    jobs = [x for x in jobs if (x[0], x[1], x[2]["id"], x[3]) not in completed]
    # Bounded batches: on authorization or allowance errors, finish only the
    # already-in-flight batch, then stop. Failed requests are never auto-retried.
    with results.open("a") as output, concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for start in range(0, len(jobs), args.workers):
            batch = [pool.submit(evaluate, x, frozen, key) for x in jobs[start:start + args.workers]]
            stop = False
            for future in concurrent.futures.as_completed(batch):
                row = future.result()
                rows.append(row)
                output.write(json.dumps(row, ensure_ascii=False) + "\n")
                output.flush()
                os.fsync(output.fileno())
                print(json.dumps({k: row[k] for k in ["candidate", "model", "task", "status", "passed", "wall_seconds"]}), flush=True)
                stop |= 400 <= row.get("http_status", 0) < 500
            if stop:
                print("Stopped: provider rejected the request; no automatic retry.", flush=True)
                break
    report = summarize(rows)
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
