#!/usr/bin/env python3
# Flag rule files unchanged for too long.
# Warns when a file has not been committed in N days or N repo commits.
# Staleness findings are advisory; an invalid source inventory fails validation.

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

# The repository root used to find source files and run Git commands.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# The default age in days before an unchanged rule can be reported as stale.
DEFAULT_DAYS = 45
# The default number of newer commits before a rule can be reported as stale.
DEFAULT_COMMITS = 200

# The source folders and file patterns checked for stale rules.
SCAN_GLOBS = [
	("src/rules", "*.md"),
]


class SourceInventoryError(RuntimeError):
	"""Raised when a configured source family contains no files."""


def collect_files() -> list[Path]:
	"""Collect files from every configured source family."""

	# The rule files collected from every folder in SCAN_GLOBS.
	files = []
	for directory, pattern in SCAN_GLOBS:
		# The absolute path of this configured source folder.
		d = REPO_ROOT / directory
		# The matching files in this folder, or an empty list when it is absent.
		matches = (
			sorted(path for path in d.glob(pattern) if path.is_file())
			if d.is_dir()
			else []
		)
		if not matches:
			raise SourceInventoryError(
				f"Configured staleness source family is empty: {d} ({pattern})"
			)
		files.extend(matches)
	return files


# Returns (last_commit_hash, commit_timestamp) for a file, or None if untracked.
#
# @param  {Path}  path
#     Absolute path of the file to query.
def last_commit(path: Path) -> tuple[str, int] | None:
	# The Git result containing this file's latest commit hash and timestamp.
	result = subprocess.run(
		["git", "log", "-1", "--format=%H %ct", "--", str(path)],
		capture_output=True,
		text=True,
		cwd=REPO_ROOT,
	)
	# The latest commit hash and timestamp on one line (empty when the file is untracked).
	line = result.stdout.strip()
	if not line:
		return None
	# The commit hash and timestamp separated for the return value.
	parts = line.split()
	return parts[0], int(parts[1])


# Returns the number of repo commits made after the given commit hash.
#
# @param  {str}  commit_hash
#     The commit to measure from.
def commits_since(commit_hash: str) -> int:
	# The Git result containing the number of commits since this hash.
	result = subprocess.run(
		["git", "rev-list", "--count", f"{commit_hash}..HEAD"],
		capture_output=True,
		text=True,
		cwd=REPO_ROOT,
	)
	try:
		return int(result.stdout.strip())
	except ValueError:
		return 0


def main() -> int:
	# The command-line parser for the staleness thresholds.
	parser = argparse.ArgumentParser()
	parser.add_argument("--days", type=int, default=DEFAULT_DAYS)
	parser.add_argument("--commits", type=int, default=DEFAULT_COMMITS)
	# The day and commit thresholds selected for this run.
	args = parser.parse_args()

	# The current Unix timestamp used to measure each file's age.
	now = int(time.time())
	try:
		# The source files whose last commits will be checked.
		files = collect_files()
	except SourceInventoryError as error:
		print(f"ERROR: {error}", file=sys.stderr)
		return 1

	# The number of stale files reported during this run.
	warnings = 0

	for path in files:
		# The latest commit details for this file, or None when it is untracked.
		info = last_commit(path)
		if info is None:
			continue

		# The file's latest commit hash and its Unix timestamp.
		commit_hash, timestamp = info
		# The number of whole days since the file's latest commit.
		age_days = (now - timestamp) // 86400
		# The number of repository commits since the file's latest commit.
		age_commits = commits_since(commit_hash)
		# The file path relative to the repository root for the warning.
		rel = path.relative_to(REPO_ROOT)

		if age_days >= args.days and age_commits >= args.commits:
			print(f"  {rel}: unchanged for {age_days} days ({age_commits} commits)")
			warnings += 1

	if warnings:
		print(
			f"  {warnings} stale file(s) — review for drift against current runtime behaviour"
		)

	return 0


if __name__ == "__main__":
	raise SystemExit(main())
