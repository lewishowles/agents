#!/usr/bin/env bash
# Checks the default skill-list size, skill links, reference files, and retired names.
# The recorded limit is lowered after each skill-family merge.

set -euo pipefail

# The repository containing the canonical skills and validation sources.
REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)

# Runs the checks in Python, which reads front matter and Markdown links more reliably than shell.
python3 - "$REPO_DIR" <<'PY'
"""Check skill-list size, links, reference files, and retired names without installing skills."""

import re
import shlex
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


# The repository containing the canonical skills and validation sources.
REPO_DIR = Path(sys.argv[1]).resolve()
# The largest allowed default skill list, in estimated tokens. Lower it to the new size after each merge.
SKILL_LIST_LIMIT = 4184
# The size of Codex's whole skill list for gpt-6-sol, shared with Codex's own and external skills.
CODEX_LIST_BUDGET = 5440
# Skill names removed by family merges; add names here when retiring them.
RETIRED_SKILL_NAMES: tuple[str, ...] = (
	"test-unit", "test-e2e", "vue-vite", "vue-router", "vue-pinia", "vue-pinia-colada", "vue-project-stack", "writing-copy", "writing-readme"
)
# Retired skill names that are also package names. Any mention inside code spans or code blocks counts as the package,
# so a backticked reference to one of these skills is not reported.
RETIRED_NAMES_ALSO_PACKAGES = frozenset({"vue-router"})
# A Markdown link, capturing its address without any title.
LINK_PATTERN = re.compile(r"\]\((<?[^)\s>]+>?)(?:\s+[^)]*)?\)")
# An inline code span, which holds an example rather than a real link.
INLINE_CODE_PATTERN = re.compile(r"(`+)(.*?)\1")
# A fenced code block, which holds examples rather than real links. The closing fence must match the opening one.
FENCED_CODE_PATTERN = re.compile(r"(?ms)^[ \t]*(`{3,}|~{3,})[^\n]*\n.*?^[ \t]*\1[^\n]*$")


def main() -> int:
	"""Print the skill-list size, report each problem on stderr, and return 1 when any check fails."""
	# Problems found in the skill catalogue.
	problems: list[str] = []
	# Canonical skill files in collection and name order.
	skill_files = sorted((REPO_DIR / "skills").glob("*/*/SKILL.md"))
	# Collections excluded from a fresh setup.
	default_off = read_default_off_collections()
	# Estimated tokens in the Codex lines for skills installed by default.
	skill_list_size = 0
	# Number of skills included in the size check.
	default_skill_count = 0

	for skill_file in skill_files:
		# The name and description Codex shows for this skill.
		skill_name, description = read_metadata(skill_file)

		if skill_file.parent.parent.name not in default_off:
			# The installed path Codex prints after each description.
			locator = Path.home() / ".agents" / "skills" / skill_name / "SKILL.md"
			# This skill's line in Codex's list, in the format Codex 0.164.0 uses.
			line = f"- {skill_name}: {description} (file: {locator})"
			# Estimate tokens as bytes divided by four, rounded up for each line.
			skill_list_size += (len(line.encode("utf-8")) + 3) // 4
			default_skill_count += 1

		problems.extend(check_links(skill_file))

	problems.extend(check_retired_names())
	print(
		f"Default skill list: {skill_list_size}/{SKILL_LIST_LIMIT} estimated tokens "
		f"across {default_skill_count} skills; "
		f"{CODEX_LIST_BUDGET - skill_list_size} tokens remain in Codex's full "
		f"{CODEX_LIST_BUDGET}-token budget."
	)
	if skill_list_size > SKILL_LIST_LIMIT:
		problems.append(
			f"Default skill list exceeds the recorded limit by "
			f"{skill_list_size - SKILL_LIST_LIMIT} estimated tokens."
		)

	for problem in problems:
		print(problem, file=sys.stderr)
	return 1 if problems else 0


def read_default_off_collections() -> set[str]:
	"""Read the skill collections a fresh setup leaves out, so the size check counts what gets installed.

	Returns:
		The names of the collections setup does not install by default.

	Raises:
		ValueError: scripts/setup.sh no longer defines default_off_collections.
	"""
	# The setup script that owns the default-off collection list.
	setup_source = (REPO_DIR / "scripts" / "setup.sh").read_text()
	# The shell array contents from the setup script.
	match = re.search(r"(?m)^\s*default_off_collections=\(([^)]*)\)", setup_source)
	if match is None:
		raise ValueError("Cannot read default_off_collections from scripts/setup.sh")
	return set(shlex.split(match.group(1)))


