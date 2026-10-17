#!/usr/bin/env python3
# Generate source-backed tables in docs so skill and hook lists do not drift.

import argparse
import json
from pathlib import Path

# Anchor paths to this repository so the script works from any directory.
REPO_DIR = Path(__file__).resolve().parent.parent.parent
# Find the Claude hook manifests used in the generated table.
HOOKS_DIR = REPO_DIR / "src" / "hooks" / "claude"
# Find the canonical skill files used in the generated table.
CANONICAL_SKILLS_DIR = REPO_DIR / "skills"


# Read a skill's name and description from the front matter of its SKILL.md.
# Descriptions written as folded (">") or literal ("|") blocks are joined
# into one line so they fit in a table cell.
#
# @param  {Path}  skill_file  The path to the skill's SKILL.md.
# @return {dict}  The skill's name and description.
def read_skill_metadata(skill_file: Path) -> dict:
	# Read the front matter that supplies the table entry.
	lines = skill_file.read_text().splitlines()
	if not lines or lines[0] != "---":
		raise ValueError(f"Missing front matter in {skill_file}")

	try:
		# Find where the skill's front matter ends.
		end = lines.index("---", 1)
	except ValueError as error:
		raise ValueError(f"Missing front matter end in {skill_file}") from error

	# Hold the skill's display name from its front matter.
	name = ""
	# Collect description text for the table cell.
	description_lines = []
	# Track whether following lines belong to a block description.
	reading_description = False
	for line in lines[1:end]:
		if line.startswith("name:"):
			name = line.removeprefix("name:").strip()
			reading_description = False
			continue
		if line.startswith("description:"):
			# Read either the complete description or the start of a block.
			description = line.removeprefix("description:").strip()
			reading_description = description.startswith((">", "|"))
			if not reading_description:
				description_lines = [description]
			continue
		if reading_description:
			if line.startswith(" ") or not line:
				description_lines.append(line.strip())
				continue
			reading_description = False

	if not name or not description_lines:
		raise ValueError(f"Missing name or description in {skill_file}")

	return {"name": name, "description": " ".join(description_lines)}


# Return the name and description of every skill under skills/<group>/,
# sorted by name.
def skill_metadata() -> list[dict]:
	# Collect the metadata for every skill in the generated table.
	skills = []
	# The SKILL.md file of every skill.
	skill_files = CANONICAL_SKILLS_DIR.glob("*/*/SKILL.md")
	for skill_file in skill_files:
		skills.append(read_skill_metadata(skill_file))
	return sorted(skills, key=lambda item: item["name"])


# Return all Claude hook manifests in display order.
def hook_manifests() -> list[dict]:
	# Collect the hook definitions for the generated table.
	manifests = []
	for hook_file in sorted(HOOKS_DIR.glob("*/hook.json")):
		manifests.append(json.loads(hook_file.read_text()))
	return sorted(manifests, key=lambda item: item["name"])


# Return generated block content between named markers.
#
# @param  {Path}  path  Markdown file path.
# @param  {str}   name  Marker name, e.g. user-skills.
def current_block(path: Path, name: str) -> str:
	# Identify the opening marker for the requested generated block.
	start = f"<!-- BEGIN GENERATED: {name} -->"
	# Identify the closing marker for the requested generated block.
	end = f"<!-- END GENERATED: {name} -->"
	# Read the document whose generated block is being checked.
	text = path.read_text()
	# Keep the text after the opening marker for the closing-marker check.
	_, marker, rest = text.partition(start)
	if not marker:
		raise ValueError(f"Missing start marker {start} in {path}")
	# Keep the current block content for comparison with generated content.
	body, marker, _ = rest.partition(end)
	if not marker:
		raise ValueError(f"Missing end marker {end} in {path}")
	return body.strip()


