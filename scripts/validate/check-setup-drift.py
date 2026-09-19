#!/usr/bin/env python3
# Warn when project setup docs/templates drift from setup-project.sh behaviour.
# Always exits 0 — setup drift is advisory, not a hard validation failure.

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Files that define project setup behaviour.
SETUP_FILES = [
	REPO_ROOT / "scripts" / "setup-project.sh",
	REPO_ROOT / "scripts" / "lib" / "project-setup.sh",
]

# Project template files that should reference setup-produced paths.
TEMPLATE_FILES = [
	REPO_ROOT / "templates" / "claude" / "AGENTS.md.template",
	REPO_ROOT / "templates" / "codex" / "AGENTS.md.template",
	REPO_ROOT / "templates" / "shared" / "AGENTS.md.template",
]

# Flags that are implementation aliases rather than user-facing setup modes.
IGNORED_FLAGS = {
	"-h",
	"--help",
	"--force-capabilities",
	"--init-capabilities",
	"--write-capabilities",
}

# Known setup outputs/flags documented in prose rather than fenced examples.
IGNORED_DRIFT = {
	(
		"setup_flag_not_in_docs",
		"--force-workspace",
	),  # documented in prose, not fenced block
	(
		"setup_path_not_documented",
		".agent/scripts",
	),  # documented in prose as linked shared tools
	(
		"setup_path_not_documented",
		".agent/scripts/change-impact.py",
	),  # covered by .agent/scripts prose
	(
		"setup_path_not_documented",
		".agent/scripts/generated-file-guard.py",
	),  # covered by .agent/scripts prose
	(
		"setup_path_not_documented",
		".agent/scripts/markdown-claims.py",
	),  # covered by .agent/scripts prose
	(
		"setup_path_not_documented",
		".agent/scripts/repo-context.py",
	),  # covered by .agent/scripts prose
	(
		"setup_path_not_documented",
		".claude",
	),  # documented in prose through Claude support files
	(
		"setup_path_not_documented",
		".claude/.claudeignore",
	),  # documented in prose, not fenced block
}

RE_CODE_FENCE = re.compile(r"```([a-zA-Z0-9_-]*)\n(.*?)```", re.DOTALL)
RE_FLAG = re.compile(r"(?<![\w-])--[a-zA-Z0-9-]+|(?<![\w-])-h(?![\w-])")
RE_FUNCTION = re.compile(
	r"^([a-zA-Z_][a-zA-Z0-9_]*)\(\) \{\n(.*?)\n\}", re.MULTILINE | re.DOTALL
)
RE_PROJECT_PATH = re.compile(r'"\$PROJECT_DIR/([^"]+)"')
RE_INLINE_CODE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
RE_LOCAL_PATH = re.compile(
	r"(?<![\w/.-])(?:WORKSPACE\.md|AGENT_CAPABILITIES\.md|AGENTS\.md|\.agent/[^\s`'\"),]+|\.claude/[^\s`'\"),]+)"
)


@dataclass
class Issue:
	kind: str
	source: str
	item: str
	message: str


@dataclass
class SetupFacts:
	flags: set[str]
	paths: set[str]
	paths_by_flag: dict[str, set[str]]


def rel(path: Path) -> str:
	return str(path.relative_to(REPO_ROOT))


def read(path: Path) -> str:
	return path.read_text(encoding="utf-8")


def normalise_path(path: str) -> str:
	return path.strip().strip('"').strip("'").removeprefix("./").rstrip("/")


def extract_flags(text: str) -> set[str]:
	return set(RE_FLAG.findall(text)) - IGNORED_FLAGS


def function_bodies(text: str) -> dict[str, str]:
	return {match.group(1): match.group(2) for match in RE_FUNCTION.finditer(text)}


def project_paths_from_text(text: str) -> set[str]:
	paths = {normalise_path(match.group(1)) for match in RE_PROJECT_PATH.finditer(text)}
	paths.discard("AGENT_CAPABILITIES.md")

	if 'local target="$PROJECT_DIR/WORKSPACE.md"' in text:
		paths.add("WORKSPACE.md")

	return paths


def called_functions(body: str, known_functions: set[str]) -> set[str]:
	calls = set()
	for name in known_functions:
		if re.search(rf"\b{name}\b", body):
			calls.add(name)
	return calls


def expand_function_paths(
	name: str,
	bodies: dict[str, str],
	seen: set[str] | None = None,
) -> set[str]:
	if seen is None:
		seen = set()

	if name in seen or name not in bodies:
		return set()

	seen.add(name)
	body = bodies[name]
	paths = project_paths_from_text(body)

	for called in called_functions(body, set(bodies)):
		if called != name:
			paths.update(expand_function_paths(called, bodies, seen))

	return paths


def parse_setup() -> SetupFacts:
	setup_text = read(SETUP_FILES[0])
	text = "\n".join([setup_text, *(read(path) for path in SETUP_FILES[1:])])
	bodies = function_bodies(text)

	paths_by_flag = {
		"--claude": expand_function_paths("setup_claude", bodies),
		"--codex": expand_function_paths("setup_codex", bodies),
		"--both": expand_function_paths("setup_both", bodies),
		"--init-workspace": {"WORKSPACE.md"},
		"--write-workspace": {"WORKSPACE.md"},
		"--force-workspace": {"WORKSPACE.md"},
	}

	paths = set()
	for flag_paths in paths_by_flag.values():
		paths.update(flag_paths)

	return SetupFacts(
		flags=extract_flags(setup_text),
		paths=paths,
		paths_by_flag=paths_by_flag,
	)


