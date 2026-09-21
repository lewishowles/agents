#!/usr/bin/env python3
"""Focused tests for the staleness validation check."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = REPO_ROOT / "scripts/validate/check-staleness.py"


def load_staleness_module():
	"""Load the hyphenated validation script as a test module."""
	spec = importlib.util.spec_from_file_location("check_staleness", SCRIPT_PATH)
	if spec is None or spec.loader is None:
		raise RuntimeError(f"Unable to load {SCRIPT_PATH}")

	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	return module


class StalenessTests(unittest.TestCase):
	"""Verify source inventory and advisory staleness behaviour."""

	def test_canonical_rule_files_contribute_files(self):
		module = load_staleness_module()

		files = module.collect_files()
		rule_files = [
			path for path in files if module.REPO_ROOT / "src/rules" in path.parents
		]

		self.assertGreater(len(rule_files), 0)

	def test_empty_source_family_fails_validation(self):
		module = load_staleness_module()

		with tempfile.TemporaryDirectory() as temp_dir:
			root = Path(temp_dir)

			with (
				patch.object(module, "REPO_ROOT", root),
				patch.object(sys, "argv", [str(SCRIPT_PATH)]),
			):
				stderr = io.StringIO()
				with contextlib.redirect_stderr(stderr):
					status = module.main()

		self.assertEqual(status, 1)
		self.assertIn("Configured staleness source family is empty", stderr.getvalue())
		self.assertIn("src/rules", stderr.getvalue())

	def test_stale_files_remain_advisory(self):
		module = load_staleness_module()

		with tempfile.TemporaryDirectory() as temp_dir:
			root = Path(temp_dir)
			rules_dir = root / "src/rules"
			rules_dir.mkdir(parents=True)
			(rules_dir / "rule.md").write_text("rule\n")

			with (
				patch.object(module, "REPO_ROOT", root),
				patch.object(module, "SCAN_GLOBS", [("src/rules", "*.md")]),
				patch.object(module, "last_commit", return_value=("abc123", 0)),
				patch.object(module, "commits_since", return_value=2),
				patch.object(module.time, "time", return_value=2 * 86400),
				patch.object(
					sys, "argv", [str(SCRIPT_PATH), "--days", "1", "--commits", "1"]
				),
			):
				stdout = io.StringIO()
				with contextlib.redirect_stdout(stdout):
					status = module.main()

		self.assertEqual(status, 0)
		self.assertIn("stale file(s)", stdout.getvalue())


if __name__ == "__main__":
	unittest.main()
