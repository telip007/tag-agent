#!/usr/bin/env python3
"""Audit a frozen screen and report paired task-level exploratory intervals."""

import argparse
import hashlib
import json
from pathlib import Path
import random
import statistics


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def build_report(directory):
    frozen = json.loads((directory / "frozen.json").read_text())
    fingerprint = frozen.pop("fingerprint")
    if digest(frozen) != fingerprint:
        raise ValueError("manifest fingerprint mismatch")
    rows = [json.loads(line) for line in (directory / "results.jsonl").read_text().splitlines()]
    expected = {(c, m, t["id"], r) for m, prompts in frozen["prompts"].items()
                for c in prompts for t in frozen["tasks"] for r in range(frozen["repeats"])}
    seen = set()
    for row in rows:
        job = (row["candidate"], row["model"], row["task"], row["repeat"])
        if job not in expected or job in seen or row["fingerprint"] != fingerprint:
            raise ValueError("unexpected, duplicate or mismatched result")
        seen.add(job)
    table = []
    pairs = []
    for model, prompts in frozen["prompts"].items():
        for candidate, prompt in prompts.items():
            items = [r for r in rows if r["model"] == model and r["candidate"] == candidate]
            valid = [r for r in items if r["status"] == "ok"]
            usage_complete = len(valid) > 0 and all(r.get("usage") is not None for r in valid)
            table.append({
                "model": model, "candidate": candidate, "prompt_characters": len(prompt),
                "valid": len(valid), "preferred_action_passes": sum(r["passed"] for r in valid),
                "infra_errors": len(items) - len(valid),
                "total_tokens": sum(r["usage"].get("total_tokens", 0) for r in valid) if usage_complete else None,
                "tool_calls": sum(len(r["message"].get("tool_calls") or []) for r in valid),
                "median_wall_seconds": round(statistics.median(r["wall_seconds"] for r in valid), 3) if valid else None,
                "monetary_cost": None,
            })
            if candidate == "baseline":
                continue
            # Pair on task AND repeat, then average repetitions within each task.
            # Resample tasks, not individual repeated responses.
            baseline = {(r["task"], r["repeat"]): r for r in rows
                        if r["model"] == model and r["candidate"] == "baseline" and r["status"] == "ok"}
            differences = {}
            for row in valid:
                base = baseline.get((row["task"], row["repeat"]))
                if base is not None:
                    differences.setdefault(row["task"], []).append(int(row["passed"]) - int(base["passed"]))
            task_diffs = [statistics.mean(values) for values in differences.values()]
            if task_diffs:
                rng = random.Random(20261020)
                boot = sorted(statistics.mean(rng.choices(task_diffs, k=len(task_diffs))) for _ in range(10000))
                pairs.append({"model": model, "candidate": candidate, "paired_tasks": len(task_diffs),
                              "mean_delta_pp": round(statistics.mean(task_diffs) * 100, 2),
                              "exploratory_95pct_task_bootstrap_pp": [round(boot[249] * 100, 2), round(boot[9749] * 100, 2)]})
    return {"fingerprint": fingerprint, "split": frozen["split"], "expected": len(expected),
            "observed": len(rows), "missing": len(expected - seen), "table": table, "paired": pairs,
            "limits": "Preferred-action surface screen, not coding success. Small curated suite; exploratory intervals are unadjusted for candidate selection and multiple comparisons. No winner inference."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    report = build_report(args.directory)
    (args.directory / "analysis.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
