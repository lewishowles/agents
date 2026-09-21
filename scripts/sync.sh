#!/usr/bin/env bash
# Generates all dist/ output from source files.
#
# Build order:
#   1. Docs tables generated from canonical skill and hook files (build-docs.py)
#   2. dist/claude/hooks/ (copied from src/hooks/claude/ source)
#   3. dist/claude/CLAUDE.md and dist/codex/AGENTS.md (assembled from src/rules/)
#   4. dist/claude/settings.json (build-settings.py)
#   5. Validation (validate.sh)

set -euo pipefail

# macOS ships bash 3.2; several validators need bash 4+ (declare -A, mapfile).
# Re-exec under homebrew bash if the current interpreter is too old.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
	export PATH="/opt/homebrew/bin:$PATH"
	if [ -x /opt/homebrew/bin/bash ]; then
		exec /opt/homebrew/bin/bash "$0" "$@"
	else
		exec "$(command -v bash)" "$0" "$@"
	fi
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$REPO_DIR/scripts/lib/colours.sh"
source "$REPO_DIR/scripts/lib/cli-style-output.sh"
source "$REPO_DIR/scripts/lib/dist-targets.sh"

# Clears dist/claude/hooks/ and repopulates it from the hook source dirs.
# Clearing first prevents stale files from accumulating when hooks are renamed.
copy_hooks() {
	mkdir -p "$REPO_DIR/dist/claude/hooks"
	find "$REPO_DIR/dist/claude/hooks" -maxdepth 1 -type f -delete
	mkdir -p "$REPO_DIR/dist/codex/hooks"
	find "$REPO_DIR/dist/codex/hooks" -maxdepth 1 -type f -delete

	local hook_dir script
	for hook_dir in "$REPO_DIR/src/hooks/claude/"/*/; do
		[ -d "$hook_dir" ] || continue
		for script in "$hook_dir"*; do
			[ -f "$script" ] || continue
			[[ "$(basename "$script")" == "hook.json" ]] && continue
			cp "$script" "$REPO_DIR/dist/claude/hooks/$(basename "$script")"
		done
	done

	local shared_file
	for shared_file in "$REPO_DIR/src/hooks/shared/"*.sh "$REPO_DIR/src/hooks/shared/"*.md; do
		[ -f "$shared_file" ] || continue
		cp "$shared_file" "$REPO_DIR/dist/claude/hooks/$(basename "$shared_file")"
		cp "$shared_file" "$REPO_DIR/dist/codex/hooks/$(basename "$shared_file")"
	done
}

mkdir -p "$REPO_DIR/dist/claude" "$REPO_DIR/dist/codex"

cli_section "Generated outputs" "Build dist files and manifests"

python3 "$REPO_DIR/scripts/build/build-docs.py" >/dev/null
copy_hooks
write_target "$CLAUDE_TARGET" "${CLAUDE_PARTS[@]}"
write_target "$CODEX_TARGET" "${CODEX_PARTS[@]}"
python3 "$REPO_DIR/scripts/build/build-settings.py" >/dev/null

# Copy static config files from adapters to dist.
cp "$REPO_DIR/src/adapters/claude/mcp.json" "$REPO_DIR/dist/claude/.mcp.json"
cp "$REPO_DIR/src/adapters/claude/statusline.sh" "$REPO_DIR/dist/claude/statusline.sh"
chmod +x "$REPO_DIR/dist/claude/statusline.sh"
if [[ -e "$REPO_DIR/dist/codex/hooks.toml" ]] || [[ -L "$REPO_DIR/dist/codex/hooks.toml" ]]; then
	trash "$REPO_DIR/dist/codex/hooks.toml"
fi
python3 -m json.tool "$REPO_DIR/src/adapters/codex/hooks.json" >/dev/null
cp "$REPO_DIR/src/adapters/codex/hooks.json" "$REPO_DIR/dist/codex/hooks.json"

cli_status success "synced" "dist/claude/CLAUDE.md"
cli_status success "synced" "dist/codex/AGENTS.md"
cli_status success "synced" "manifest-backed docs tables"
cli_status success "synced" "dist/claude/settings.json"
cli_status success "synced" "dist/codex/hooks.json"

bash "$REPO_DIR/scripts/validate.sh"