def project_setup_section(text: str) -> str:
	marker = "\n## Project setup\n"
	if marker not in text:
		return text
	return text.split(marker, 1)[1]


def shell_fenced_blocks(text: str) -> list[str]:
	blocks = []
	for language, body in RE_CODE_FENCE.findall(text):
		if language.lower() in {"bash", "sh", "shell", "zsh"}:
			blocks.append(body)
	return blocks


def command_destination_paths(line: str) -> set[str]:
	parts = line.strip().split()
	if not parts:
		return set()

	command = parts[0]
	if command == "cp" and len(parts) >= 3:
		return {normalise_path(parts[-1])}
	if command == "mkdir" and "-p" in parts and len(parts) >= 3:
		return {normalise_path(parts[-1])}

	return set()


def parse_docs() -> tuple[set[str], set[str], list[tuple[str, set[str], set[str]]]]:
	path = REPO_ROOT / "docs" / "setup.md"
	blocks = shell_fenced_blocks(project_setup_section(read(path)))
	flags = set()
	paths = set()
	block_facts = []

	for index, block in enumerate(blocks, start=1):
		block_flags = extract_flags(block)
		block_paths = set()

		for line in block.splitlines():
			block_paths.update(command_destination_paths(line))

		flags.update(block_flags)
		paths.update(block_paths)
		block_facts.append(
			(f"{rel(path)} fenced block {index}", block_flags, block_paths)
		)

	return flags, paths, block_facts


def extract_template_paths(text: str) -> set[str]:
	paths = set()

	for code in RE_INLINE_CODE.findall(text):
		paths.update(
			normalise_path(match.group(0)) for match in RE_LOCAL_PATH.finditer(code)
		)

	paths.update(
		normalise_path(match.group(0)) for match in RE_LOCAL_PATH.finditer(text)
	)

	return paths


def parse_templates() -> tuple[set[str], dict[str, set[str]]]:
	all_paths = set()
	paths_by_file = {}

	for path in TEMPLATE_FILES:
		paths = extract_template_paths(read(path))
		paths_by_file[rel(path)] = paths
		all_paths.update(paths)

	return all_paths, paths_by_file


def add_missing_issues(
	issues: list[Issue],
	kind: str,
	source: str,
	missing_items: set[str],
	message_template: str,
) -> None:
	for item in sorted(missing_items):
		if (kind, item) in IGNORED_DRIFT:
			continue

		issues.append(
			Issue(
				kind=kind,
				source=source,
				item=item,
				message=message_template.format(item=item),
			)
		)


def find_issues(
	setup: SetupFacts,
	doc_flags: set[str],
	doc_paths: set[str],
	doc_blocks: list[tuple[str, set[str], set[str]]],
	template_paths: set[str],
) -> list[Issue]:
	issues = []
	reference_paths = doc_paths | template_paths

	add_missing_issues(
		issues,
		"doc_flag_not_in_setup",
		"docs/setup.md",
		doc_flags - setup.flags,
		"docs reference {item}, but setup-project.sh does not expose that flag",
	)
	add_missing_issues(
		issues,
		"setup_flag_not_in_docs",
		"scripts/setup-project.sh",
		setup.flags - doc_flags - IGNORED_FLAGS,
		"setup-project.sh exposes {item}, but docs/setup.md project setup examples do not mention it",
	)
	add_missing_issues(
		issues,
		"doc_path_not_produced",
		"docs/setup.md",
		doc_paths - setup.paths,
		"docs project setup examples reference {item}, but setup-project.sh does not produce it",
	)
	add_missing_issues(
		issues,
		"template_path_not_produced",
		"templates/*/AGENTS.md.template",
		template_paths - setup.paths,
		"templates reference {item}, but setup-project.sh does not produce it",
	)
	add_missing_issues(
		issues,
		"setup_path_not_documented",
		"scripts/setup-project.sh",
		setup.paths - reference_paths,
		"setup-project.sh produces {item}, but docs/templates do not mention it",
	)

	for source, flags, paths in doc_blocks:
		for flag in sorted(flags & setup.paths_by_flag.keys()):
			missing = paths - setup.paths_by_flag[flag]
			add_missing_issues(
				issues,
				"doc_block_flag_path_mismatch",
				source,
				missing,
				f"docs use {flag} in same setup block as {{item}}, but that flag only produces "
				+ ", ".join(sorted(setup.paths_by_flag[flag])),
			)

	return issues


def print_issues(issues: list[Issue]) -> None:
	for issue in issues:
		print(f"  {issue.source}: {issue.message}")

	if issues:
		print(
			f"\n  {len(issues)} setup drift warning(s) — review docs/templates against setup-project.sh"
		)


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--json", action="store_true", help="Output findings as JSON")
	args = parser.parse_args()

	setup = parse_setup()
	doc_flags, doc_paths, doc_blocks = parse_docs()
	template_paths, _paths_by_file = parse_templates()
	issues = find_issues(setup, doc_flags, doc_paths, doc_blocks, template_paths)
	checked = [
		rel(path)
		for path in [*SETUP_FILES, REPO_ROOT / "docs" / "setup.md", *TEMPLATE_FILES]
	]

	if args.json:
		print(
			json.dumps(
				{"issues": [asdict(issue) for issue in issues], "checked": checked},
				indent=2,
			)
		)
	else:
		print_issues(issues)


if __name__ == "__main__":
	main()
