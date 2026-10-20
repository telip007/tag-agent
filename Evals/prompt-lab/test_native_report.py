import unittest
import hashlib
import json
from pathlib import Path
import tempfile

from native_report import analyze, resources
from benchmark import digest


class NativeResourceTests(unittest.TestCase):
    def test_per_success_usage_requires_every_attempted_request(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = {"models": ["m"], "policies": {"baseline": None},
                        "tasks": [{"id": task, "kind": "code"} for task in ["success", "timeout"]],
                        "repeats": 1, "source_hashes": {}}
            manifest["fingerprint"] = digest(manifest)
            (directory / "frozen.json").write_text(json.dumps(manifest))
            (directory / "runs").mkdir()
            rows = []
            for task in ["success", "timeout"]:
                passed = task == "success"
                row = {"id": f"m--baseline--{task}--0", "model": "m", "candidate": "baseline",
                       "task": task, "repeat": 0, "fingerprint": manifest["fingerprint"],
                       "status": "ok" if passed else "model_error", "passed": passed,
                       "functional_pass": passed, "forbidden_changes": [], "wall_seconds": 1,
                       "requested_check_observed": False,
                       "outcome": {"attemptedCalls": 1, "responses": [
                           {"inputTokens": 100, "outputTokens": 10}] if passed else []}}
                rows.append(row)
                (directory / "runs" / (row["id"] + ".json")).write_text(json.dumps({"row": row}))
            def report():
                (directory / "results.jsonl").write_text("".join(json.dumps(row) + "\n" for row in rows))
                return analyze(directory)["table"][0]
            incomplete = report()
            self.assertFalse(incomplete["usage_complete_for_attempted_calls"])
            self.assertEqual(incomplete["reported_tokens"], 110)
            self.assertIsNone(incomplete["reported_tokens_per_success"])
            rows[1]["outcome"]["responses"] = [{"inputTokens": 50, "outputTokens": 5}]
            (directory / "runs" / (rows[1]["id"] + ".json")).write_text(json.dumps({"row": rows[1]}))
            complete = report()
            self.assertTrue(complete["usage_complete_for_attempted_calls"])
            self.assertEqual(complete["reported_tokens_per_success"], 165)

    def test_cache_reads_and_output_are_costed_separately(self):
        result = resources("glm-5.3-flash", [{"inputTokens": 100, "cachedInputTokens": 80, "outputTokens": 10}])
        self.assertEqual(result["recorded_uncached_input_tokens"], 20)
        self.assertEqual(result["recorded_allowance_rate_value_usd_range"], [0.0000104, 0.0000104])

    def test_missing_cache_data_is_unknown_instead_of_assumed_zero(self):
        result = resources("glm-5.3-flash", [{"inputTokens": 100, "outputTokens": 10}])
        self.assertIsNone(result["recorded_cache_read_tokens"])
        self.assertIsNone(result["recorded_allowance_rate_value_usd_range"])

    def test_peak_timing_is_reported_as_a_range(self):
        result = resources("deepseek-v4.1-flash", [{"inputTokens": 100, "cachedInputTokens": 0, "outputTokens": 100}])
        low, high = result["recorded_allowance_rate_value_usd_range"]
        self.assertAlmostEqual(high, 2 * low)


class AdjudicationTests(unittest.TestCase):
    def fixture(self, directory, kind):
        manifest = {"models": ["m"], "policies": {"baseline": None}, "tasks": [{"id": "t", "kind": kind}],
                    "repeats": 1, "source_hashes": {}}
        manifest["fingerprint"] = digest(manifest)
        (directory / "frozen.json").write_text(json.dumps(manifest))
        row = {"id": "m--baseline--t--0", "model": "m", "candidate": "baseline", "task": "t", "repeat": 0,
               "fingerprint": manifest["fingerprint"], "status": "ok", "passed": False, "functional_pass": False,
               "forbidden_changes": [], "outcome": {"responses": []}, "wall_seconds": 1,
               "requested_check_observed": False}
        (directory / "results.jsonl").write_text(json.dumps(row) + "\n")
        (directory / "runs").mkdir()
        detail = directory / "runs" / (row["id"] + ".json")
        detail.write_text(json.dumps({"row": row, "final_files": {}}))
        decision = {"id": row["id"], "fingerprint": manifest["fingerprint"], "reviewed_passed": True,
                    "detail_sha256": hashlib.sha256(detail.read_bytes()).hexdigest()}
        (directory / "adjudications.json").write_text(json.dumps([decision]))
        return detail

    def test_behavioral_review_cannot_override_a_code_test_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.fixture(directory, "code")
            with self.assertRaisesRegex(ValueError, "adjudication"):
                analyze(directory)

    def test_review_keeps_raw_score_and_rejects_later_trajectory_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            detail = self.fixture(directory, "clarify")
            result = analyze(directory)
            self.assertEqual(result["table"][0]["raw_passed"], 0)
            self.assertEqual(result["table"][0]["passed"], 1)
            detail.write_text(detail.read_text() + " ")
            with self.assertRaisesRegex(ValueError, "adjudication"):
                analyze(directory)


if __name__ == "__main__":
    unittest.main()
