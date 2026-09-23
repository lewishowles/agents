#!/usr/bin/env bash
# Shared definition of how dist/claude/CLAUDE.md and dist/codex/AGENTS.md are
# assembled from src/rules/ fragments, and of the generated code-style rule in
# dist/claude/rules/. Sourced by scripts/sync.sh (real build),
# scripts/validate/check-dist-sync.sh (drift check against a temp rebuild), and
# scripts/validate/check-hook-sync.sh (code-style rule drift check).
# Requires REPO_DIR to already be set before sourcing.

CLAUDE_TARGET="$REPO_DIR/dist/claude/CLAUDE.md"
CODEX_TARGET="$REPO_DIR/dist/codex/AGENTS.md"

# Ordered fragment lists for each agent's composed output file.
CLAUDE_PARTS=(
	"$REPO_DIR/src/fragments/claude/header.md"
	"$REPO_DIR/src/rules/global-rules.md"
	"$REPO_DIR/src/fragments/claude/subagent-delegation.md"
	"$REPO_DIR/src/rules/identity.md"
	"$REPO_DIR/src/rules/skills-policy.md"
	"$REPO_DIR/src/rules/file-discovery.md"
)

CODEX_PARTS=(
	"$REPO_DIR/src/fragments/codex/header.md"
	"$REPO_DIR/src/rules/global-rules.md"
	"$REPO_DIR/src/rules/identity.md"
	"$REPO_DIR/src/rules/skills-policy.md"
	"$REPO_DIR/src/rules/file-discovery.md"
	"$REPO_DIR/src/fragments/codex/exec-environment.md"
)

# Concatenates ordered fragment files into a single target file, with a blank
# line separating each fragment so sections don't run together.
#
# @param  {string}  target
#     Output file path.
# @param  {string}  ...
#     Fragment file paths (remaining arguments), in order.
write_target() {
	local target="$1"
	shift

	: > "$target"

	local part
	local first=true

	for part in "$@"; do
		if [ "$first" = false ]; then
			printf '\n' >> "$target"
		fi

		cat "$part" >> "$target"
		first=false
	done
}

# Prints the Claude rule that tells sessions to load the code-style skill
# when they work with code files. The file list comes from the code-style
# entry in the skill trigger patterns, so the rule and the pre-edit hook
# cover the same files.
print_code_style_rule() {
	local patterns="$REPO_DIR/src/hooks/claude/skill-file-trigger/skill-file-trigger.patterns.json"  # Code file patterns shared with the pre-edit skill hook.

	printf '%s\n' '---' 'paths:'
	jq -r '."code-style".filePatterns[] | "  - \"**/" + . + "\""' "$patterns"
	printf '%s\n' '---' '' 'Load the code-style skill before planning or editing code in these files.'
}
