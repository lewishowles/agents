#!/usr/bin/env python3
# Score repository drift by running reference checks and aggregating findings.
#
# Score starts at 100 and is reduced per issue:
#   missing_script  — -10  (agents directed to a non-existent script)
#   missing_path    —  -5  (stale path reference in agent docs)
#   not_executable  —  -5  (script exists but cannot be run)

from __future__ import annotations

import argparse
import datetime
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

DEDUCTIONS: dict[str, int] = {
	"missing_script": 10,
	"missing_path": 5,
	"not_executable": 5,
}

FIX_TEMPLATES: dict[str, str] = {
	"missing_path": "Update {file} — remove or fix reference to '{claim}' (path does not exist)",
	"missing_script": "Update {file} — remove or fix reference to '{claim}' (script missing from repo)",
	"not_executable": "Update {file} or run chmod +x {claim} — referenced script is not executable",
}


@dataclass
class Issue:
	file: str
	claim: str
	kind: str


# Runs the markdown claims check and returns its findings as Issue objects.
def run_claims_check() -> list[Issue]:
	result = subprocess.run(
		[
			"project-checks-markdown-claims",
			"--mode",
			"all",
			"--json",
		],
		capture_output=True,
		text=True,
		check=True,
	)
	try:
		data = json.loads(result.stdout)
	except json.JSONDecodeError:
		return []
	return [Issue(**item) for item in data.get("issues", [])]


# Deduplicates issues with the same (file, claim), keeping the highest deduction.
# This prevents the same missing scripts/ path from scoring as both missing_path
# and missing_script.
#
# @param  {list[Issue]}  issues
#     Raw issues from all checks, possibly overlapping.
def deduplicate(issues: list[Issue]) -> list[Issue]:
	best: dict[tuple[str, str], Issue] = {}
	for issue in issues:
		key = (issue.file, issue.claim)
		if key not in best or DEDUCTIONS.get(issue.kind, 5) > DEDUCTIONS.get(
			best[key].kind, 5
		):
			best[key] = issue
	return list(best.values())


# Computes score from issues. Minimum is 0.
#
# @param  {list[Issue]}  issues
#     Deduplicated issues collected from drift checks.
def compute_score(issues: list[Issue]) -> int:
	total_deduction = sum(DEDUCTIONS.get(i.kind, 5) for i in issues)
	return max(0, 100 - total_deduction)


def _format_issue(issue: Issue) -> str:
	label = {
		"missing_path": "missing path",
		"missing_script": "missing script",
		"not_executable": "not executable",
	}.get(issue.kind, issue.kind)
	deduction = DEDUCTIONS.get(issue.kind, 5)
	return f"  {issue.file}: {label} '{issue.claim}'  (-{deduction})"


def _format_fix_prompt(issue: Issue) -> str:
	template = FIX_TEMPLATES.get(issue.kind, "Fix '{claim}' in {file}")
	return "  • " + template.format(file=issue.file, claim=issue.claim)


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--json",
		action="store_true",
		help="Output results as JSON",
	)
	parser.add_argument(
		"--fix-prompts",
		action="store_true",
		help="Print one-line agent prompts for each finding",
	)
	args = parser.parse_args()

	issues = deduplicate(run_claims_check())
	score = compute_score(issues)

	if args.json:
		output = {
			"score": score,
			"max": 100,
			"checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
			"issues": [
				{
					"file": i.file,
					"claim": i.claim,
					"kind": i.kind,
					"deduction": DEDUCTIONS.get(i.kind, 5),
				}
				for i in issues
			],
		}
		print(json.dumps(output, indent=2))
		return

	print(f"Drift score: {score}/100")

	if issues:
		print()
		for issue in issues:
			print(_format_issue(issue))

	if args.fix_prompts and issues:
		print("\nFix prompts:")
		for issue in issues:
			print(_format_fix_prompt(issue))

	if not issues:
		print("No drift detected.")


if __name__ == "__main__":
	main()
