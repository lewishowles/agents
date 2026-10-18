#!/usr/bin/env python3
# Generate source-backed tables in docs so skill and hook lists do not drift.

import argparse
import json
from pathlib import Path

# The repository root, so the script finds its files from any working directory.
REPO_DIR = Path(__file__).resolve().parent.parent.parent
# The folder of Claude hook manifests that the hooks table is built from.
HOOKS_DIR = REPO_DIR / "src" / "hooks" / "claude"
# The folder of skill groups that the skills table is built from.
CANONICAL_SKILLS_DIR = REPO_DIR / "skills"


# Read a skill's name and description from the front matter of its SKILL.md.
# Descriptions written as folded (">") or literal ("|") blocks are joined
# into one line so they fit in a table cell.
#
# @param  {Path}  skill_file  The path to the skill's SKILL.md.
# @return {dict}  The skill's name and description.
def read_skill_metadata(skill_file: Path) -> dict:
	# The lines of the SKILL.md file, which must open with front matter.
	lines = skill_file.read_text().splitlines()
	if not lines or lines[0] != "---":
		raise ValueError(f"Missing front matter in {skill_file}")

	try:
		# The position of the line that closes the front matter.
		end = lines.index("---", 1)
	except ValueError as error:
		raise ValueError(f"Missing front matter end in {skill_file}") from error

	# The skill's name from its front matter, empty until the name line is found.
	name = ""
	# The lines of the skill's description, joined into one table cell at the end.
	description_lines = []
	# Whether the next lines continue a folded or literal block description.
	reading_description = False
	for line in lines[1:end]:
		if line.startswith("name:"):
			name = line.removeprefix("name:").strip()
			reading_description = False
			continue
		if line.startswith("description:"):
			# The text after the description key: the whole description, or the > or | that starts a block.
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
	# The name and description of each skill found so far.
	skills = []
	# The SKILL.md file of every skill.
	skill_files = CANONICAL_SKILLS_DIR.glob("*/*/SKILL.md")
	for skill_file in skill_files:
		skills.append(read_skill_metadata(skill_file))
	return sorted(skills, key=lambda item: item["name"])


# Return all Claude hook manifests in display order.
def hook_manifests() -> list[dict]:
	# The contents of each hook.json file found so far.
	manifests = []
	for hook_file in sorted(HOOKS_DIR.glob("*/hook.json")):
		manifests.append(json.loads(hook_file.read_text()))
	return sorted(manifests, key=lambda item: item["name"])


# Return generated block content between named markers.
#
# @param  {Path}  path  Markdown file path.
# @param  {str}   name  Marker name, e.g. user-skills.
def current_block(path: Path, name: str) -> str:
	# The comment that marks the start of the generated block.
	start = f"<!-- BEGIN GENERATED: {name} -->"
	# The comment that marks the end of the generated block.
	end = f"<!-- END GENERATED: {name} -->"
	# The full Markdown document.
	text = path.read_text()
	# The start marker (empty when the document lacks it) and the text after it.
	_, marker, rest = text.partition(start)
	if not marker:
		raise ValueError(f"Missing start marker {start} in {path}")
	# The current block content and the end marker (empty when the document lacks it).
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
	# The comment that marks the start of the generated block.
	start = f"<!-- BEGIN GENERATED: {name} -->"
	# The comment that marks the end of the generated block.
	end = f"<!-- END GENERATED: {name} -->"
	# The full Markdown document before the block is replaced.
	text = path.read_text()
	# The text before the start marker, the start marker (empty when the document lacks it) and the text after it.
	before, marker, rest = text.partition(start)
	if not marker:
		raise ValueError(f"Missing start marker {start} in {path}")
	# The end marker (empty when the document lacks it) and the text after it, which ends the rewritten document.
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
	# The rows of the skills table, starting with its header.
	lines = [
		"| Skill | When to use |",
		"| ----- | ----------- |",
	]
	for skill in skill_metadata():
		lines.append(f"| `{skill['name']}` | {cell(skill['description'])} |")
	return "\n".join(lines)


def build_registered_hooks_table() -> str:
	# The rows of the hooks table, starting with its header.
	lines = [
		"| Hook | Purpose | Event | Behaviour on failure |",
		"| ---- | ------- | ----- | -------------------- |",
	]
	for manifest in hook_manifests():
		# The hook's name, shown in the Hook column.
		name = manifest["name"]
		# The hook's purpose, shown in the Purpose column.
		description = manifest.get("description", "")
		# The labels of every event the hook runs on, for the Event column.
		events = []
		for event in manifest.get("events", []):
			# The event name, followed by its matcher when it has one.
			label = event["event"]
			if event.get("matcher"):
				label += f" (`{event['matcher']}`)"
			events.append(label)
		# The hook's failure mode, shown in the Behaviour on failure column.
		failure = manifest.get("failureMode", "")
		# The tools the hook needs installed.
		dependencies = manifest.get("dependencies", [])
		# The note that lists the hook's required tools after the failure mode, or empty when there are none.
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
	# The number of blocks that differ from what this script would write.
	failures = 0
	for path, name, body in generated_blocks():
		# The block content this script would write, including its generated notice.
		expected = f"{generated_notice()}\n{body.rstrip()}"
		if current_block(path, name) != expected:
			print(f"Out of sync: {path.relative_to(REPO_DIR)} ({name})")
			failures += 1
	return failures


def main() -> None:
	# The command-line parser, with a --check option that checks the docs tables without rewriting them.
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--check", action="store_true", help="Check generated docs without writing."
	)
	# The parsed command-line options.
	args = parser.parse_args()

	if args.check:
		# The number of blocks that are out of date.
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
