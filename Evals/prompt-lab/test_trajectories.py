import json
from pathlib import Path
import tempfile
import unittest

from trajectories import behavior_grade, clean, configured_policies, context_treatment, fatal_row, read_policy, verify_reserve
from benchmark import digest


class TrajectoryTests(unittest.TestCase):
    def test_scaffold_labels_preserve_native_baseline_rules_and_distinguish_samples(self):
        self.assertEqual(configured_policies(["baseline"], "standard"), {"baseline": None})
        self.assertEqual(configured_policies(["baseline"], "lean"), {"baseline_lean": None})
        standard = configured_policies(["evidence"], "standard")
        lean = configured_policies(["evidence"], "lean")
        self.assertEqual(lean["evidence_lean"], standard["evidence"])
        with self.assertRaises(ValueError):
            configured_policies(["baseline"], "unknown")

    def test_joint_scaffold_schedule_keeps_each_treatment_distinct(self):
        both = configured_policies(["baseline", "evidence"], "both")
        self.assertEqual(set(both), {"baseline", "baseline_lean", "evidence", "evidence_lean"})
        self.assertIsNone(both["baseline_lean"])
        self.assertEqual(both["evidence"], both["evidence_lean"])
        with self.assertRaises(ValueError):
            configured_policies(["baseline_lean"], "both")

    def test_reserved_manifest_and_task_text_are_both_bound(self):
        tasks = [{"id": "t", "task": "original"}]
        reserved = {"tasks": tasks, "state": "unused"}
        reserved["fingerprint"] = digest(reserved)
        verify_reserve(tasks, reserved)
        with self.assertRaisesRegex(ValueError, "fingerprint"):
            verify_reserve(tasks, {**reserved, "state": "changed"})
        with self.assertRaisesRegex(ValueError, "tasks differ"):
            verify_reserve([{"id": "t", "task": "changed"}], reserved)

    def test_redaction_preserves_json_structure_and_later_evidence(self):
        original = {"prompt": "OS: macOS 27.0 (arm64)\nShell: bash\n", "grade": {"returncode": 0}}
        redacted = clean(original, {})
        decoded = json.loads(json.dumps(redacted))
        self.assertEqual(decoded["grade"], {"returncode": 0})
        self.assertIn("Shell: bash", decoded["prompt"])
        self.assertNotIn("27.0", decoded["prompt"])

    def test_redacts_nested_paths_without_changing_numbers_or_booleans(self):
        original = {"events": [{"output": "/private/task/file.py", "failed": False}], "count": 4}
        self.assertEqual(clean(original, {"/private/task": "/fixture"}),
                         {"events": [{"output": "/fixture/file.py", "failed": False}], "count": 4})

    def test_redacts_both_macos_temporary_path_spellings(self):
        for text in ["/var/folders/ab/private/T/check.py", "/private/var/folders/ab/private/T/check.py"]:
            self.assertEqual(clean(text, {}), "/temporary")

    def test_known_timeout_is_nonfatal_but_auth_and_infrastructure_errors_stop(self):
        self.assertFalse(fatal_row({"status": "model_error", "outcome": {"failure": "The request timed out."}}))
        self.assertFalse(fatal_row({"status": "model_error", "outcome": {"failure": "The network connection was lost."}}))
        self.assertTrue(fatal_row({"status": "model_error", "outcome": {"failure": "The API key was rejected."}}))
        self.assertTrue(fatal_row({"status": "infrastructure_error"}))
        self.assertFalse(fatal_row({"status": "generation_limit", "outcome": {"failure": "The model sent an empty reply."}}))

    def test_custom_policy_cannot_replace_baseline_or_make_unsafe_run_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "policy.json"
            for identifier in ["baseline", "../escape", "a/b"]:
                path.write_text(json.dumps({"id": identifier, "rules": ["A rule"]}))
                with self.assertRaises(ValueError):
                    read_policy(path)
            path.write_text(json.dumps({"id": "fresh", "rules": ["A rule"]}))
            self.assertEqual(read_policy(path), ("fresh", ["A rule"], None))
            path.write_text(json.dumps({"id": "fresh", "rules": ["A rule"], "scaffold": "lean"}))
            self.assertEqual(read_policy(path), ("fresh", ["A rule"], "lean"))
            path.write_text(json.dumps({"id": "fresh", "rules": ["A rule"], "scaffold": "both"}))
            with self.assertRaises(ValueError):
                read_policy(path)

    def test_explicit_choice_request_does_not_need_a_question_mark(self):
        task = {"kind": "clarify", "files": {"invoice.py": "stub"}}
        outcome = {"final": "Please choose:\n1. Half-even\n2. Half-up"}
        self.assertTrue(behavior_grade(task, outcome, {"invoice.py": "stub"}))
        self.assertFalse(behavior_grade(task, outcome, {"invoice.py": "stub", "implementation.py": "new code"}))

    def test_markdown_choice_request_has_the_same_meaning(self):
        task = {"kind": "clarify", "files": {"invoice.py": "stub"}}
        for text in ["**Please choose the rounding policy:**\n1. Half-even\n2. Half-up",
                     "_Select a rounding policy:_\nHalf-even or half-up"]:
            self.assertTrue(behavior_grade(task, {"final": text}, task["files"]))
        self.assertFalse(behavior_grade(task, {"final": "I chose half-up."}, task["files"]))

    def test_context_profile_binds_reserved_task_renderer_and_models(self):
        from transfer_fixtures import TRANSFER_TASKS
        task = next(task for task in TRANSFER_TASKS if task["id"] == "framed-client")
        context = context_treatment("middle", [task], ["glm-5.3-flash"])
        self.assertEqual(context["position"], "middle")
        self.assertEqual(sum(map(len, context["parts"])), 125952)
        with self.assertRaisesRegex(ValueError, "task"):
            context_treatment("middle", [{**task, "task": "changed"}], ["glm-5.3-flash"])
        with self.assertRaisesRegex(ValueError, "model"):
            context_treatment("middle", [task], ["unreserved-model"])
        with self.assertRaisesRegex(ValueError, "position"):
            context_treatment("elsewhere", [task], ["glm-5.3-flash"])


if __name__ == "__main__":
    unittest.main()
