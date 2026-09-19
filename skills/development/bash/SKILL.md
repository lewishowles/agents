---
name: bash
description: >
  Use this skill when writing shell scripts, zsh functions, bash utilities, .env files, or config files. Apply even for short scripts or helper functions — covers bash patterns, minimal documentation style, and config file conventions.
filePatterns: ["*.sh"]
pathPatterns: []
---
# Bash and Python scripts

Standalone bash and Python scripts; keep both consistent.

## Shared conventions

- Tabs for indentation in all files, including Python
- Quote all variables and paths in bash
- Use `/path/to/directory` placeholders in examples, not user-specific paths

## Script-level comments

Every script opens with `#` purpose comment after shebang. For build scripts, include execution order or key constraints.

```bash
#!/usr/bin/env bash
# Generates all dist/ output from source files.
#
# Build order:
#   1. SKILL.md files (build-skill-mds.py)
#   2. Hook scripts copied to dist/claude/hooks/
#   3. Agent instruction files assembled from src/rules/
```

```python
#!/usr/bin/env python3
# Generate dist/claude/settings.json from src/adapters/claude/settings.base.json
# and src/hooks/claude/*/hook.json. The base file holds env, permissions, and
# skillOverrides; all hook entries are derived from manifests.
```

## Function comments

Every function: purpose comment + JSDoc-style `@param` lines. Use format `# @param  {type}  name`. Put description on indented next line, even brief ones. Add blank `#` before first `@param`.

```bash
# Moves a file to its backup location and prints the backup path.
# Backup paths are routed by prefix so each agent's backups stay separate.
#
# @param  {string}  path
#     The file or symlink to back up.
backup_path() {
	local path="$1"  # File or symlink to move to its backup location.
	…
}
```

```python
# Read skill.json and return the fields needed for index generation.
#
# @param  {Path}  skill_dir
#     The skill directory containing skill.json.
def load_manifest(skill_dir: Path) -> dict:
	…
```

Every function needs this documentation, including one-line functions and functions whose name or signature is clear.

## Variables

Every top-level and local variable needs a short purpose comment. Use a trailing `#` comment for a short declaration or a preceding `#` comment when it reads more clearly.

```bash
MANIFEST="$REPO_DIR/external-skills.json"  # List of skills to sync, with URLs and metadata.
```

```python
PM_GROUP = "project-management"  # Listed first in the global index so it appears near slash-command docs.
```

## No banner dividers

Do not use `# ---` or `# ===` dividers. Use blank lines and plain section comments.

```bash
# Collect all skill names for dependency resolution.
declare -A SKILL_NAMES
```

## Extract repeated logic

If pattern appears more than once, extract named function. Name after what it resolves, not how it works.

```bash
# Returns 0 if the value is in the allowed list, 1 otherwise.
# @param  {string}  value
#     The value to check.
# @param  {string}  ...
#     Allowed values passed as remaining arguments.
is_valid() {
	local value="$1"  # Value to compare with the allowed values.
	shift
	local allowed  # Current allowed value being compared.
	for allowed in "$@"; do
		[ "$value" = "$allowed" ] && return 0
	done
	return 1
}
```

## Inline scripts in heredocs

When bash embeds Python/awk inline, add comment explaining what it does and why inline if needed.

```bash
# Strips YAML frontmatter and writes the body to the output file.
strip_frontmatter "$temp_file" "$skill_dir/SKILL.body.md"
```

If logic is complex, wrap heredoc in named function so call site stays readable.

## Bash boilerplate

```bash
#!/usr/bin/env bash

set -euo pipefail

if ! command -v jq &>/dev/null; then
	printf 'This script requires jq. Install it with: brew install jq\n' >&2
	exit 1
fi

config_path="${1:-/path/to/config.json}"  # Configuration file to validate and read.

if [[ ! -f "$config_path" ]]; then
	printf 'Config file not found: %s\n' "$config_path" >&2
	exit 1
fi

jq -r '.name // "unknown"' "$config_path"
```

## Background processes in verification

Avoid a background process during ad-hoc verification unless the behaviour under test genuinely needs one. When one is required: capture its PID, install cleanup before the risky step, trap `EXIT`, `INT`, and `TERM`, kill descendants as well as the direct child, and `wait` for the terminated children so they are reaped. Cleanup must still run if an assertion fails, the check times out, it is interrupted, or the shell exits unexpectedly. Do not rely on closing the terminal, ending the agent session, or the parent tool process to clean up children.

## File existence checks

Use `[[ -f path ]]` or `[[ -d path ]]` with explicit branch, not `&&` chain. A `&&` exits silently on any failure (not just missing files), making it unreliable for existence checks.

```bash
# Correct
if [[ -f "$config_path" ]]; then
	…
fi

# Wrong — exits silently if any prior command fails
[ -f "$config_path" ] && do_something
```

Use the Read tool in preference to a shell check when the goal is to act on a file's contents.

## Config files

- Every variable or setting has a short purpose comment; no headers
- `.env`/`.conf` concise, scannable
- Config organised cleanly
