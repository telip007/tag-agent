"""Result-integrity checks must fail independently of model behavior."""

import json
from pathlib import Path
import tempfile
import unittest

from report import build_report, digest


class ReportTests(unittest.TestCase):
    def fixture(self, directory):
        frozen = {"prompts": {"m": {"baseline": "x"}}, "tasks": [{"id": "t"}],
                  "repeats": 1, "split": "dev"}
        frozen["fingerprint"] = digest(frozen)
        (directory / "frozen.json").write_text(json.dumps(frozen))
        row = {"candidate": "baseline", "model": "m", "task": "t", "repeat": 0,
               "fingerprint": frozen["fingerprint"], "status": "ok", "passed": True,
               "usage": {"total_tokens": 12}, "message": {"content": "OK"}, "wall_seconds": 1}
        return frozen, row

    def test_missing_work_is_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            self.fixture(directory)
            (directory / "results.jsonl").write_text("")
            self.assertEqual(build_report(directory)["missing"], 1)

    def test_duplicate_rows_do_not_inflate_sample_count(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            _, row = self.fixture(directory)
            (directory / "results.jsonl").write_text((json.dumps(row) + "\n") * 2)
            with self.assertRaisesRegex(ValueError, "duplicate"):
                build_report(directory)

    def test_modified_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            frozen, row = self.fixture(directory)
            frozen["split"] = "holdout"
            (directory / "frozen.json").write_text(json.dumps(frozen))
            (directory / "results.jsonl").write_text(json.dumps(row) + "\n")
            with self.assertRaisesRegex(ValueError, "fingerprint"):
                build_report(directory)


if __name__ == "__main__":
    unittest.main()
