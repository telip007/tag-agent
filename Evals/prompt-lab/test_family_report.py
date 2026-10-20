import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from family_report import cluster_summary, compare_rows, load_experiments, merge_samples


def sample(policy, task="t", tokens=100, model="glm-5.3-flash", passed=True):
    return {"model": model, "candidate": policy, "task": task, "repeat": 0,
            "passed": passed, "reviewed_passed": passed, "functional_pass": passed,
            "forbidden_changes": [], "status": "ok", "wall_seconds": 1,
            "outcome": {"attemptedCalls": 1, "responses": [
                {"inputTokens": tokens, "outputTokens": 10, "cachedInputTokens": 0}]}}


class FamilyReportTests(unittest.TestCase):
    def test_uncertainty_resamples_tasks_without_treating_repeats_as_new_tasks(self):
        one = {"m1": {"a": [1], "b": [-1]}, "m2": {"a": [1], "b": [-1]}}
        repeated = {m: {t: values * 3 for t, values in tasks.items()} for m, tasks in one.items()}
        self.assertEqual(cluster_summary(one), cluster_summary(repeated))
        result = cluster_summary(one)
        self.assertEqual(result["point"], 0)
        self.assertEqual(result["exploratory_95pct_task_bootstrap"], [-100, 100])

    def test_model_weight_is_equal_and_missing_common_tasks_are_explicit(self):
        self.assertEqual(cluster_summary({"a": {"t": [1] * 9}, "b": {"t": [-1]}})["point"], 0)
        result = cluster_summary({"a": {"x": [1]}, "b": {"y": [1]}})
        self.assertEqual(result["common_tasks"], [])
        self.assertIsNone(result["point"])

    def test_duplicate_samples_are_not_counted_twice(self):
        row = sample("baseline")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            merge_samples([[row], [row]])

    def test_task_exclusion_is_uniform_and_preserves_raw_failure(self):
        rows = [sample("baseline"), sample("p", passed=False),
                sample("baseline", "ambiguous"), sample("p", "ambiguous", passed=False)]
        table = compare_rows(rows, {"ambiguous"})
        policy = next(item for item in table if item["candidate"] == "p")
        self.assertEqual(policy["all_tasks"]["passed"], 0)
        self.assertEqual(policy["selection_tasks"]["observed"], 1)
        self.assertEqual(policy["selection_tasks"]["passed"], 0)
        self.assertFalse(rows[3]["passed"])

    def test_missing_reply_usage_does_not_create_savings(self):
        base, candidate = sample("baseline"), sample("p")
        candidate["outcome"]["attemptedCalls"] = 2
        table = compare_rows([base, candidate], set())
        policy = next(item for item in table if item["candidate"] == "p")
        self.assertEqual(policy["resource_pairs"], 0)
        self.assertIsNone(policy["paired_geomean_token_ratio"])
        self.assertIsNone(policy["selection_resources"]["tokens_per_reviewed_success"])

    def test_failed_attempt_usage_is_included_in_cost_per_success(self):
        rows = [sample("baseline"), sample("baseline", "other"),
                sample("p"), sample("p", "other", passed=False)]
        policy = next(item for item in compare_rows(rows, set()) if item["candidate"] == "p")
        self.assertEqual(policy["paired_geomean_token_ratio"], 1.0)
        self.assertTrue(policy["selection_resources"]["usage_complete"])
        self.assertEqual(policy["selection_resources"]["tokens_per_reviewed_success"], 220)

    def test_pairing_uses_task_and_repeat_within_each_model(self):
        rows = [sample("baseline", tokens=190), sample("p", tokens=90),
                sample("p", "unpaired", tokens=999)]
        policy = next(item for item in compare_rows(rows, set()) if item["candidate"] == "p")
        self.assertEqual(policy["resource_pairs"], 1)
        self.assertEqual(policy["paired_geomean_token_ratio"], 0.5)

    def test_changed_task_or_generation_control_cannot_be_pooled(self):
        with tempfile.TemporaryDirectory() as temporary:
            directories = [Path(temporary) / name for name in ["a", "b"]]
            manifest = {"stage": "native", "split": "development", "max_calls": 12,
                        "max_tokens": 4096, "deadline_seconds": 180, "temperature": 0,
                        "reasoning": "provider defaults", "runner_binary_sha256": "bundle",
                        "tasks": [{"id": "t", "task": "original"}], "policies": {"baseline": None}}
            for directory in directories:
                directory.mkdir()
                (directory / "frozen.json").write_text(json.dumps(manifest))
                (directory / "results.jsonl").write_text("")
            audit = {"fingerprint": "fp", "expected": 1, "observed": 0}
            with patch("family_report.analyze", return_value=audit):
                for changed, pattern in [({**manifest, "max_tokens": 2048}, "controls"),
                                         ({**manifest, "context": {"position": "middle", "parts": ["a", "b"]}}, "controls"),
                                         ({**manifest, "tasks": [{"id": "t", "task": "changed"}]}, "task definition"),
                                         ({**manifest, "scaffold": "both", "policy_scaffolds": {"baseline": "lean"}}, "policy text"),
                                         ({**manifest, "policies": {"baseline": ["changed"]}}, "policy text")]:
                    (directories[1] / "frozen.json").write_text(json.dumps(changed))
                    with self.assertRaisesRegex(ValueError, pattern):
                        load_experiments(directories)


if __name__ == "__main__":
    unittest.main()
