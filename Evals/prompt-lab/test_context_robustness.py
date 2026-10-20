import unittest

from context_robustness import render_context_task


class ContextTreatmentTests(unittest.TestCase):
    def test_default_retains_the_exact_original_task(self):
        self.assertEqual(render_context_task("Original task.", None), "Original task.")

    def test_positions_reorder_the_same_blocks_without_losing_task_or_data(self):
        texts = [render_context_task("UNIQUE_TASK", {"parts": ["ARCHIVE_ONE", "ARCHIVE_TWO"], "position": position})
                 for position in ["beginning", "middle", "end"]]
        self.assertEqual(len({len(text) for text in texts}), 1)
        for text in texts:
            self.assertEqual(text.count("UNIQUE_TASK"), 1)
            self.assertEqual(text.count("ARCHIVE_ONE"), 1)
            self.assertEqual(text.count("ARCHIVE_TWO"), 1)
        self.assertLess(texts[0].index("UNIQUE_TASK"), texts[0].index("ARCHIVE_ONE"))
        self.assertLess(texts[1].index("ARCHIVE_ONE"), texts[1].index("UNIQUE_TASK"))
        self.assertLess(texts[1].index("UNIQUE_TASK"), texts[1].index("ARCHIVE_TWO"))
        self.assertGreater(texts[2].index("UNIQUE_TASK"), texts[2].index("ARCHIVE_TWO"))

    def test_unknown_position_or_malformed_parts_fail_instead_of_silently_changing_control(self):
        for context in [{"parts": ["a", "b"], "position": "unknown"},
                        {"parts": ["one"], "position": "middle"},
                        {"parts": ["a", 4], "position": "end"}]:
            with self.assertRaises(ValueError):
                render_context_task("Task", context)


if __name__ == "__main__":
    unittest.main()