def read_metadata(skill_file: Path) -> tuple[str, str]:
	"""Read the fields Codex shows for a canonical skill.

	Args:
		skill_file: The canonical SKILL.md to read.

	Returns:
		The skill name and description.

	Raises:
		ValueError: The front matter is missing or incomplete.
	"""
	# Lines in the skill's source file.
	lines = skill_file.read_text().splitlines()
	if not lines or lines[0] != "---":
		raise ValueError(f"Missing front matter: {skill_file}")

	# The position of the closing front matter marker in lines.
	try:
		end = lines.index("---", 1)
	except ValueError as error:
		raise ValueError(f"Missing closing front matter marker: {skill_file}") from error
	# Skill name used in Codex's listing and installed path.
	name = ""
	# Lines that form the description shown by Codex.
	description_lines: list[str] = []
	# Whether an indented description block is being read.
	in_description = False
	for line in lines[1:end]:
		if line.startswith("name:"):
			name = line.removeprefix("name:").strip()
			in_description = False
		elif line.startswith("description:"):
			# The text after the key: the whole description, or a block marker such as ">".
			value = line.removeprefix("description:").strip()
			in_description = value.startswith((">", "|"))
			if not in_description:
				description_lines = [value]
		elif in_description:
			if line.startswith(" ") or not line:
				description_lines.append(line.strip())
			else:
				in_description = False

	if not name or not description_lines:
		raise ValueError(f"Missing name or description: {skill_file}")
	return name, " ".join(description_lines)


def check_links(skill_file: Path) -> list[str]:
	"""Find broken relative links in a skill, and reference files that none of its files link to.

	Skills copied from upstream (those with a SOURCE.md) skip the unlinked-file check, because
	their layout follows the upstream project. Links inside code examples are ignored.

	Args:
		skill_file: The canonical SKILL.md whose links and references are checked.

	Returns:
		The broken-link and orphaned-reference findings.
	"""
	# The skill folder that owns these references.
	skill_dir = skill_file.parent
	# Reference files reached by a link in this skill's own files.
	linked_references: set[Path] = set()
	# Findings for this skill.
	problems: list[str] = []
	# Reference files included in the scan alongside the main skill file.
	reference_files = sorted(path for path in (skill_dir / "references").rglob("*") if path.is_file())

	for source in [skill_file, *reference_files]:
		if source.suffix.lower() not in {".md", ".markdown"}:
			continue

		# The file's text with code examples removed, so only real links remain.
		content = FENCED_CODE_PATTERN.sub("", source.read_text())
		content = INLINE_CODE_PATTERN.sub("", content)
		for match in LINK_PATTERN.finditer(content):
			# The link address without Markdown's optional angle brackets.
			address = match.group(1).strip("<>")
			# The address split into parts, so web links and absolute paths can be skipped.
			parts = urlsplit(address)
			if parts.scheme or parts.netloc or not parts.path or parts.path.startswith("/"):
				continue

			# The actual file named by the relative link.
			target = (source.parent / unquote(parts.path)).resolve()
			if not target.is_file():
				problems.append(f"Broken skill link: {source.relative_to(REPO_DIR)} -> {address}")
				continue
			if target in reference_files:
				linked_references.add(target)

	if not (skill_dir / "SOURCE.md").is_file():
		for reference in reference_files:
			if reference not in linked_references:
				problems.append(f"Orphaned skill reference: {reference.relative_to(REPO_DIR)}")
	return problems


def check_retired_names() -> list[str]:
	"""Find retired skill names still mentioned in maintained source files.

	Names that are also package names are only reported outside code, where they would refer to the skill.

	Returns:
		One finding for each retired name in each file that still mentions it.
	"""
	# Findings for names that should have disappeared from source.
	problems: list[str] = []
	if not RETIRED_SKILL_NAMES:
		return problems

	# Directories and root files that must use the merged skill names instead.
	source_paths = ("src", "skills", "teams", "scripts", "docs", "README.md", "AGENTS.md")
	for source_path in source_paths:
		# The directory or root file to search.
		root = REPO_DIR / source_path
		for source in (root,) if root.is_file() else root.rglob("*"):
			if not source.is_file():
				continue
			# The retired-name list is maintained here, so this file is not a source to scan.
			if source == REPO_DIR / "scripts" / "validate" / "check-skill-list.sh":
				continue
			try:
				# The file's text, searched for retired names.
				content = source.read_text()
			except UnicodeDecodeError:
				continue

			for retired_name in RETIRED_SKILL_NAMES:
				# The file's text with code removed when the name is also a package, since code there means the package.
				text_to_check = content
				if retired_name in RETIRED_NAMES_ALSO_PACKAGES:
					text_to_check = FENCED_CODE_PATTERN.sub("", text_to_check)
					text_to_check = INLINE_CODE_PATTERN.sub("", text_to_check)

				# Match the complete skill name, not part of another name.
				pattern = rf"(?<![\w-]){re.escape(retired_name)}(?![\w-])"
				if re.search(pattern, text_to_check):
					problems.append(f"Retired skill name {retired_name}: {source.relative_to(REPO_DIR)}")
	return problems


if __name__ == "__main__":
	raise SystemExit(main())
PY
