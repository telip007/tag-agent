#!/usr/bin/env python3
"""Reproduce the predeclared complete repeated-template selection dataset."""

import hashlib
import json
from pathlib import Path

from benchmark import digest
from family_report import compare_rows, load_experiments, paired_statistics


def main():
    base = Path(__file__).resolve().parent
    plan = json.loads((base / "proposals/repeated-comparison.json").read_text())
    fingerprint = plan.pop("fingerprint")
    if digest(plan) != fingerprint:
        raise ValueError("repeat plan fingerprint mismatch")
    names = {core + ("_lean" if scaffold == "lean" else "")
             for core in plan["core_policies"] for scaffold in plan["scaffolds"]}
    expected = {(model, candidate, task, repeat) for model in plan["models"]
                for candidate in names for task in plan["task_hashes"]
                for repeat in range(plan["samples_per_cell"])}
    paths = [base / "results" / name for name in ["native-dev-02", "native-family-dev-01",
                                                  "native-scaffold-dev-01", "native-repeat-dev-01"]]
    rows, records, controls = load_experiments(paths)
    key = lambda row: tuple(row[field] for field in ["model", "candidate", "task", "repeat"])
    selected = [row for row in rows if key(row) in expected]
    if {key(row) for row in selected} != expected or len(selected) != len(expected):
        raise ValueError("predeclared selected-template matrix is incomplete")
    for path in paths:
        manifest = json.loads((path / "frozen.json").read_text())
        for task in manifest["tasks"]:
            if task["id"] in plan["task_hashes"] and digest(task) != plan["task_hashes"][task["id"]]:
                raise ValueError("task differs from the repeated plan")
        for name, rules in manifest["policies"].items():
            core = name.removesuffix("_lean")
            if name in names and rules != plan["core_policies"][core]:
                raise ValueError("policy differs from the repeated plan")
        for row in [json.loads(line) for line in (path / "results.jsonl").read_text().splitlines()]:
            if key(row) not in expected:
                continue
            origin = "native-repeat-dev-01" if row["repeat"] else (
                "native-scaffold-dev-01" if row["candidate"].endswith("_lean") else
                "native-family-dev-01" if row["candidate"] == "minimal" else "native-dev-02")
            if path.name != origin:
                raise ValueError("sample origin differs from the predeclared reuse")
    report = {"plan_fingerprint": fingerprint, "expected": len(expected), "observed": len(selected),
              "complete": True, "controls": controls,
              "runs": [{**record, "directory": "results/" + Path(record["directory"]).name} for record in records],
              "excluded_task": "config-precedence", "table": compare_rows(selected, set()),
              "balanced_paired_summaries": paired_statistics(selected, set()),
              "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "limits": "528 repeated trajectories on eleven authored tasks and mutable aliases. Whole tasks, not repeat samples, are statistical clusters. Conditional resource pairs exclude failures; all-attempt metrics require complete usage. Exploratory intervals are unadjusted and cannot establish equivalence or universal superiority."}
    output = base / "results/native-repeat-comparison-01/selection.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"expected": len(expected), "observed": len(selected), "output": "results/native-repeat-comparison-01/selection.json"}))


if __name__ == "__main__":
    main()