# Replace generated block content between named markers.
#
# @param  {Path}  path  Markdown file path.
# @param  {str}   name  Marker name, e.g. user-skills.
# @param  {str}   body
#     New block content without surrounding markers.
def replace_block(path: Path, name: str, body: str) -> None:
	# Identify the opening marker to preserve the document around the block.
	start = f"<!-- BEGIN GENERATED: {name} -->"
	# Identify the closing marker to preserve the document around the block.
	end = f"<!-- END GENERATED: {name} -->"
	# Read the document before replacing its generated block.
	text = path.read_text()
	# Preserve the text before the block and find its closing marker.
	before, marker, rest = text.partition(start)
	if not marker:
		raise ValueError(f"Missing start marker {start} in {path}")
	# Preserve the text after the block for the rewritten document.
	_, marker, after = rest.partition(end)
	if not marker:
		raise ValueError(f"Missing end marker {end} in {path}")
	path.write_text(
		f"{before}{start}\n{generated_notice()}\n{body.rstrip()}\n{end}{after}"
	)


def generated_notice() -> str:
	return "<!-- Generated by scripts/build/build-docs.py. Edit SKILL.md or hook.json, then run scripts/sync.sh. -->"


# Keep table cells on one line.
#
# @param  {str}  value  Cell text.
def cell(value: str) -> str:
	return value.replace("\n", " ").replace("|", "\\|")


def build_user_skills_table() -> str:
	# Start the skill table with its headings.
	lines = [
		"| Skill | When to use |",
		"| ----- | ----------- |",
	]
	for skill in skill_metadata():
		lines.append(f"| `{skill['name']}` | {cell(skill['description'])} |")
	return "\n".join(lines)


def build_registered_hooks_table() -> str:
	# Start the hook table with its headings.
	lines = [
		"| Hook | Purpose | Event | Behaviour on failure |",
		"| ---- | ------- | ----- | -------------------- |",
	]
	for manifest in hook_manifests():
		# Show the hook's registered name in the table.
		name = manifest["name"]
		# Show the hook's stated purpose in the table.
		description = manifest.get("description", "")
		# Collect the events that appear in the hook's table cell.
		events = []
		for event in manifest.get("events", []):
			# Show the event and any matcher required to run the hook.
			label = event["event"]
			if event.get("matcher"):
				label += f" (`{event['matcher']}`)"
			events.append(label)
		# Show how the hook behaves when it fails.
		failure = manifest.get("failureMode", "")
		# List the tools the hook needs to run.
		dependencies = manifest.get("dependencies", [])
		# Add required tools to the hook's failure-behaviour cell.
		dependency_text = (
			f"; requires {', '.join(dependencies)}" if dependencies else ""
		)
		lines.append(
			f"| `{name}` | {cell(description)} | {cell(', '.join(events))} | `{failure}`{dependency_text} |"
		)
	return "\n".join(lines)


# Return all (path, marker-name, body) triples for every generated block across all docs files.
def generated_blocks() -> list[tuple[Path, str, str]]:
	return [
		(REPO_DIR / "docs" / "skills.md", "user-skills", build_user_skills_table()),
		(
			REPO_DIR / "docs" / "hooks.md",
			"registered-hooks",
			build_registered_hooks_table(),
		),
	]


# Return the number of generated blocks whose on-disk content does not match what would be generated.
def check_blocks() -> int:
	# Count generated blocks whose document content needs updating.
	failures = 0
	for path, name, body in generated_blocks():
		# Compare each block with the content this script would write.
		expected = f"{generated_notice()}\n{body.rstrip()}"
		if current_block(path, name) != expected:
			print(f"Out of sync: {path.relative_to(REPO_DIR)} ({name})")
			failures += 1
	return failures


def main() -> None:
	# Define the command-line option for checking generated documents.
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--check", action="store_true", help="Check generated docs without writing."
	)
	# Select whether to check or write the generated blocks.
	args = parser.parse_args()

	if args.check:
		# Count blocks that differ from the generated content.
		failures = check_blocks()
		if failures:
			raise SystemExit(1)
		print("Generated docs tables in sync.")
		return

	for path, name, body in generated_blocks():
		replace_block(path, name, body)
	print("Generated docs tables.")


if __name__ == "__main__":
	main()
