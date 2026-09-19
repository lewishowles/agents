#!/usr/bin/env python3
# Generate runtime skill directories for Claude and Codex.
#
# Sources per skill:
#   skill.json    — metadata (name, description, dependencies, capabilities)
#   SKILL.body.md — instructional content (the part Claude actually reads)
#
# Output per skill:
#   dist/skills/<name>/SKILL.md — generated frontmatter and instructional body
#   dist/skills/<name>/*        — copied runtime references and supporting files
#
# Skill discovery supports two layouts:
#   src/skills/<name>/           — flat skill
#   src/skills/<group>/<name>/   — grouped skill (e.g. src/skills/vue/vue-pinia/)

import json
import shutil
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent.parent
SKILLS_DIR = REPO_DIR / "src" / "skills"
RULES_DIR = REPO_DIR / "src" / "rules"
DIST_SKILLS_DIR = REPO_DIR / "dist" / "skills"

# The global-rules skill has no authored SKILL.body.md — its body is composed
# directly from src/rules/ fragments so it can never drift from the source rules.
GLOBAL_RULES_SKILL_NAME = "global-rules"
GLOBAL_RULES_FRAGMENTS = [
	"global-rules.md",
	"identity.md",
	"skills-policy.md",
	"file-discovery.md",
]

GENERATED_HEADER = "# Generated — edit skill.json and SKILL.body.md instead."
# skill.json is copied to dist so the file-trigger hook can read
# capabilities, filePatterns, and pathPatterns at runtime.
SOURCE_FILENAMES = {"SKILL.body.md", "SKILL.md", "SYNC.md"}


# Return all skill directories, sorted alphabetically at each level.
# Handles both flat (src/skills/<name>/) and grouped (src/skills/<group>/<name>/) layouts.
def discover_skill_dirs() -> list[Path]:
	dirs = []
	for d in sorted(SKILLS_DIR.iterdir()):
		if not d.is_dir():
			continue
		if (d / "skill.json").exists():
			dirs.append(d)
		else:
			for sub in sorted(d.iterdir()):
				if sub.is_dir() and (sub / "skill.json").exists():
					dirs.append(sub)
	return dirs


# src/rules/global-rules.md nests its subsections under a "## General configuration"
# wrapper heading. Drop that wrapper and promote its direct ### children to ##
# so the skill body reads as flat top-level sections, matching every other
# src/rules/*.md fragment. Headings past the wrapper's own section (e.g. "###
# Subagent delegation" under "## Working across sessions") are left alone.
def promote_general_configuration(text: str) -> str:
	lines = text.splitlines()
	assert lines[0] == "## General configuration"
	lines = lines[1:]
	while lines and lines[0] == "":
		lines.pop(0)

	first_top_level = next(
		(i for i, line in enumerate(lines) if line.startswith("## ")), len(lines)
	)
	for i in range(first_top_level):
		if lines[i].startswith("### "):
			lines[i] = "## " + lines[i][len("### ") :]

	return "\n".join(lines)


# Compose the global-rules skill body directly from src/rules/ fragments, so the
# skill can never drift from the source rules the way a hand-maintained copy could.
def build_global_rules_body() -> str:
	parts = ["# Global rules"]
	for fragment in GLOBAL_RULES_FRAGMENTS:
		text = (RULES_DIR / fragment).read_text().strip()
		if fragment == "global-rules.md":
			text = promote_general_configuration(text)
		parts.append(text)
	return "\n\n".join(parts) + "\n"


# Write a runtime skill directory from authored metadata, body, and support files.
#
# @param  {Path}  skill_dir
#     The authored skill directory.
def generate_skill_md(skill_dir: Path) -> None:
	manifest_file = skill_dir / "skill.json"
	manifest = json.loads(manifest_file.read_text())

	if manifest["name"] == GLOBAL_RULES_SKILL_NAME:
		body = build_global_rules_body()
	else:
		body = (skill_dir / "SKILL.body.md").read_text()

	output_dir = DIST_SKILLS_DIR / manifest["name"]
	output_file = output_dir / "SKILL.md"

	output_dir.mkdir(parents=True, exist_ok=True)

	parts = [
		"---",
		GENERATED_HEADER,
		f"name: {manifest['name']}",
	]

	display_name = manifest.get("title")
	if display_name:
		parts.append(f"displayName: {display_name}")

	parts.extend(
		[
			"description: >",
			f"  {manifest.get('description', '')}",
		]
	)

	do_not_use = manifest.get("do-not-use-when", [])
	if do_not_use:
		parts.append("do-not-use-when:")
		parts.extend(f"  - {item}" for item in do_not_use)

	deps = manifest.get("dependencies", [])
	if deps:
		parts.append("related-skills:")
		parts.extend(f"  - {dep}" for dep in deps)

	explicit_invocation_only = manifest.get("explicitInvocationOnly", False)
	if explicit_invocation_only:
		parts.append("disable-model-invocation: true")

	parts.append("---")
	parts.append("")

	output_file.write_text("\n".join(parts) + body)

	# Codex has no equivalent frontmatter field — it reads a sibling policy
	# file instead of the SKILL.md frontmatter Claude uses.
	targets = manifest.get("targets")
	codex_enabled = targets is None or "codex" in targets
	if explicit_invocation_only and codex_enabled:
		agents_dir = output_dir / "agents"
		agents_dir.mkdir(parents=True, exist_ok=True)
		(agents_dir / "openai.yaml").write_text(
			"policy:\n  allow_implicit_invocation: false\n"
		)

	for source in skill_dir.iterdir():
		if source.name in SOURCE_FILENAMES:
			continue

		target = output_dir / source.name
		if source.is_dir():
			shutil.copytree(source, target)
		elif source.is_file():
			shutil.copy2(source, target)


def main() -> None:
	if DIST_SKILLS_DIR.exists():
		shutil.rmtree(DIST_SKILLS_DIR)
	DIST_SKILLS_DIR.mkdir(parents=True)

	skill_dirs = discover_skill_dirs()
	for skill_dir in skill_dirs:
		generate_skill_md(skill_dir)
	print(f"Generated {len(skill_dirs)} runtime skills in dist/skills/.")


if __name__ == "__main__":
	main()
