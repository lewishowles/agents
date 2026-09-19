#!/usr/bin/env python3
"""Create and check deterministic Git patch artefacts for proposed commits."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


# Unified diff context on every generated patch, so a reviewer sees enough
# surrounding code without the coordinator having to choose a value per call.
CONTEXT_LINES = 10

# Default ignored location for generated patch and metadata files.
DEFAULT_OUTPUT_DIRECTORY = Path(".agent/review-patches")

# Metadata schema version, bumped when a breaking change is made to the
# generated manifest or per-proposal metadata shape.
FORMAT_VERSION = 1

# Matches a unified diff hunk header line, used to split one diff block into
# its separate hunks.
HUNK_HEADER = re.compile(r"^@@ ")


class PatchError(RuntimeError):
	"""Report an invalid plan, repository state, or generated patch."""


def git_command(
	root: Path,
	arguments: list[str],
	*,
	input_bytes: bytes | None = None,
	env: dict[str, str] | None = None,
	expected_codes: tuple[int, ...] = (0,),
) -> subprocess.CompletedProcess[bytes]:
	"""Run one Git command and return its bounded binary result."""
	result = subprocess.run(
		["git", *arguments],
		cwd=root,
		env=env,
		input=input_bytes,
		stdout=subprocess.PIPE,
		stderr=subprocess.PIPE,
		check=False,
	)
	if result.returncode not in expected_codes:
		detail = result.stderr.decode("utf-8", errors="replace").strip()
		raise PatchError(
			f"git {' '.join(arguments)} failed with exit {result.returncode}: {detail}"
		)
	return result


def git_text(root: Path, arguments: list[str], *, expected_codes: tuple[int, ...] = (0,)) -> str:
	"""Run Git and decode its text output with Git-compatible path handling."""
	return git_command(root, arguments, expected_codes=expected_codes).stdout.decode(
		"utf-8", errors="surrogateescape"
	)


def nul_values(value: bytes) -> list[str]:
	"""Decode a NUL-separated Git path list in deterministic order."""
	return sorted(
		item.decode("utf-8", errors="surrogateescape")
		for item in value.split(b"\0")
		if item
	)


def repository_root(path: Path) -> Path:
	"""Return the absolute root of the Git repository containing `path`."""
	root = git_text(path, ["rev-parse", "--show-toplevel"]).strip()
	return Path(root).resolve()


def ensure_head(root: Path) -> str:
	"""Return the committed base revision used by generated patches."""
	return git_text(root, ["rev-parse", "--verify", "HEAD"]).strip()


def has_staged_changes(root: Path) -> bool:
	"""Return whether the real index contains staged content."""
	result = git_command(root, ["diff", "--cached", "--quiet"], expected_codes=(0, 1))
	return result.returncode == 1


def changed_paths(root: Path) -> list[str]:
	"""Return tracked and untracked worktree paths relative to the repository root."""
	tracked = git_command(
		root,
		[
			"diff",
			"--name-only",
			"--no-renames",
			"-z",
			"HEAD",
			"--",
		],
	).stdout
	untracked = git_command(
		root,
		["ls-files", "--others", "--exclude-standard", "-z"],
	).stdout
	return sorted(set(nul_values(tracked) + nul_values(untracked)))


def path_is_tracked_at_head(root: Path, path: str) -> bool:
	"""Return whether `path` exists in the committed base tree."""
	result = git_command(
		root,
		["ls-tree", "-r", "--name-only", "-z", "HEAD", "--", path],
	)
	return path in nul_values(result.stdout)


def validate_relative_path(path: str) -> str:
	"""Reject plan paths that could escape the repository root."""
	if not path or "\n" in path or "\r" in path or "\0" in path:
		raise PatchError(f"invalid plan path: {path!r}")
	if Path(path).is_absolute() or ".." in Path(path).parts:
		raise PatchError(f"plan path must stay inside the repository: {path!r}")
	return path


def raw_diff(root: Path, path: str) -> str:
	"""Return the full-index diff for one tracked or untracked path."""
	common = [
		"diff",
		"--binary",
		"--full-index",
		"--no-ext-diff",
		"--no-renames",
		f"--unified={CONTEXT_LINES}",
	]
	if path_is_tracked_at_head(root, path):
		result = git_command(root, [*common, "HEAD", "--", path])
	else:
		result = git_command(
			root,
			[*common, "--no-index", "/dev/null", path],
			expected_codes=(0, 1),
		)
	return result.stdout.decode("utf-8", errors="surrogateescape")


def diff_blocks(diff: str, path: str) -> list[str]:
	"""Return the single-path diff block, preserving all Git metadata."""
	if not diff:
		raise PatchError(f"no diff found for changed path {path!r}")
	lines = diff.splitlines(keepends=True)
	starts = [index for index, line in enumerate(lines) if line.startswith("diff --git ")]
	if len(starts) != 1:
		raise PatchError(f"expected one diff block for {path!r}, found {len(starts)}")
	return ["".join(lines[starts[0] :])]


def hunk_ranges(block: str) -> list[tuple[int, int]]:
	"""Return line ranges for complete textual hunks in one diff block."""
	lines = block.splitlines(keepends=True)
	starts = [index for index, line in enumerate(lines) if HUNK_HEADER.match(line)]
	return [
		(start, starts[position + 1] if position + 1 < len(starts) else len(lines))
		for position, start in enumerate(starts)
	]


def select_hunks(block: str, selected: list[int] | None, path: str) -> tuple[str, list[int]]:
	"""Select complete hunks while retaining the Git header and metadata."""
	ranges = hunk_ranges(block)
	if selected is None:
		return block, list(range(len(ranges)))
	if not ranges:
		raise PatchError(f"path {path!r} has no textual hunks and must be whole-file")
	if len(set(selected)) != len(selected) or any(index < 0 or index >= len(ranges) for index in selected):
		raise PatchError(f"invalid hunk selection for {path!r}: {selected!r}")
	lines = block.splitlines(keepends=True)
	prefix_end = ranges[0][0]
	selected_lines = lines[:prefix_end]
	for index in sorted(selected):
		start, end = ranges[index]
		selected_lines.extend(lines[start:end])
	return "".join(selected_lines), sorted(selected)


def content_bytes(root: Path, path: str) -> bytes | None:
	"""Read the current worktree content, or `None` when the path is deleted."""
	file_path = root / Path(path)
	if not file_path.exists() and not file_path.is_symlink():
		return None
	if file_path.is_symlink():
		return os.readlink(file_path).encode("utf-8", errors="surrogateescape")
	return file_path.read_bytes()


def head_bytes(root: Path, path: str) -> bytes | None:
	"""Read one path from `HEAD`, or `None` when the base has no path."""
	if not path_is_tracked_at_head(root, path):
		return None
	return git_command(root, ["show", f"HEAD:{path}"]).stdout


def sha256(value: bytes | None) -> str | None:
	"""Return a stable content hash, preserving the absence of deleted content."""
	if value is None:
		return None
	return hashlib.sha256(value).hexdigest()


def load_plan(plan_path: Path) -> list[dict[str, Any]]:
	"""Load and validate the coordinator-owned proposal list."""
	try:
		plan = json.loads(plan_path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		raise PatchError(f"cannot read plan {plan_path}: {error}") from error
	if not isinstance(plan, dict) or not isinstance(plan.get("proposals"), list) or not plan["proposals"]:
		raise PatchError("plan must contain a non-empty proposals list")
	proposals: list[dict[str, Any]] = []
	proposal_ids: set[str] = set()
	for proposal in plan["proposals"]:
		if not isinstance(proposal, dict):
			raise PatchError("each proposal must be an object")
		proposal_id = proposal.get("id")
		changes = proposal.get("changes")
		if not isinstance(proposal_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", proposal_id):
			raise PatchError(f"invalid proposal id: {proposal_id!r}")
		if proposal_id in proposal_ids:
			raise PatchError(f"duplicate proposal id: {proposal_id}")
		if not isinstance(changes, list) or not changes:
			raise PatchError(f"proposal {proposal_id} must contain changes")
		proposal_ids.add(proposal_id)
		proposals.append({"id": proposal_id, "title": proposal.get("title", proposal_id), "changes": changes})
	return proposals


def proposal_units(
	proposal: dict[str, Any],
	diffs: dict[str, str],
) -> tuple[set[tuple[str, int | str]], dict[str, list[int] | None]]:
	"""Validate one proposal and return its selected diff units and hunks."""
	units: set[tuple[str, int | str]] = set()
	selections: dict[str, list[int] | None] = {}
	seen_paths: set[str] = set()
	for change in proposal["changes"]:
		if not isinstance(change, dict) or not isinstance(change.get("path"), str):
			raise PatchError(f"proposal {proposal['id']} contains an invalid change")
		path = validate_relative_path(change["path"])
		if path in seen_paths:
			raise PatchError(f"proposal {proposal['id']} repeats path {path!r}")
		if path not in diffs:
			raise PatchError(f"proposal {proposal['id']} does not match changed path {path!r}")
		seen_paths.add(path)
		selected = change.get("hunks")
		if selected is not None and (
			not isinstance(selected, list) or not all(isinstance(index, int) for index in selected)
		):
			raise PatchError(f"hunks for {path!r} must be a list of integers")
		block, hunk_indexes = select_hunks(diffs[path], selected, path)
		if selected is None:
			units.update((path, index) for index in hunk_indexes)
			if not hunk_indexes:
				units.add((path, "whole"))
		else:
			units.update((path, index) for index in hunk_indexes)
		selections[path] = None if selected is None else hunk_indexes
		if not block:
			raise PatchError(f"proposal {proposal['id']} selected no patch content for {path!r}")
	return units, selections


def apply_check(root: Path, patch: bytes) -> None:
	"""Check a patch against a temporary index built from `HEAD`."""
	with tempfile.TemporaryDirectory(prefix="review-patches-index-") as directory:
		index_path = Path(directory) / "index"
		env = os.environ.copy()
		env["GIT_INDEX_FILE"] = str(index_path)
		git_command(root, ["read-tree", "HEAD"], env=env)
		git_command(
			root,
			["apply", "--check", "--cached", "--whitespace=nowarn", "-"],
			input_bytes=patch,
			env=env,
		)


def file_record(root: Path, path: str) -> dict[str, Any]:
	"""Return the current and base fingerprints for one changed path."""
	current = content_bytes(root, path)
	base = head_bytes(root, path)
	return {
		"path": path,
		"base_sha256": sha256(base),
		"worktree_sha256": sha256(current),
	}


def write_json(path: Path, value: dict[str, Any]) -> None:
	"""Write stable, human-readable JSON metadata."""
	path.write_text(json.dumps(value, ensure_ascii=False, indent="\t", sort_keys=True) + "\n", encoding="utf-8")


def generate(
	root: Path,
	plan_path: Path,
	output_directory: Path,
	*,
	staged_policy: str,
	refresh_id: str | None = None,
) -> dict[str, Any]:
	"""Generate all plan patches without changing the real worktree or index."""
	base_revision = ensure_head(root)
	if staged_policy not in {"refuse", "include"}:
		raise PatchError(f"unsupported staged policy: {staged_policy}")
	if has_staged_changes(root) and staged_policy == "refuse":
		raise PatchError("the index contains staged changes; choose an explicit staged policy")
	proposals = load_plan(plan_path)
	current_paths = changed_paths(root)
	if not current_paths:
		raise PatchError("the worktree has no tracked or untracked changes")
	diffs = {path: raw_diff(root, path) for path in current_paths}
	all_units: set[tuple[str, int | str]] = set()
	proposal_records: list[dict[str, Any]] = []
	for proposal in proposals:
		units, selections = proposal_units(proposal, diffs)
		duplicate_units = all_units.intersection(units)
		if duplicate_units:
			raise PatchError(f"units assigned to more than one proposal: {sorted(duplicate_units)!r}")
		all_units.update(units)
		proposal_records.append({"proposal": proposal, "selections": selections})
	if all_units == set():
		raise PatchError("plan selected no changed units")
	expected_units: set[tuple[str, int | str]] = set()
	for path, diff in diffs.items():
		ranges = hunk_ranges(diff)
		if ranges:
			expected_units.update((path, index) for index in range(len(ranges)))
		else:
			expected_units.add((path, "whole"))
	missing_units = expected_units - all_units
	if missing_units:
		raise PatchError(f"changed units are missing from the plan: {sorted(missing_units)!r}")
	if refresh_id is not None and refresh_id not in {record["proposal"]["id"] for record in proposal_records}:
		raise PatchError(f"cannot refresh unknown proposal {refresh_id!r}")
	plan_hash = sha256(plan_path.read_bytes())
	existing_manifest_proposals: dict[str, dict[str, Any]] = {}
	if refresh_id is not None:
		manifest_path = output_directory / "manifest.json"
		try:
			existing_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
		except (OSError, json.JSONDecodeError) as error:
			raise PatchError(f"cannot refresh without an existing manifest: {error}") from error
		if not isinstance(existing_manifest, dict) or not isinstance(existing_manifest.get("proposals"), list):
			raise PatchError("cannot refresh from a manifest without a proposals list")
		existing_manifest_proposals = {
			proposal["id"]: proposal
			for proposal in existing_manifest["proposals"]
			if isinstance(proposal, dict) and isinstance(proposal.get("id"), str)
		}
		missing_manifest_proposals = {
			record["proposal"]["id"]
			for record in proposal_records
			if record["proposal"]["id"] not in existing_manifest_proposals
		}
		if missing_manifest_proposals:
			raise PatchError(
				"cannot refresh because the manifest is missing proposals: "
				f"{sorted(missing_manifest_proposals)!r}"
			)
	output_directory.mkdir(parents=True, exist_ok=True)
	manifest_proposals: list[dict[str, Any]] = []
	for record in proposal_records:
		proposal = record["proposal"]
		selections = record["selections"]
		patch_parts: list[str] = []
		change_records: list[dict[str, Any]] = []
		for path in sorted(selections):
			selected = selections[path]
			selected_patch, selected_hunks = select_hunks(diffs[path], selected, path)
			patch_parts.append(selected_patch)
			change_records.append({**file_record(root, path), "hunks": selected_hunks})
		patch_bytes = "".join(patch_parts).encode("utf-8", errors="surrogateescape")
		if not patch_bytes:
			raise PatchError(f"proposal {proposal['id']} produced an empty patch")
		apply_check(root, patch_bytes)
		patch_path = output_directory / f"{proposal['id']}.patch"
		metadata_path = output_directory / f"{proposal['id']}.json"
		metadata = {
			"format_version": FORMAT_VERSION,
			"proposal": {"id": proposal["id"], "title": proposal["title"]},
			"base": base_revision,
			"context_lines": CONTEXT_LINES,
			"staged_policy": staged_policy,
			"diff_options": ["--binary", "--full-index", "--no-ext-diff", "--no-renames"],
			"changes": change_records,
			"patch": {"path": patch_path.name, "sha256": sha256(patch_bytes)},
			"freshness": "fresh",
			"apply_check": "passed",
		}
		manifest_proposal = {
			"id": proposal["id"],
			"patch": patch_path.name,
			"metadata": metadata_path.name,
			"sha256": metadata["patch"]["sha256"],
		}
		if refresh_id is None or proposal["id"] == refresh_id:
			patch_path.write_bytes(patch_bytes)
			write_json(metadata_path, metadata)
			manifest_proposals.append(manifest_proposal)
		else:
			manifest_proposals.append(existing_manifest_proposals[proposal["id"]])
	manifest = {
		"format_version": FORMAT_VERSION,
		"base": base_revision,
		"context_lines": CONTEXT_LINES,
		"staged_policy": staged_policy,
		"plan_sha256": plan_hash,
		"proposals": manifest_proposals,
	}
	write_json(output_directory / "manifest.json", manifest)
	return manifest


def check_metadata(root: Path, metadata_path: Path, base_revision: str) -> tuple[bool, list[str]]:
	"""Check one patch metadata file against current inputs and patch bytes."""
	try:
		metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		return False, [f"cannot read metadata: {error}"]
	issues: list[str] = []
	if metadata.get("base") != base_revision:
		issues.append("base revision changed")
	patch_name = metadata.get("patch", {}).get("path")
	if not isinstance(patch_name, str):
		return False, ["metadata has no patch path"]
	patch_path = metadata_path.parent / patch_name
	try:
		patch_bytes = patch_path.read_bytes()
	except OSError as error:
		return False, [f"cannot read patch: {error}"]
	if sha256(patch_bytes) != metadata.get("patch", {}).get("sha256"):
		issues.append("patch hash changed")
	for change in metadata.get("changes", []):
		path = change.get("path")
		if not isinstance(path, str):
			issues.append("metadata contains an invalid path")
			continue
		current = file_record(root, path)
		for key in ("base_sha256", "worktree_sha256"):
			if current[key] != change.get(key):
				issues.append(f"{path}: {key} changed")
	return not issues, issues


def check_directory(root: Path, directory: Path, plan_path: Path) -> int:
	"""Check generated proposals against the current plan, base, and inputs."""
	manifest_path = directory / "manifest.json"
	try:
		manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		print(f"stale: cannot read manifest: {error}")
		return 1
	base_revision = ensure_head(root)
	try:
		current_plan_hash = sha256(plan_path.read_bytes())
	except OSError as error:
		print(f"stale: cannot read plan: {error}")
		return 1
	stale = False
	if manifest.get("plan_sha256") != current_plan_hash:
		print("stale: plan changed")
		stale = True
	if manifest.get("base") != base_revision:
		print("stale: base revision changed")
		stale = True
	for proposal in manifest.get("proposals", []):
		metadata_name = proposal.get("metadata")
		if not isinstance(metadata_name, str):
			print(f"stale: proposal {proposal.get('id', '<unknown>')} has no metadata")
			stale = True
			continue
		fresh, issues = check_metadata(root, directory / metadata_name, base_revision)
		if fresh:
			print(f"fresh: {proposal['id']}")
		else:
			stale = True
			print(f"stale: {proposal.get('id', '<unknown>')}: {'; '.join(issues)}")
	return int(stale)


def write_file(root: Path, path: str, content: str) -> None:
	"""Write a self-test fixture beneath a temporary repository."""
	file_path = root / path
	file_path.parent.mkdir(parents=True, exist_ok=True)
	file_path.write_text(content, encoding="utf-8")


def selftest_git(root: Path, arguments: list[str]) -> None:
	"""Run a Git command used by the isolated self-test fixture."""
	git_command(root, arguments)


def run_selftest() -> None:
	"""Verify tracked, untracked, deleted, multi-hunk, stale, and apply cases."""
	with tempfile.TemporaryDirectory(prefix="review-patches-selftest-") as directory:
		root = Path(directory) / "repo"
		root.mkdir()
		selftest_git(root, ["init", "-q"])
		selftest_git(root, ["config", "user.email", "review-patches@example.test"])
		selftest_git(root, ["config", "user.name", "Review patches selftest"])
		tracked_lines = [f"line {index}\n" for index in range(40)]
		write_file(root, "tracked.txt", "".join(tracked_lines))
		write_file(root, "deleted.txt", "remove me\n")
		write_file(root, "unchanged.txt", "keep me\n")
		selftest_git(root, ["add", "."])
		selftest_git(root, ["commit", "-qm", "initial"])
		changed = tracked_lines.copy()
		changed[2] = "first change\n"
		changed[30] = "second change\n"
		write_file(root, "tracked.txt", "".join(changed))
		(root / "deleted.txt").unlink()
		write_file(root, "new.txt", "new content\n")
		plan_path = Path(directory) / "plan.json"
		plan = {
			"proposals": [
				{"id": "patch-first", "title": "First hunk", "changes": [{"path": "tracked.txt", "hunks": [0]}]},
				{"id": "patch-second", "title": "Second hunk", "changes": [{"path": "tracked.txt", "hunks": [1]}]},
				{"id": "patch-new", "title": "New file", "changes": [{"path": "new.txt"}]},
				{"id": "patch-delete", "title": "Deleted file", "changes": [{"path": "deleted.txt"}]},
			]
		}
		write_json(plan_path, plan)
		output_directory = Path(directory) / "artefacts"
		manifest = generate(root, plan_path, output_directory, staged_policy="refuse")
		assert len(manifest["proposals"]) == 4
		assert (output_directory / "patch-new.patch").read_text(encoding="utf-8").find("new file mode") >= 0
		assert (output_directory / "patch-delete.patch").read_text(encoding="utf-8").find("deleted file mode") >= 0
		assert all(
			json.loads((output_directory / proposal["metadata"]).read_text(encoding="utf-8"))["apply_check"] == "passed"
			for proposal in manifest["proposals"]
		)
		assert check_directory(root, output_directory, plan_path) == 0
		first_snapshot = (output_directory / "patch-first.patch").read_bytes()
		second_patch_snapshot = (output_directory / "patch-second.patch").read_bytes()
		second_metadata_snapshot = (output_directory / "patch-second.json").read_bytes()
		generate(root, plan_path, output_directory, staged_policy="refuse", refresh_id="patch-first")
		assert (output_directory / "patch-first.patch").read_bytes() == first_snapshot
		write_file(root, "tracked.txt", "feedback changed\n")
		assert check_directory(root, output_directory, plan_path) == 1
		write_file(root, "tracked.txt", "".join(changed[:30] + ["untouched drift\n"] + changed[31:]))
		assert check_directory(root, output_directory, plan_path) == 1
		generate(root, plan_path, output_directory, staged_policy="refuse", refresh_id="patch-first")
		assert (output_directory / "patch-second.patch").read_bytes() == second_patch_snapshot
		assert (output_directory / "patch-second.json").read_bytes() == second_metadata_snapshot
		assert check_directory(root, output_directory, plan_path) == 1
		write_file(root, "tracked.txt", "".join(changed))
		generate(root, plan_path, output_directory, staged_policy="refuse", refresh_id="patch-first")
		assert check_directory(root, output_directory, plan_path) == 0
		regrouped_plan = {
			"proposals": [
				{"id": "patch-first", "title": "First hunk", "changes": [{"path": "tracked.txt", "hunks": [1]}]},
				{"id": "patch-second", "title": "Second hunk", "changes": [{"path": "tracked.txt", "hunks": [0]}]},
				{"id": "patch-new", "title": "New file", "changes": [{"path": "new.txt"}]},
				{"id": "patch-delete", "title": "Deleted file", "changes": [{"path": "deleted.txt"}]},
			]
		}
		write_json(plan_path, regrouped_plan)
		assert check_directory(root, output_directory, plan_path) == 1
		write_json(plan_path, plan)
		assert check_directory(root, output_directory, plan_path) == 0
		selftest_git(root, ["add", "tracked.txt"])
		try:
			generate(root, plan_path, Path(directory) / "staged-refuse", staged_policy="refuse")
		except PatchError:
			pass
		else:
			raise AssertionError("staged changes were accepted under the refuse policy")
		included_manifest = generate(
			root,
			plan_path,
			Path(directory) / "staged-include",
			staged_policy="include",
		)
		assert included_manifest["staged_policy"] == "include"
		selftest_git(root, ["reset", "-q", "HEAD", "--", "tracked.txt"])
		overlapping_plan = Path(directory) / "overlap.json"
		write_json(
			overlapping_plan,
			{
				"proposals": [
					{"id": "one", "changes": [{"path": "tracked.txt", "hunks": [0]}]},
					{"id": "two", "changes": [{"path": "tracked.txt", "hunks": [0]}]},
				]
			},
		)
		try:
			generate(root, overlapping_plan, Path(directory) / "overlap-output", staged_policy="refuse")
		except PatchError:
			pass
		else:
			raise AssertionError("overlapping hunk assignment was accepted")
		assert not has_staged_changes(root)
	print("create_review_patches selftest passed")


def parse_arguments() -> argparse.Namespace:
	"""Parse isolated self-test, generation, refresh, and freshness-check modes."""
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--root", type=Path, default=Path.cwd())
	parser.add_argument("--plan", type=Path)
	parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIRECTORY)
	parser.add_argument("--check", type=Path)
	parser.add_argument("--refresh")
	parser.add_argument("--staged-policy", choices=("refuse", "include"))
	parser.add_argument("--include-staged", action="store_true")
	parser.add_argument("--selftest", action="store_true")
	arguments = parser.parse_args()
	if arguments.selftest:
		if any((arguments.plan, arguments.check, arguments.refresh, arguments.include_staged, arguments.staged_policy)):
			parser.error("--selftest cannot be combined with another mode")
		return arguments
	if arguments.check is not None and any((arguments.refresh, arguments.include_staged, arguments.staged_policy)):
		parser.error("--check cannot be combined with generation options")
	if arguments.check is None and arguments.plan is None:
		parser.error("--plan is required unless --check or --selftest is used")
	if arguments.refresh is not None and arguments.plan is None:
		parser.error("--refresh requires --plan")
	if arguments.include_staged:
		arguments.staged_policy = "include"
	elif arguments.staged_policy is None:
		arguments.staged_policy = "refuse"
	return arguments


def main() -> int:
	"""Run the requested helper mode and return a shell status."""
	arguments = parse_arguments()
	if arguments.selftest:
		run_selftest()
		return 0
	root = repository_root(arguments.root.resolve())
	if arguments.check is not None:
		check_path = arguments.check if arguments.check.is_absolute() else root / arguments.check
		plan_path = arguments.plan if arguments.plan is not None else check_path / "plan.json"
		plan_path = plan_path if plan_path.is_absolute() else root / plan_path
		return check_directory(root, check_path, plan_path)
	plan_path = arguments.plan if arguments.plan.is_absolute() else root / arguments.plan
	output_directory = arguments.output_dir if arguments.output_dir.is_absolute() else root / arguments.output_dir
	manifest = generate(
		root,
		plan_path,
		output_directory,
		staged_policy=arguments.staged_policy,
		refresh_id=arguments.refresh,
	)
	print(json.dumps(manifest, ensure_ascii=False, indent="\t", sort_keys=True))
	return 0


if __name__ == "__main__":
	try:
		raise SystemExit(main())
	except PatchError as error:
		print(f"error: {error}", file=sys.stderr)
		raise SystemExit(2)
