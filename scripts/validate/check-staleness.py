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

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

DEFAULT_DAYS = 45
DEFAULT_COMMITS = 200

SCAN_GLOBS = [
	("src/rules", "*.md"),
]


class SourceInventoryError(RuntimeError):
	"""Raised when a configured source family contains no files."""


def collect_files() -> list[Path]:
	"""Collect files from every configured source family."""

	files = []
	for directory, pattern in SCAN_GLOBS:
		d = REPO_ROOT / directory
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
	result = subprocess.run(
		["git", "log", "-1", "--format=%H %ct", "--", str(path)],
		capture_output=True,
		text=True,
		cwd=REPO_ROOT,
	)
	line = result.stdout.strip()
	if not line:
		return None
	parts = line.split()
	return parts[0], int(parts[1])


# Returns the number of repo commits made after the given commit hash.
#
# @param  {str}  commit_hash
#     The commit to measure from.
def commits_since(commit_hash: str) -> int:
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
	parser = argparse.ArgumentParser()
	parser.add_argument("--days", type=int, default=DEFAULT_DAYS)
	parser.add_argument("--commits", type=int, default=DEFAULT_COMMITS)
	args = parser.parse_args()

	now = int(time.time())
	try:
		files = collect_files()
	except SourceInventoryError as error:
		print(f"ERROR: {error}", file=sys.stderr)
		return 1

	warnings = 0

	for path in files:
		info = last_commit(path)
		if info is None:
			continue

		commit_hash, timestamp = info
		age_days = (now - timestamp) // 86400
		age_commits = commits_since(commit_hash)
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
