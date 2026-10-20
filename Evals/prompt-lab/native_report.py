#!/usr/bin/env python3
"""Audit full native trajectories without inferring completion from partial work."""

import argparse
import hashlib
import json
from pathlib import Path
import random
import statistics

from benchmark import digest


def resources(model, replies):
    known = [reply for reply in replies if "inputTokens" in reply and "outputTokens" in reply]
    inputs = sum(reply["inputTokens"] for reply in known)
    outputs = sum(reply["outputTokens"] for reply in known)
    cache_known = bool(known) and all("cachedInputTokens" in reply and 0 <= reply["cachedInputTokens"] <= reply["inputTokens"] for reply in known)
    cached = sum(reply["cachedInputTokens"] for reply in known) if cache_known else None
    rates = json.loads(Path(__file__).with_name("go-rates-2026-10-20.json").read_text())["models"].get(model, [])
    estimates = [(inputs - cached) * rate["input"] / 1e6 + cached * rate["cache_read"] / 1e6 + outputs * rate["output"] / 1e6
                 for rate in rates] if cached is not None else []
    return {"recorded_input_tokens": inputs, "recorded_output_tokens": outputs,
            "recorded_cache_read_tokens": cached, "recorded_uncached_input_tokens": inputs - cached if cached is not None else None,
            "recorded_allowance_rate_value_usd_range": [round(min(estimates), 8), round(max(estimates), 8)] if estimates else None}


