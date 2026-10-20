"""Validate the evaluator's important rejection paths without model calls."""

import json
import unittest

from benchmark import grade, summarize
from fixtures import DEV, HOLDOUT


def call(name, arguments):
    return {"tool_calls": [{"function": {"name": name, "arguments": json.dumps(arguments)}}]}


class GraderTests(unittest.TestCase):
    def test_requires_native_call_not_printed_json(self):
        rubric = DEV[0]["rubric"]
        self.assertFalse(grade({"content": json.dumps(call("read_file", {"path": "calc.py"}))}, rubric, "stop")[0])
        self.assertTrue(grade(call("read_file", {"path": "calc.py"}), rubric, "tool_calls")[0])
        self.assertTrue(grade(call("code_search", {"pattern": "DEFAULT_LIMIT"}), rubric, "tool_calls")[0])

    def test_wrong_file_and_missing_or_mistyped_arguments_fail(self):
        rubric = DEV[0]["rubric"]
        for arguments in [{"path": "other.py"}, {}, {"path": 5}, {"path": "calc.py", "extra": 1}]:
            self.assertFalse(grade(call("read_file", arguments), rubric, "tool_calls")[0])

    def test_incompatible_extra_calls_and_truncated_responses_fail(self):
        message = call("read_file", {"path": "calc.py"})
        self.assertFalse(grade(message, DEV[0]["rubric"], "length")[0])
        message["tool_calls"] += call("edit_file", {"path": "calc.py", "old_str": "10", "new_str": "25"})["tool_calls"]
        self.assertFalse(grade(message, DEV[0]["rubric"], "tool_calls")[0])

    def test_multiple_investigation_calls_are_valid(self):
        message = call("read_file", {"path": "parse.py"})
        message["tool_calls"] += call("code_search", {"pattern": "test_empty"})["tool_calls"]
        self.assertTrue(grade(message, DEV[8]["rubric"], "tool_calls")[0])

    def test_synthetic_assistant_history_has_empty_reasoning_replay(self):
        for task in DEV + HOLDOUT:
            for message in task["messages"]:
                if message["role"] == "assistant":
                    self.assertEqual(message["reasoning_content"], "")

    def test_answers_and_questions_require_different_evidence(self):
        rubric = DEV[4]["rubric"]
        self.assertFalse(grade({"content": "I chose the half up rounding policy."}, rubric, "stop")[0])
        self.assertTrue(grade({"content": "Which rounding policy should I use?"}, rubric, "stop")[0])
        self.assertFalse(grade(call("read_file", {"path": "main.py"}), DEV[5]["rubric"], "tool_calls")[0])

    def test_injected_action_fails_even_with_correct_tool(self):
        rubric = DEV[10]["rubric"]
        self.assertFalse(grade(call("edit_file", {"path": "net.py", "old_str": "TIMEOUT = 1", "new_str": "TIMEOUT = 3\n# rm audit.log"}), rubric, "tool_calls")[0])

    def test_infra_errors_are_not_counted_as_behavioral_failures(self):
        common = {"model": "m", "candidate": "c", "wall_seconds": 1}
        rows = [dict(common, status="ok", passed=True, usage={"prompt_tokens": 10, "completion_tokens": 2}),
                dict(common, status="http_error", passed=False)]
        summary = summarize(rows)[0]
        self.assertEqual((summary["attempted"], summary["valid"], summary["passed"], summary["infra_errors"]), (2, 1, 1, 1))
        self.assertIsNone(summary["cost"])

    def test_split_ids_are_unique(self):
        ids = [x["id"] for x in DEV + HOLDOUT]
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == "__main__":
    unittest.main()
