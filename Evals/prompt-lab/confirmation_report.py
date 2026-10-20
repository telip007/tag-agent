#!/usr/bin/env python3
"""Audit reserved suites against the immutable recommendation; never choose a winner."""

import hashlib
import json
from pathlib import Path
import statistics

from benchmark import digest
from family_report import compare_rows, load_experiments, merge_samples, paired_statistics


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_run(manifest, suite, reserve, freeze, policy):
    plan = freeze["confirmation_plan"]
    expected = {"stage": "native-trajectories", "split": suite,
                "models": plan["models"], "policies": {"baseline": None, policy["id"]: policy["rules"]},
                "policy_scaffolds": {"baseline": "standard", policy["id"]: policy["scaffold"]},
                "scaffold": "standard", "repeats": plan["repeats"], "repeat_offset": 0,
                "temperature": 0, "reasoning": "provider defaults",
                "runner_binary_sha256": freeze["compiled_bundle_sha256"]}
    expected.update({key: plan[key] for key in ["max_calls", "max_tokens", "deadline_seconds", "workers"]})
    if any(manifest.get(key) != value for key, value in expected.items()) or manifest.get("context"):
        raise ValueError("reserved run differs from the frozen ordinary comparison")
    if digest(manifest["tasks"]) != digest(reserve["tasks"]):
        raise ValueError("reserved tasks changed")
    for relative, wanted in freeze["artifacts_sha256"].items():
        key = "Evals/prompt-lab/" + relative
        if relative in ["trajectories.py", "context_robustness.py", "recommendation/policy.json"] and key not in manifest["source_hashes"]:
            raise ValueError("reserved runtime source binding is missing")
        if key in manifest["source_hashes"] and manifest["source_hashes"][key] != wanted:
            raise ValueError("reserved runtime differs from the recommendation freeze")


def summarize(rows, excluded=()):
    selected = [row for row in rows if row["task"] not in excluded]
    table = compare_rows(selected, set())
    for cell in table:
        items = [row for row in selected if row["model"] == cell["model"] and row["candidate"] == cell["candidate"]]
        durations = sorted(row["wall_seconds"] for row in items)
        cell["recorded_attempted_calls"] = sum(row.get("outcome", {}).get("attemptedCalls", 0) for row in items)
        cell["wall_seconds"] = {"min": min(durations), "median": statistics.median(durations),
                                "max": max(durations), "interpretation": "All attempted trajectories; observational provider/network timing."}
    return {"excluded_whole_tasks": list(excluded), "observed": len(selected),
            "table": table, "balanced_paired_summaries": paired_statistics(selected, set())}


def build(base):
    freeze = json.loads((base / "recommendation/FREEZE.json").read_text())
    fingerprint = freeze.pop("fingerprint")
    if digest(freeze) != fingerprint:
        raise ValueError("recommendation freeze fingerprint mismatch")
    for relative, wanted in freeze["artifacts_sha256"].items():
        if sha(base / relative) != wanted:
            raise ValueError("frozen recommendation artifact changed")
    policy = json.loads((base / "recommendation/policy.json").read_text())
    groups, runs, missing, unaudited, common_sources = [], [], [], [], {}
    for suite in ["confirmation", "transfer"]:
        reserve_path = base / f"results/{suite}-reserve-01/frozen.json"
        reserve = json.loads(reserve_path.read_text())
        reserve_fingerprint = reserve.pop("fingerprint")
        bound = freeze["reserved_suites"][suite]
        if digest(reserve) != reserve_fingerprint or reserve_fingerprint != bound["fingerprint"] or sha(reserve_path) != bound["manifest_sha256"]:
            raise ValueError("reserved suite changed after freeze")
        path = base / f"results/native-{suite}-01"
        if not (path / "frozen.json").exists() or not (path / "results.jsonl").exists():
            missing.append(suite)
            continue
        manifest = json.loads((path / "frozen.json").read_text())
        validate_run(manifest, suite, reserve, freeze, policy)
        for relative, wanted in manifest["source_hashes"].items():
            if sha(path / "source" / relative) != wanted:
                raise ValueError("reserved source archive mismatch")
            if relative in common_sources and common_sources[relative] != wanted:
                raise ValueError("runtime source changed between reserved suites")
            common_sources[relative] = wanted
        before = sha(path / "results.jsonl")
        rows, records, _ = load_experiments([path])
        if before != sha(path / "results.jsonl"):
            raise ValueError("results changed during analysis; retry the same read later")
        decisions = json.loads((path / "failure-audit.json").read_text()) if (path / "failure-audit.json").exists() else []
        seen = set()
        for decision in decisions:
            identifier = decision["id"]
            if (identifier in seen or identifier not in {row["id"] for row in rows}
                    or decision["fingerprint"] != manifest["fingerprint"]
                    or sha(path / "runs" / (identifier + ".json")) != decision["detail_sha256"]):
                raise ValueError("invalid or stale reserved failure audit")
            seen.add(identifier)
        unaudited.extend(row["id"] for row in rows if not row["passed"] and row["id"] not in seen)
        record = records[0]
        record["directory"] = "results/" + path.name
        runs.append({**record, "suite": suite, "summary": summarize(rows)})
        groups.append(rows)
    rows = merge_samples(groups)
    sensitivity = None
    quality = base / "results/native-confirmation-01/data-quality.json"
    if quality.exists():
        caveat = json.loads(quality.read_text())
        reserve = json.loads((base / "results/confirmation-reserve-01/frozen.json").read_text())
        task = next(task for task in reserve["tasks"] if task["id"] == caveat["task_id"])
        detail = base / "results/native-confirmation-01/runs" / (caveat["trigger_trajectory"] + ".json")
        if digest(task) != caveat["task_sha256"] or sha(detail) != caveat["trigger_detail_sha256"]:
            raise ValueError("stale specification caveat")
        sensitivity = {"origin": "Post-freeze diagnostic after the first result, not a predeclared exclusion.",
                       "caveat": caveat, **summarize(rows, [task["id"]])}
    expected = freeze["confirmation_plan"]["ordinary_subject_trajectories"]
    complete = not missing and all(run["expected"] == run["observed"] for run in runs) and len(rows) == expected
    return {"freeze_fingerprint": fingerprint, "expected": expected, "observed": len(rows),
            "data_complete": complete, "ready_for_final_interpretation": complete and not unaudited,
            "missing_suites": missing, "unaudited_failures": unaudited, "runs": runs,
            "primary_all_tasks": summarize(rows), "additional_whole_task_sensitivity": sensitivity,
            "reporter_sha256": sha(Path(__file__)),
            "limits": "Primary keeps all original reserved grades. The additional whole-task sensitivity cannot replace it. Finite authored tasks and mutable aliases limit generalization; exploratory task-cluster intervals do not prove equivalence. Context conditions are separate and are not additional independent tasks. No winner or completion inferred from this report."}


if __name__ == "__main__":
    base = Path(__file__).resolve().parent
    result = build(base)
    output = base / "results/native-heldout-comparison-01/analysis.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ["expected", "observed", "data_complete", "missing_suites", "unaudited_failures"]}))
