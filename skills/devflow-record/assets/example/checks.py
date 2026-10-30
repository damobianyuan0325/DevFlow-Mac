"""Run real assertions and report actual unittest counts for the demo runner."""
import json
import unittest

from feature import normalize_label


class LabelChecks(unittest.TestCase):
    def test_trims_edges_preserves_inner_spaces(self):
        self.assertEqual(normalize_label("  a  b\n"), "a  b")

    def test_plain_text_unchanged(self):
        self.assertEqual(normalize_label("DevFlow"), "DevFlow")

    def test_whitespace_rejected(self):
        with self.assertRaises(ValueError):
            normalize_label(" \t\n")


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LabelChecks)
    )
    failures = len(result.failures) + len(result.errors) + len(result.unexpectedSuccesses)
    skipped = len(result.skipped) + len(result.expectedFailures)
    print(json.dumps({"counts": {
        "total": result.testsRun,
        "passed": result.testsRun - failures - skipped,
        "failed": failures,
        "skipped": skipped,
    }}), flush=True)
    raise SystemExit(0 if result.wasSuccessful() else 1)
