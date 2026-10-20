#!/usr/bin/env bash
# Shared definition of how dist/claude/CLAUDE.md and dist/codex/AGENTS.md are
# assembled from src/rules/ fragments. Sourced by scripts/sync.sh (real build)
# and scripts/validate/check-dist-sync.sh (drift check against a temp rebuild).
# Requires REPO_DIR to already be set before sourcing.

# The output path for the composed Claude rules.
CLAUDE_TARGET="$REPO_DIR/dist/claude/CLAUDE.md"
# The output path for the composed Codex rules.
CODEX_TARGET="$REPO_DIR/dist/codex/AGENTS.md"

# The source fragments for the composed Claude rules, in output order.
CLAUDE_PARTS=(
	"$REPO_DIR/src/fragments/claude/header.md"
	"$REPO_DIR/src/rules/global-rules.md"
	"$REPO_DIR/src/rules/identity.md"
	"$REPO_DIR/src/rules/skills-policy.md"
	"$REPO_DIR/src/rules/file-discovery.md"
)

# The source fragments for the composed Codex rules, in output order.
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
	# The output file that the rule fragments are written to.
	local target="$1"
	shift

	: > "$target"

	local part
	# Whether the next fragment is the first in the output file.
	local first=true

	for part in "$@"; do
		if [ "$first" = false ]; then
			printf '\n' >> "$target"
		fi

		cat "$part" >> "$target"
		first=false
	done
}
