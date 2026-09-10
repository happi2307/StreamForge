"""
StreamForge Phase 6 - Migration Validation Tests

The handler lives in `validation/lambda/`, which is not importable as a package
(`lambda` is a Python keyword), so it is loaded by path. boto3 and pg8000 are
stubbed: these tests cover pure logic, and the handler only touches AWS and the
database at call time, never at import time.
"""

import importlib.util
import sys
import types
import unittest
from pathlib import Path

_pg8000 = types.ModuleType("pg8000")
_pg8000.native = types.SimpleNamespace(Connection=object)
sys.modules.setdefault("pg8000", _pg8000)
sys.modules.setdefault("pg8000.native", _pg8000.native)

_boto3 = types.ModuleType("boto3")
_boto3.client = lambda *a, **kw: None
sys.modules.setdefault("boto3", _boto3)

_HANDLER = Path(__file__).resolve().parents[1] / "validation" / "lambda" / "validation_handler.py"
_spec = importlib.util.spec_from_file_location("validation_handler", _HANDLER)
handler = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(handler)


class FakeConnection:
    """Returns a fixed count for every SELECT COUNT(*), or raises."""

    def __init__(self, count=5, error=None):
        self.count = count
        self.error = error

    def run(self, query):
        if self.error:
            raise RuntimeError(self.error)
        return [[self.count]]


class TestValidateRowCounts(unittest.TestCase):
    def test_counts_every_table(self):
        result = handler.validate_row_counts(FakeConnection(count=7))

        self.assertEqual(result["status"], "PASS")
        self.assertEqual(len(result["tables"]), 10)
        self.assertEqual(result["tables"]["customers"]["postgresql_count"], 7)

    def test_query_failure_is_reported_not_raised(self):
        result = handler.validate_row_counts(FakeConnection(error="relation does not exist"))

        self.assertEqual(result["status"], "ERROR")
        self.assertEqual(result["tables"]["orders"]["status"], "ERROR")
        self.assertIn("relation does not exist", result["tables"]["orders"]["error"])


class TestGenerateValidationReport(unittest.TestCase):
    def test_all_passing(self):
        report = handler.generate_validation_report(
            "test-001",
            {"row_counts": {"status": "PASS"}, "primary_keys": {"status": "PASS"}},
        )

        self.assertEqual(report["migration_id"], "test-001")
        self.assertEqual(report["overall_status"], "PASS")
        self.assertIn("validation_timestamp", report)

    def test_one_failure_fails_overall(self):
        report = handler.generate_validation_report(
            "test-002",
            {"row_counts": {"status": "PASS"}, "foreign_keys": {"status": "FAIL"}},
        )

        self.assertEqual(report["overall_status"], "FAIL")

    def test_error_fails_overall(self):
        report = handler.generate_validation_report(
            "test-003", {"checksums": {"status": "ERROR"}}
        )

        self.assertEqual(report["overall_status"], "FAIL")

    def test_summary_counts_individual_checks(self):
        report = handler.generate_validation_report(
            "test-004",
            {
                "primary_keys": {
                    "status": "FAIL",
                    "checks": [
                        {"status": "PASS"},
                        {"status": "PASS"},
                        {"status": "FAIL"},
                        {"status": "ERROR"},
                    ],
                }
            },
        )

        self.assertEqual(report["summary"]["total_checks"], 4)
        self.assertEqual(report["summary"]["passed_checks"], 2)
        self.assertEqual(report["summary"]["failed_checks"], 1)
        self.assertEqual(report["summary"]["errors"], 1)


if __name__ == "__main__":
    unittest.main()
