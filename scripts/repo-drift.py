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

# The repository whose documentation references are checked for drift.
REPO_ROOT = Path(__file__).resolve().parent.parent

# The points removed from the repository score for each issue type.
DEDUCTIONS: dict[str, int] = {
	"missing_script": 10,
	"missing_path": 5,
	"not_executable": 5,
}

# The repair prompt shown for each kind of repository drift.
FIX_TEMPLATES: dict[str, str] = {
	"missing_path": "Update {file} — remove or fix reference to '{claim}' (path does not exist)",
	"missing_script": "Update {file} — remove or fix reference to '{claim}' (script missing from repo)",
	"not_executable": "Update {file} or run chmod +x {claim} — referenced script is not executable",
}


@dataclass
class Issue:
	# The documentation file that contains the broken reference.
	file: str
	# The path the documentation refers to.
	claim: str
	# The issue type, which sets the score deduction and the repair prompt.
	kind: str


# Runs doc-paths over the repository and returns each missing path as an Issue.
def run_doc_paths_check() -> list[Issue]:
	# The path check output, including its exit code and reported issues.
	result = subprocess.run(
		[
			"doc-paths",
			"--project-dir",
			str(REPO_ROOT),
			"--json",
		],
		capture_output=True,
		text=True,
	)

	# doc-paths exits 1 when it finds missing paths, which is drift to report rather than a failure.
	if result.returncode not in (0, 1):
		result.check_returncode()

	try:
		# The path check findings decoded from its JSON output.
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
	# The highest-scoring issue for each file and referenced path.
	best: dict[tuple[str, str], Issue] = {}
	for issue in issues:
		# The file and referenced path used to identify duplicate findings.
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
	# The combined score reduction from all distinct issues.
	total_deduction = sum(DEDUCTIONS.get(i.kind, 5) for i in issues)
	return max(0, 100 - total_deduction)


def _format_issue(issue: Issue) -> str:
	# The plain-language issue type printed in the terminal report.
	label = {
		"missing_path": "missing path",
		"missing_script": "missing script",
		"not_executable": "not executable",
	}.get(issue.kind, issue.kind)
	# The score reduction displayed beside this issue.
	deduction = DEDUCTIONS.get(issue.kind, 5)
	return f"  {issue.file}: {label} '{issue.claim}'  (-{deduction})"


def _format_fix_prompt(issue: Issue) -> str:
	# The repair prompt text for this issue type, or a generic fallback.
	template = FIX_TEMPLATES.get(issue.kind, "Fix '{claim}' in {file}")
	return "  • " + template.format(file=issue.file, claim=issue.claim)


def main() -> None:
	# The accepted options for the drift report command.
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
	# The output format and repair prompt options chosen for this run.
	args = parser.parse_args()

	# The distinct missing or invalid references found in repository documentation.
	issues = deduplicate(run_doc_paths_check())
	# The repository score after deductions for those references.
	score = compute_score(issues)

	if args.json:
		# The report fields serialised for machine-readable output.
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