def analyze(directory):
    manifest = json.loads((directory / "frozen.json").read_text())
    fingerprint = manifest.pop("fingerprint")
    if digest(manifest) != fingerprint:
        raise ValueError("manifest fingerprint mismatch")
    expected = {f"{m}--{c}--{t['id']}--{r}" for m in manifest["models"] for c in manifest["policies"]
                for t in manifest["tasks"] for r in range(manifest.get("repeat_offset", 0), manifest.get("repeat_offset", 0) + manifest["repeats"])}
    rows = [json.loads(line) for line in (directory / "results.jsonl").read_text().splitlines()]
    overrides = {}
    audit = directory / "adjudications.json"
    if audit.exists():
        for decision in json.loads(audit.read_text()):
            identifier = decision["id"]
            row = next((row for row in rows if row["id"] == identifier), None)
            task = next((task for task in manifest["tasks"] if row and task["id"] == row["task"]), None)
            detail_path = directory / "runs" / (identifier + ".json")
            if (identifier in overrides or not row or task["kind"] not in ["read-only", "clarify"]
                    or row["status"] != "ok" or row["forbidden_changes"]
                    or decision["fingerprint"] != fingerprint
                    or hashlib.sha256(detail_path.read_bytes()).hexdigest() != decision["detail_sha256"]
                    or not isinstance(decision["reviewed_passed"], bool)):
                raise ValueError("invalid or stale behavioral adjudication")
            overrides[identifier] = decision["reviewed_passed"]
    def effective(row):
        return overrides.get(row["id"], row["passed"])
    seen = set()
    for row in rows:
        if row["id"] in seen or row["id"] not in expected or row["fingerprint"] != fingerprint:
            raise ValueError("duplicate, unexpected or mismatched trajectory")
        detail = json.loads((directory / "runs" / (row["id"] + ".json")).read_text())
        if detail["row"] != row:
            raise ValueError("trajectory detail disagrees with result row")
        seen.add(row["id"])
    archived = directory / "source"
    if archived.exists():
        for relative, expected_hash in manifest["source_hashes"].items():
            if hashlib.sha256((archived / relative).read_bytes()).hexdigest() != expected_hash:
                raise ValueError("archived source fingerprint mismatch")
    table = []
    pairs = []
    kinds = {task["id"]: task["kind"] for task in manifest["tasks"]}
    for model in manifest["models"]:
        baseline = {(r["task"], r["repeat"]): r for r in rows if r["model"] == model and r["candidate"] == "baseline"}
        for candidate in manifest["policies"]:
            items = [r for r in rows if r["model"] == model and r["candidate"] == candidate]
            replies = [reply for row in items for reply in row.get("outcome", {}).get("responses", [])]
            known_usage = [reply for reply in replies if "inputTokens" in reply and "outputTokens" in reply]
            attempts = sum(r.get("outcome", {}).get("attemptedCalls", 0) for r in items)
            token_total = sum(reply["inputTokens"] + reply["outputTokens"] for reply in known_usage)
            passes = sum(effective(r) for r in items)
            usage_complete = bool(items) and all(bool(r.get("outcome")) for r in items) and len(known_usage) == attempts
            table.append({"model": model, "candidate": candidate, "scheduled": len(manifest["tasks"]) * manifest["repeats"],
                          "observed": len(items), "passed": passes,
                          "raw_passed": sum(r["passed"] for r in items),
                          "functional_passes": sum(r["functional_pass"] for r in items),
                          "code_tasks_observed": sum(kinds[r["task"]] in ["code", "swift"] for r in items),
                          "code_test_passes": sum(r["functional_pass"] for r in items if kinds[r["task"]] in ["code", "swift"]),
                          "behavioral_tasks_observed": sum(kinds[r["task"]] in ["read-only", "clarify"] for r in items),
                          "behavioral_passes": sum(effective(r) for r in items if kinds[r["task"]] in ["read-only", "clarify"]),
                          "statuses": {status: sum(r["status"] == status for r in items) for status in sorted({r["status"] for r in items})},
                          "model_calls": attempts, "reported_tokens": token_total,
                          "usage_complete_for_attempted_calls": usage_complete,
                          "reported_tokens_per_success": round(token_total / passes, 1) if passes and usage_complete else None,
                          "median_wall_seconds": round(statistics.median(r["wall_seconds"] for r in items), 3) if items else None,
                          "visible_check_string_observed": sum(r["requested_check_observed"] for r in items),
                          "monetary_cost": None, **resources(model, replies)})
            differences = {}
            for row in items:
                base = baseline.get((row["task"], row["repeat"]))
                if base and base["status"] in ["ok", "request_limit", "generation_limit"] and row["status"] in ["ok", "request_limit", "generation_limit"]:
                    differences.setdefault(row["task"], []).append(int(effective(row)) - int(effective(base)))
            values = [statistics.mean(v) for v in differences.values()]
            if candidate != "baseline" and values:
                rng = random.Random(20261021)
                boot = sorted(statistics.mean(rng.choices(values, k=len(values))) for _ in range(10000))
                pairs.append({"model": model, "candidate": candidate, "paired_tasks": len(values),
                              "delta_pp": round(100 * statistics.mean(values), 2),
                              "exploratory_95pct_task_bootstrap_pp": [round(100 * boot[249], 2), round(100 * boot[9749], 2)]})
    return {"fingerprint": fingerprint, "split": manifest.get("split"), "expected": len(expected), "observed": len(rows), "missing": len(expected - seen),
            "table": table, "paired": pairs, "behavioral_adjudications": len(overrides),
            "failed_runs": [{"id": r["id"], "status": r["status"], "functional_pass": r["functional_pass"],
                             "forbidden_changes": r["forbidden_changes"], "failure": r.get("outcome", {}).get("failure")} for r in rows if not effective(r)],
            "limits": "External tests cover declared cases, not arbitrary correctness. The split field records the frozen suite. Behavioral grades and visible-check strings are weaker evidence. Unadjusted exploratory intervals exclude infrastructure/model errors and do not establish equivalence. No confirmation winner inferred.",
            "reporter_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "rate_card_sha256": hashlib.sha256(Path(__file__).with_name("go-rates-2026-10-20.json").read_bytes()).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    report = analyze(args.directory)
    (args.directory / "analysis.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
