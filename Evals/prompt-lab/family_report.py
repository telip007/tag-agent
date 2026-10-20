#!/usr/bin/env python3
"""Combine audited native experiments, preserving failures and sample identities."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import statistics

from benchmark import digest
from native_report import analyze, resources


def merge_samples(groups):
    rows, seen = [], set()
    for group in groups:
        for row in group:
            key = tuple(row[field] for field in ["model", "candidate", "task", "repeat"])
            if key in seen:
                raise ValueError("duplicate sample across experiments")
            seen.add(key)
            rows.append(row)
    return rows


def usage(row):
    outcome = row.get("outcome", {})
    replies = outcome.get("responses", [])
    complete = bool(replies) and len(replies) == outcome.get("attemptedCalls") and all(
        isinstance(reply.get("inputTokens"), int) and isinstance(reply.get("outputTokens"), int)
        for reply in replies)
    return sum(reply["inputTokens"] + reply["outputTokens"] for reply in replies) if complete else None


def counts(rows):
    return {"observed": len(rows), "passed": sum(row["reviewed_passed"] for row in rows),
            "raw_passed": sum(row["passed"] for row in rows),
            "functional_passes": sum(row["functional_pass"] for row in rows),
            "scope_failures": sum(bool(row["forbidden_changes"]) for row in rows),
            "statuses": {status: sum(row["status"] == status for row in rows)
                         for status in sorted({row["status"] for row in rows})}}


def geometric(values):
    return round(math.exp(statistics.mean(math.log(value) for value in values)), 6) if values else None


def total_resources(model, rows):
    replies = [reply for row in rows for reply in row.get("outcome", {}).get("responses", [])]
    complete = bool(rows) and all(usage(row) is not None for row in rows)
    metrics = resources(model, replies)
    tokens = metrics["recorded_input_tokens"] + metrics["recorded_output_tokens"]
    passes = sum(row["reviewed_passed"] for row in rows)
    rate = metrics["recorded_allowance_rate_value_usd_range"]
    return {"usage_complete": complete, "recorded_tokens": tokens,
            "tokens_per_reviewed_success": round(tokens / passes, 3) if complete and passes else None,
            "rate_value_per_reviewed_success_range": [round(value / passes, 8) for value in rate]
            if complete and passes and rate else None,
            **metrics}


def cluster_summary(groups, ratio=False):
    """Equal-model task clusters; repeat samples never create new task clusters."""
    common = sorted(set.intersection(*(set(tasks) for tasks in groups.values()))) if groups else []
    if not common:
        return {"common_tasks": [], "point": None, "exploratory_95pct_task_bootstrap": None}
    effects = [statistics.mean(statistics.mean(tasks[task]) for tasks in groups.values()) for task in common]
    rng = random.Random(20261022)
    boot = sorted(statistics.mean(rng.choices(effects, k=len(effects))) for _ in range(10000))
    transform = (lambda value: round(math.exp(value), 6)) if ratio else (lambda value: round(100 * value, 2))
    return {"common_tasks": common, "point": transform(statistics.mean(effects)),
            "exploratory_95pct_task_bootstrap": [transform(boot[249]), transform(boot[9749])]}


def paired_statistics(rows, excluded):
    models = sorted({row["model"] for row in rows})
    baseline = {(row["model"], row["task"], row["repeat"]): row for row in rows if row["candidate"] == "baseline"}
    output = []
    for policy in sorted({row["candidate"] for row in rows} - {"baseline"}):
        metrics = {metric: {model: {} for model in models} for metric in ["quality_delta_pp", "token_ratio", "call_ratio", "rate_ratio"]}
        pairs = {model: 0 for model in models}
        for row in rows:
            if row["candidate"] != policy or row["task"] in excluded:
                continue
            model, task = row["model"], row["task"]
            base = baseline.get((model, task, row["repeat"]))
            if not base:
                continue
            pairs[model] += 1
            values = {"quality_delta_pp": int(row["reviewed_passed"]) - int(base["reviewed_passed"])}
            a, b = usage(row), usage(base)
            if row["reviewed_passed"] and base["reviewed_passed"] and a and b:
                values["token_ratio"] = math.log(a / b)
                values["call_ratio"] = math.log(row["outcome"]["attemptedCalls"] / base["outcome"]["attemptedCalls"])
                a_rate = resources(model, row["outcome"]["responses"])["recorded_allowance_rate_value_usd_range"]
                b_rate = resources(model, base["outcome"]["responses"])["recorded_allowance_rate_value_usd_range"]
                if a_rate and b_rate and a_rate[0] and b_rate[0]:
                    values["rate_ratio"] = math.log(a_rate[0] / b_rate[0])
            for metric, value in values.items():
                metrics[metric][model].setdefault(task, []).append(value)
        output.append({"candidate": policy, "models": models, "quality_pairs_by_model": pairs,
                       "metrics": {metric: cluster_summary(groups, ratio=metric != "quality_delta_pp")
                                   for metric, groups in metrics.items()}})
    return output


def compare_rows(rows, excluded):
    table = []
    for model, policy in sorted({(row["model"], row["candidate"]) for row in rows}):
        items = [row for row in rows if row["model"] == model and row["candidate"] == policy]
        selected = [row for row in items if row["task"] not in excluded]
        baseline = {(row["task"], row["repeat"]): row for row in rows
                    if row["model"] == model and row["candidate"] == "baseline"}
        tokens, calls, rates, keys = [], [], [], []
        for row in selected:
            base = baseline.get((row["task"], row["repeat"]))
            if not base or not base["reviewed_passed"] or not row["reviewed_passed"]:
                continue
            a, b = usage(row), usage(base)
            if a is None or b is None or not b:
                continue
            tokens.append(a / b)
            calls.append(row["outcome"]["attemptedCalls"] / base["outcome"]["attemptedCalls"])
            keys.append([row["task"], row["repeat"]])
            a_rate = resources(model, row["outcome"]["responses"])["recorded_allowance_rate_value_usd_range"]
            b_rate = resources(model, base["outcome"]["responses"])["recorded_allowance_rate_value_usd_range"]
            if a_rate and b_rate and b_rate[0]:
                # Same-model common tariff scenario; peak timing remains unresolved.
                rates.append(a_rate[0] / b_rate[0])
        table.append({"model": model, "candidate": policy, "all_tasks": counts(items),
                      "selection_tasks": counts(selected), "selection_resources": total_resources(model, selected),
                      "resource_pairs": len(tokens),
                      "resource_pair_keys": keys,
                      "paired_geomean_token_ratio": geometric(tokens),
                      "paired_geomean_call_ratio": geometric(calls),
                      "rate_pairs": len(rates), "paired_geomean_rate_ratio": geometric(rates)})
    return table


def load_experiments(directories):
    groups, records, controls, task_hashes, policies = [], [], None, {}, {}
    for directory in directories:
        audit = analyze(directory)
        manifest = json.loads((directory / "frozen.json").read_text())
        comparison = {key: manifest[key] for key in
                      ["stage", "split", "max_calls", "max_tokens", "deadline_seconds", "temperature", "reasoning"]}
        comparison["workers"] = manifest.get("workers", 2)
        comparison["context_treatment_sha256"] = digest(manifest["context"]) if manifest.get("context") else None
        if controls is not None and comparison != controls:
            raise ValueError("incompatible inference controls or task split")
        controls = comparison
        for task in manifest["tasks"]:
            old = task_hashes.setdefault(task["id"], digest(task))
            if old != digest(task):
                raise ValueError("task definition changed across experiments")
        for name, rules in manifest["policies"].items():
            scaffold = manifest.get("policy_scaffolds", {}).get(name, manifest.get("scaffold", "standard"))
            policy_hash = digest({"rules": rules, "scaffold": scaffold})
            old = policies.setdefault(name, policy_hash)
            if old != policy_hash:
                raise ValueError("policy text changed under the same identity")
        reviewed = {}
        adjudication = directory / "adjudications.json"
        if adjudication.exists():
            reviewed = {item["id"]: item["reviewed_passed"] for item in json.loads(adjudication.read_text())}
        rows = [json.loads(line) for line in (directory / "results.jsonl").read_text().splitlines()]
        for row in rows:
            row["reviewed_passed"] = reviewed.get(row["id"], row["passed"])
        groups.append(rows)
        records.append({"directory": str(directory), "fingerprint": audit["fingerprint"],
                        "expected": audit["expected"], "observed": audit["observed"],
                        "native_bundle_sha256": manifest["runner_binary_sha256"],
                        "scaffold": manifest.get("scaffold", "standard"),
                        "policy_scaffolds": manifest.get("policy_scaffolds", {}),
                        "results_sha256": hashlib.sha256((directory / "results.jsonl").read_bytes()).hexdigest()})
    return merge_samples(groups), records, controls


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", type=Path, nargs="+")
    parser.add_argument("--exclude-task", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rows, runs, controls = load_experiments(args.directories)
    excluded = set(args.exclude_task)
    if not excluded <= {row["task"] for row in rows}:
        parser.error("exclusion is not an observed task")
    table = compare_rows(rows, excluded)
    report = {"runs": runs, "controls": controls, "excluded_selection_tasks": sorted(excluded),
              "complete": all(run["expected"] == run["observed"] for run in runs), "table": table,
              "balanced_paired_summaries": paired_statistics(rows, excluded),
              "equal_model_resource_ratios": [
                  {"candidate": name, "models": len(items),
                   "token_ratio": geometric([item["paired_geomean_token_ratio"] for item in items]),
                   "rate_ratio": geometric([item["paired_geomean_rate_ratio"] for item in items
                                             if item["paired_geomean_rate_ratio"] is not None])}
                  for name in sorted({item["candidate"] for item in table})
                  if (items := [item for item in table if item["candidate"] == name
                                and item["paired_geomean_token_ratio"] is not None])],
              "limits": "Exploratory pooled runs with recorded bundle fingerprints, not a randomized contemporaneous comparison. Resource pairs condition on successful completions with complete usage; inspect all failure counts and all-attempt cost per success separately. Balanced summaries use only task clusters represented on every model, average repeats within model/task, and weight models equally. Task-bootstrap intervals are unadjusted for selection or multiple comparisons; a zero-width quality interval from all observed successes does not establish equivalence. Model aliases, cache states and routing vary. Same-tariff estimates are not actual cash or allowance debits. No winner is inferred.",
              "reporter_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"complete": report["complete"], "observed": len(rows),
                      "equal_model_resource_ratios": report["equal_model_resource_ratios"]}, indent=2))


if __name__ == "__main__":
    main()
