import copy
import unittest

from confirmation_report import summarize, validate_run


class ConfirmationReportTests(unittest.TestCase):
    def test_reserved_controls_task_and_policy_cannot_change_after_freeze(self):
        plan = {"models": ["m"], "repeats": 3, "max_calls": 12, "max_tokens": 4096,
                "deadline_seconds": 180, "workers": 2}
        policy = {"id": "recommendation", "rules": ["Frozen rule"], "scaffold": "standard"}
        freeze = {"confirmation_plan": plan, "compiled_bundle_sha256": "bundle",
                  "artifacts_sha256": {"trajectories.py": "controller"}}
        reserve = {"tasks": [{"id": "t", "task": "frozen task"}]}
        manifest = {"stage": "native-trajectories", "split": "confirmation", "models": ["m"],
                    "policies": {"baseline": None, "recommendation": ["Frozen rule"]},
                    "policy_scaffolds": {"baseline": "standard", "recommendation": "standard"},
                    "scaffold": "standard", "repeats": 3, "repeat_offset": 0, "temperature": 0,
                    "reasoning": "provider defaults", "runner_binary_sha256": "bundle",
                    "tasks": reserve["tasks"], "source_hashes": {"Evals/prompt-lab/trajectories.py": "controller"},
                    **{key: plan[key] for key in ["max_calls", "max_tokens", "deadline_seconds", "workers"]}}
        validate_run(manifest, "confirmation", reserve, freeze, policy)
        for changed in [{"repeats": 2}, {"context": {"position": "middle"}},
                        {"policies": {"baseline": None, "recommendation": ["Revised rule"]}},
                        {"tasks": [{"id": "t", "task": "easier task"}]},
                        {"source_hashes": {}},
                        {"source_hashes": {"Evals/prompt-lab/trajectories.py": "different"}}]:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                validate_run({**manifest, **changed}, "confirmation", reserve, freeze, policy)

    def test_sensitivity_drops_whole_task_uniformly_without_regrading_primary(self):
        rows = []
        for model in ["m1", "m2"]:
            for candidate in ["baseline", "recommendation"]:
                for task in ["clear", "ambiguous"]:
                    for repeat in [0, 1]:
                        passed = candidate != "baseline" or task != "ambiguous"
                        rows.append({"model": model, "candidate": candidate, "task": task,
                                     "repeat": repeat, "passed": passed, "reviewed_passed": passed,
                                     "functional_pass": passed, "forbidden_changes": [], "status": "ok",
                                     "wall_seconds": 1, "outcome": {"attemptedCalls": 1,
                                     "responses": [{"inputTokens": 100, "outputTokens": 10, "cachedInputTokens": 0}]}})
        original = copy.deepcopy(rows)
        primary = summarize(rows)
        sensitivity = summarize(rows, ["ambiguous"])
        self.assertEqual(primary["observed"], 16)
        self.assertEqual(sensitivity["observed"], 8)
        self.assertEqual(sum(item["all_tasks"]["passed"] for item in primary["table"]), 12)
        self.assertEqual(sum(item["all_tasks"]["passed"] for item in sensitivity["table"]), 8)
        self.assertTrue(all(item["all_tasks"]["observed"] == 2 for item in sensitivity["table"]))
        self.assertEqual(rows, original)


if __name__ == "__main__":
    unittest.main()
