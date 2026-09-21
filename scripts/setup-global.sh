#!/usr/bin/env bash
# Installs global agent configuration into Claude and Codex via symlinks.

set -euo pipefail

# Resolved at startup so aliases can call this script from any directory.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$REPO_DIR/scripts/lib/setup-links.sh"

usage() {
	printf 'Usage: %s [--claude|--codex|--both] [--claude-dir <path>] [--codex-dir <path>] [--refresh] [--skip-external]\n' "$(basename "$0")"
}

setup_claude() {
	cli_section "Claude global setup ($(display_path "$CLAUDE_DIR"))"

	cli_group_begin "Claude directories"
	ensure_container_dir "$CLAUDE_DIR" "$(display_path "$CLAUDE_DIR")"
	ensure_container_dir "$CLAUDE_DIR/skills" "skills"
	ensure_container_dir "$CLAUDE_DIR/hooks" "hooks"
	ensure_container_dir "$CLAUDE_DIR/commands" "commands"
	cli_group_end

	cli_group_begin "Claude command-line tools"
	ensure_friction
	cli_group_end

	cli_group_begin "Claude files"
	link_path "$REPO_DIR/dist/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
	link_path "$REPO_DIR/dist/claude/settings.json" "$CLAUDE_DIR/settings.json" "settings.json"
	link_path "$REPO_DIR/dist/claude/.mcp.json" "$CLAUDE_DIR/.mcp.json" ".mcp.json"
	link_path "$REPO_DIR/dist/claude/statusline.sh" "$CLAUDE_DIR/statusline.sh" "statusline.sh"
	cli_group_end

	cli_group_begin "Claude skills"
	prune_stale_repo_links "$CLAUDE_DIR/skills" "$REPO_DIR" "skills"
	link_skills "$CLAUDE_DIR/skills"
	cli_group_end

	cli_group_begin "Claude hooks"
	prune_stale_repo_links "$CLAUDE_DIR/hooks" "$REPO_DIR/dist/claude/hooks" "hooks"
	local hook
	for hook in "$REPO_DIR"/dist/claude/hooks/*; do
		[ -f "$hook" ] || continue
		link_path "$hook" "$CLAUDE_DIR/hooks/$(basename "$hook")" "hooks/$(basename "$hook")"
	done
	cli_group_end

	cli_group_begin "Claude commands"
	local command
	for command in "$REPO_DIR"/dist/claude/commands/*; do
		[ -f "$command" ] || continue
		link_path "$command" "$CLAUDE_DIR/commands/$(basename "$command")" "commands/$(basename "$command")"
	done
	cli_group_end
}

# Ensures the friction command is available for the central Claude hook.
ensure_friction() {
	if command -v friction >/dev/null 2>&1; then
		cli_group_status muted "friction" "globally installed"
		return
	fi

	if ! command -v uv >/dev/null 2>&1; then
		cli_group_status failed "friction" "missing and uv is not installed"
		return 1
	fi

	cli_group_status warning "friction" "installing globally"
	if ! uv tool install --from ~/Dev/Repositories/Packages/dev-tools/packages/friction friction >/dev/null; then
		cli_group_status failed "friction" "global installation failed"
		return 1
	fi

	if ! command -v friction >/dev/null 2>&1; then
		cli_group_status failed "friction" "installation did not expose friction"
		return 1
	fi

	cli_group_status success "friction" "installed globally"
}

setup_codex() {
	cli_section "Codex global setup ($(display_path "$CODEX_DIR"))"

	cli_group_begin "Codex directories"
	ensure_container_dir "$HOME/.agents" "~/.agents"
	ensure_container_dir "$HOME/.agents/skills" "~/.agents/skills"
	ensure_container_dir "$CODEX_DIR" "$(display_path "$CODEX_DIR")"
	ensure_container_dir "$CODEX_DIR/hooks" "hooks"
	cli_group_end

	cli_group_begin "Codex files"
	link_path "$REPO_DIR/dist/codex/AGENTS.md" "$HOME/.agents/AGENTS.md" "AGENTS.md"
	link_path "$REPO_DIR/dist/codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" "Codex AGENTS.md"
	link_path "$REPO_DIR/dist/codex/hooks.json" "$CODEX_DIR/hooks.json" "Codex hooks"
	prune_stale_repo_links "$CODEX_DIR/hooks" "$REPO_DIR/dist/codex/hooks" "hooks"
	local hook
	for hook in "$REPO_DIR"/dist/codex/hooks/*; do
		[ -f "$hook" ] || continue
		link_path "$hook" "$CODEX_DIR/hooks/$(basename "$hook")" "hooks/$(basename "$hook")"
	done
	ensure_codex_config
	cli_group_end

	cli_group_begin "Codex skills"
	prune_stale_repo_links "$HOME/.agents/skills" "$REPO_DIR" "skills"
	prune_stale_repo_links "$CODEX_DIR/skills" "$REPO_DIR" "legacy skills" "1"
	link_skills "$HOME/.agents/skills"
	cli_group_end
}

# Prints one repository-managed Codex configuration value.
#
# @param  {string}  section
#     TOML section name, or root for a root-level setting.
# @param  {string}  key
#     Setting name to read.
codex_config_value() {
	local section="$1" key="$2"

	awk -v section="$section" -v key="$key" '
		BEGIN { in_section = section == "root" }
		/^\[/ {
			if (section == "root") {
				exit
			}

			in_section = $0 == "[" section "]"
			next
		}
		in_section && $0 ~ "^" key "[[:space:]]*=" {
			sub("^[^=]*=[[:space:]]*", "")
			print
			exit
		}
	' "$REPO_DIR/src/adapters/codex/config.base.toml"
}

# Prints one repository-managed Codex TOML section.
#
# @param  {string}  section
#     TOML section name to read.
codex_config_section() {
	local section="$1"

	sed "s|{{HOME}}|$HOME|g" "$REPO_DIR/src/adapters/codex/config.base.toml" | awk -v section="$section" '
		$0 == "[" section "]" { in_section = 1 }
		/^\[/ && in_section && $0 != "[" section "]" { exit }
		in_section { print }
	'
}

# Ensures the Codex TUI uses the managed settings while preserving unrelated
# TUI preferences.
#
# @param  {string}  config
#     Codex config file to update.
ensure_codex_tui_settings() {
	local config="$1"
	local alternate_screen status_line status_line_use_colors temp

	alternate_screen=$(codex_config_value "tui" "alternate_screen")
	status_line=$(codex_config_value "tui" "status_line")
	status_line_use_colors=$(codex_config_value "tui" "status_line_use_colors")

	temp=$(mktemp)
	awk '
		BEGIN {
			in_tui = 0
			tui_found = 0
		}
		/^\[tui\]$/ {
			print
			print "alternate_screen = " alternate_screen
			print "status_line = " status_line
			print "status_line_use_colors = " status_line_use_colors
			in_tui = 1
			tui_found = 1
			next
		}
		/^\[/ { in_tui = 0 }
		in_tui && /^(alternate_screen|status_line(_use_colors)?)[[:space:]]*=/ { next }
		{ print }
		END {
			if (!tui_found) {
				print ""
				print "[tui]"
				print "alternate_screen = " alternate_screen
				print "status_line = " status_line
				print "status_line_use_colors = " status_line_use_colors
			}
		}
	' alternate_screen="$alternate_screen" status_line="$status_line" status_line_use_colors="$status_line_use_colors" "$config" > "$temp"
	mv "$temp" "$config"
}

# Sets the root-level Codex defaults while preserving unrelated configuration.
#
# @param  {string}  source
#     Existing Codex config file to read.
# @param  {string}  destination
#     Temporary file that receives the updated configuration.
ensure_codex_defaults() {
	local source="$1" destination="$2"
	local approval_policy sandbox_mode

	approval_policy=$(codex_config_value "root" "approval_policy")
	sandbox_mode=$(codex_config_value "root" "sandbox_mode")

	awk -v approval_policy="$approval_policy" -v sandbox_mode="$sandbox_mode" '
		function print_defaults() {
			print "approval_policy = " approval_policy
			print "sandbox_mode = " sandbox_mode
		}
		BEGIN {
			in_root = 1
			defaults_written = 0
		}
		/^\[/ {
			if (in_root) {
				print_defaults()
				defaults_written = 1
				in_root = 0
			}
			print
			next
		}
		in_root && /^(approval_policy|sandbox_mode)[[:space:]]*=/ { next }
		{ print }
		END {
			if (!defaults_written) {
				print_defaults()
			}
		}
	' "$source" > "$destination"
}

# Ensures the workspace-write sandbox has the managed settings while preserving
# user-owned settings and writable roots.
#
# @param  {string}  config
#     Codex configuration file to update.
ensure_codex_workspace_settings() {
	local config="$1"
	local network_access writable_roots temp
	local -a writable_root_list=()
	local rest item

	network_access=$(codex_config_value "sandbox_workspace_write" "network_access")
	writable_roots=$(codex_config_value "sandbox_workspace_write" "writable_roots")
	writable_roots=${writable_roots//\{\{HOME\}\}/$HOME}

	rest="$writable_roots"
	while [[ "$rest" == *'"'*'"'* ]]; do
		rest=${rest#*\"}
		item=${rest%%\"*}
		writable_root_list+=("$item")
		rest=${rest#*\"}
	done

	temp=$(mktemp)
	awk -v network_access="$network_access" -v writable_roots="$writable_roots" -v roots_list="$(printf '%s|' "${writable_root_list[@]}")" '
		function finish_workspace_write() {
			if (in_workspace_write && !writable_roots_found) {
				print "writable_roots = " writable_roots
			}
		}
		BEGIN {
			in_workspace_write = 0
			workspace_write_found = 0
			writable_roots_found = 0
		}
		/^\[sandbox_workspace_write\]$/ {
			finish_workspace_write()
			print
			print "network_access = " network_access
			in_workspace_write = 1
			workspace_write_found = 1
			next
		}
		/^\[/ {
			finish_workspace_write()
			in_workspace_write = 0
		}
		in_workspace_write && /^network_access[[:space:]]*=/ { next }
		in_workspace_write && /^writable_roots[[:space:]]*=/ {
			writable_roots_found = 1
			n = split(roots_list, roots, "|")
			for (i = 1; i <= n; i++) {
				root = roots[i]
				if (root != "" && index($0, "\"" root "\"") == 0) {
					sub(/\][[:space:]]*$/, ", \"" root "\"]")
				}
			}
			print
			next
		}
		{ print }
		END {
			finish_workspace_write()
			if (!workspace_write_found) {
				print ""
				print "[sandbox_workspace_write]"
				print "network_access = " network_access
				print "writable_roots = " writable_roots
			}
		}
	' "$config" > "$temp"
	mv "$temp" "$config"
}

# Removes inline Codex hook definitions while preserving user configuration
# and Codex-managed hook trust state. Hooks are defined in hooks.json.
#
# @param  {string}  source
#     Existing Codex config file to read.
# @param  {string}  destination
#     Temporary file that receives the configuration without inline hooks.
remove_inline_codex_hooks() {
	local source="$1" destination="$2"

	awk '
		/^\[\[hooks\./ { skip = 1; next }
		/^\[hooks\.state/ { skip = 0 }
		/^\[/ && skip { skip = 0 }
		!skip { print }
	' "$source" > "$destination"
}

# Ensures $CODEX_DIR/config.toml contains the managed defaults, MCP server
# entries, hooks feature flag, and TUI status line. Legacy inline hooks are
# removed so Codex uses the managed hooks.json file.
ensure_codex_config() {
	local config="$CODEX_DIR/config.toml"
	local defaults_temp temp

	defaults_temp=$(mktemp)
	temp=$(mktemp)
	touch "$config"
	ensure_codex_defaults "$config" "$defaults_temp"

	# Strip managed MCP server sections before re-appending them,
	# so re-running setup never creates duplicate entries.
	awk '
		/^\[mcp_servers\.codebase-memory-mcp(\.|\])/{ skip = 1; next }
		/^\[mcp_servers\.serena(\.|\])/{ skip = 1; next }
		/^\[mcp_servers\.mdn(\.|\])/{ skip = 1; next }
		/^\[/{ skip = 0 }
		!skip { print }
	' "$defaults_temp" > "$temp"
	rm "$defaults_temp"

	# Re-add repository-managed MCP server configuration.
	for section in "mcp_servers.codebase-memory-mcp" "mcp_servers.serena" "mcp_servers.mdn"; do
		printf '\n' >> "$temp"
		codex_config_section "$section" >> "$temp"
	done
	ensure_codex_workspace_settings "$temp"
	ensure_codex_tui_settings "$temp"

	local hooks_temp
	hooks_temp=$(mktemp)
	remove_inline_codex_hooks "$temp" "$hooks_temp"
	mv "$hooks_temp" "$temp"

	local hooks_enabled
	hooks_enabled=$(codex_config_value "features" "hooks")

	# Migrate the deprecated codex_hooks key to hooks, and ensure the hooks
	# feature flag is present in [features].
	if grep -q '^codex_hooks' "$temp"; then
		local temp2
		temp2=$(mktemp)
		sed "s/^codex_hooks = /hooks = $hooks_enabled/" "$temp" > "$temp2"
		mv "$temp2" "$temp"
	elif ! grep -q '^\[features\]' "$temp"; then
		printf '\n[features]\nhooks = %s\n' "$hooks_enabled" >> "$temp"
	elif ! grep -q '^hooks' "$temp"; then
		local temp2
		temp2=$(mktemp)
		awk -v hooks_enabled="$hooks_enabled" '/^\[features\]/{print; print "hooks = " hooks_enabled; next} 1' "$temp" > "$temp2"
		mv "$temp2" "$temp"
	fi

	if cmp -s "$config" "$temp"; then
		rm "$temp"
		cli_group_status muted "Codex config" "already configured"
		return
	fi

	local backup
	backup=$(backup_path "$config")
	mv "$temp" "$config"
	cli_group_status success "configured Codex MCP servers and hooks" "backup at $(display_path "$backup")"
}

# Configures git to use src/hooks/git/ as the hook directory for this repo.
# This installs the pre-push hook without touching ~/.git/hooks directly.
configure_git_hooks() {
	cli_section "Git hooks"

	if ! git -C "$REPO_DIR" config core.hooksPath src/hooks/git &>/dev/null; then
		cli_status warning "Could not set core.hooksPath" "not a git repo?"
		return
	fi

	cli_status success "git hooks path set" "src/hooks/git/"
}

prompt_target() {
	printf 'Which agent(s)? [1] Claude  [2] Codex  [3] Both: '
	read -r choice

	case "$choice" in
		1) printf 'claude' ;;
		2) printf 'codex' ;;
		3) printf 'both' ;;
		*) printf 'Invalid choice.\n' >&2; exit 1 ;;
	esac
}

target=""
refresh=false
sync_external=true
CLAUDE_DIR="$HOME/.claude"  # Overridable so a second account can install alongside the default one.
CODEX_DIR="$HOME/.codex"    # Overridable so a second account can install alongside the default one.

while [ $# -gt 0 ]; do
	case "$1" in
		--claude)        target="claude" ;;
		--codex)         target="codex" ;;
		--both)          target="both" ;;
		--claude-dir)    CLAUDE_DIR="$2"; shift ;;
		--codex-dir)     CODEX_DIR="$2"; shift ;;
		--refresh)       refresh=true ;;
		--skip-external) sync_external=false ;;
		--help)          usage; exit 0 ;;
		*)               usage >&2; exit 1 ;;
	esac
	shift
done

if [ -z "$target" ]; then
	target=$(prompt_target)
fi

bash "$REPO_DIR/scripts/install-cli-style.sh"
source "$REPO_DIR/scripts/lib/cli-style-output.sh"

if [ "$refresh" = true ]; then
	if [ "$sync_external" = true ]; then
		if ! bash "$REPO_DIR/scripts/sync-external-skills.sh"; then
			cli_status warning "external skill sync failed" "continuing with existing local skills"
		fi
	fi

	bash "$REPO_DIR/scripts/sync.sh"
	bash "$REPO_DIR/scripts/validate.sh"
fi

case "$target" in
	claude) setup_claude ;;
	codex)  setup_codex ;;
	both)   setup_claude; setup_codex ;;
esac

configure_git_hooks

printf '\n'
cli_status success "Done."
