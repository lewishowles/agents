#!/usr/bin/env bash
# Installs global agent configuration into Claude and Codex via symlinks.

set -euo pipefail

# Resolved at startup so aliases can call this script from any directory.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$REPO_DIR/scripts/lib/setup-links.sh"

usage() {
	printf 'Usage: %s [--claude|--codex|--both] [--claude-dir <path>] [--codex-dir <path>] [--exclude <skill>[,<skill>...]] [--include <skill>[,<skill>...]] [--include-all] [--refresh] [--skip-external]\n' "$(basename "$0")"
}

# Parses a comma-separated skill list into the pending setup operations.
#
# @param  {string}  operation
#     Operation to apply to each listed skill.
# @param  {string}  value
#     Comma-separated skill names supplied on the command line.
parse_skill_list() {
	local operation="$1"  # Pending operation to apply to each skill name.
	local value="$2"  # Comma-separated skill names from the command line.
	local skill_name  # Skill name currently being parsed.
	local -a names=()  # Skill names parsed from the option value.

	IFS=',' read -r -a names <<< "$value"
	if [ "${#names[@]}" -eq 0 ]; then
		printf 'Expected at least one skill name for --%s.\n' "$operation" >&2
		return 1
	fi

	for skill_name in "${names[@]}"; do
		skill_name="${skill_name#"${skill_name%%[![:space:]]*}"}"
		skill_name="${skill_name%"${skill_name##*[![:space:]]}"}"
		if [ -z "$skill_name" ]; then
			printf 'Expected at least one skill name for --%s.\n' "$operation" >&2
			return 1
		fi

		skill_operation_types+=("$operation")
		skill_operation_names+=("$skill_name")
	done
}

# Returns 0 when a canonical skill folder has the requested name.
#
# @param  {string}  requested_name
#     Skill name to find in the canonical skills directory.
canonical_skill_exists() {
	local requested_name="$1"  # Skill name supplied by the user.
	local skill  # Canonical skill directory currently being checked.

	for skill in "$REPO_DIR"/skills/*/*; do
		[ -d "$skill" ] || continue
		if [ "$(basename "$skill")" = "$requested_name" ]; then
			return 0
		fi
	done

	return 1
}

# Rejects unknown exclusions and includes unless an include clears a saved name.
#
# @return  {integer}
#     0 when every requested skill name is known, or 1 otherwise.
validate_skill_operations() {
	local index  # Index of the pending skill operation being validated.
	local skill_name  # Requested skill name currently being validated.
	local operation  # Pending operation for the requested skill name.

	if [ "${#skill_operation_types[@]}" -eq 0 ]; then
		return 0
	fi

	for index in "${!skill_operation_types[@]}"; do
		operation="${skill_operation_types[$index]}"
		if [ "$operation" = "include-all" ]; then
			continue
		fi

		skill_name="${skill_operation_names[$index]}"
		if ! canonical_skill_exists "$skill_name" && {
			[ "$operation" != "include" ] || ! excluded_skill_exists "$skill_name"
		}; then
			printf 'Unknown skill: %s\n' "$skill_name" >&2
			return 1
		fi
	done
}

# Reads persisted skill exclusions without creating the exclusions file.
load_skill_exclusions() {
	local skill_name  # Persisted skill name currently being read.

	[ -f "$skill_exclusions_file" ] || return 0

	while IFS= read -r skill_name; do
		[ -n "$skill_name" ] || continue
		if ! excluded_skill_exists "$skill_name"; then
			excluded_skills+=("$skill_name")
		fi
	done < "$skill_exclusions_file"
}

# Returns 0 when the current exclusion list contains a skill name.
#
# @param  {string}  skill_name
#     Skill name to find in the current exclusion list.
excluded_skill_exists() {
	local skill_name="$1"  # Skill name to find in the exclusion list.
	local excluded_skill  # Excluded skill name currently being checked.

	if [ "${#excluded_skills[@]}" -gt 0 ]; then
		for excluded_skill in "${excluded_skills[@]}"; do
			if [ "$excluded_skill" = "$skill_name" ]; then
				return 0
			fi
		done
	fi

	return 1
}

# Adds a skill name to the current exclusion list once.
#
# @param  {string}  skill_name
#     Skill name to exclude from future setup runs.
add_excluded_skill() {
	local skill_name="$1"  # Skill name to add to the exclusion list.

	if ! excluded_skill_exists "$skill_name"; then
		excluded_skills+=("$skill_name")
	fi
}

# Removes a skill name from the current exclusion list.
#
# @param  {string}  skill_name
#     Skill name to include in future setup runs.
remove_excluded_skill() {
	local skill_name="$1"  # Skill name to remove from the exclusion list.
	local excluded_skill  # Existing exclusion currently being retained.
	local -a remaining_skills=()  # Exclusions that do not match the requested name.

	if [ "${#excluded_skills[@]}" -gt 0 ]; then
		for excluded_skill in "${excluded_skills[@]}"; do
			if [ "$excluded_skill" != "$skill_name" ]; then
				remaining_skills+=("$excluded_skill")
			fi
		done
	fi

	if [ "${#remaining_skills[@]}" -gt 0 ]; then
		excluded_skills=("${remaining_skills[@]}")
	else
		excluded_skills=()
	fi
}

# Applies the validated skill operations in their command-line order.
apply_skill_operations() {
	local index  # Index of the pending operation being applied.
	local operation  # Operation name for the current pending operation.
	local skill_name  # Skill name for the current pending operation.

	if [ "${#skill_operation_types[@]}" -eq 0 ]; then
		return 0
	fi

	for index in "${!skill_operation_types[@]}"; do
		operation="${skill_operation_types[$index]}"
		skill_name="${skill_operation_names[$index]}"
		case "$operation" in
			exclude) add_excluded_skill "$skill_name" ;;
			include) remove_excluded_skill "$skill_name" ;;
			include-all) excluded_skills=() ;;
		esac
	done
}

# Writes the current exclusions, removing the file when no exclusions remain.
save_skill_exclusions() {
	local skill_name  # Excluded skill name currently being written.
	local temp  # Temporary file used for an atomic replacement.

	if [ "${#excluded_skills[@]}" -eq 0 ]; then
		if [ -e "$skill_exclusions_file" ] || [ -L "$skill_exclusions_file" ]; then
			trash "$skill_exclusions_file"
		fi
		return 0
	fi

	mkdir -p "$HOME/.agents"
	temp=$(mktemp)
	for skill_name in "${excluded_skills[@]}"; do
		printf '%s\n' "$skill_name" >> "$temp"
	done
	mv "$temp" "$skill_exclusions_file"
}

# Joins the current exclusions into one comma-separated list for output.
format_excluded_skills() {
	local formatted=''  # Comma-separated exclusion names for terminal output.
	local skill_name  # Excluded skill name currently being formatted.

	for skill_name in "${excluded_skills[@]}"; do
		if [ -n "$formatted" ]; then
			formatted="$formatted, $skill_name"
		else
			formatted="$skill_name"
		fi
	done

	printf '%s' "$formatted"
}

# Tells the user which skills this run skips and where that list is saved,
# so a missing skill is explained rather than looking like a broken install.
report_excluded_skills() {
	local formatted  # Comma-separated exclusion names for terminal output.

	if [ "${#excluded_skills[@]}" -eq 0 ]; then
		return 0
	fi

	formatted=$(format_excluded_skills)
	printf 'Excluded: %s (from ~/.agents/skill-exclusions; run with --include-all to restore)\n' "$formatted"
}

# Links canonical skills while passing the current exclusion list safely on
# macOS Bash 3.2, where expanding an empty array under `set -u` fails.
#
# @param  {string}  target_dir
#     Directory to install skill symlinks into.
link_configured_skills() {
	local target_dir="$1"  # Directory to install skill symlinks into.

	if [ "${#excluded_skills[@]}" -gt 0 ]; then
		link_skills "$target_dir" "${excluded_skills[@]}"
	else
		link_skills "$target_dir"
	fi
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
	link_configured_skills "$CLAUDE_DIR/skills"
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
	link_configured_skills "$HOME/.agents/skills"
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
	local approval_policy default_permissions

	approval_policy=$(codex_config_value "root" "approval_policy")
	default_permissions=$(codex_config_value "root" "default_permissions")

	awk -v approval_policy="$approval_policy" -v default_permissions="$default_permissions" '
		function print_defaults() {
			print "approval_policy = " approval_policy
			print "default_permissions = " default_permissions
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
		in_root && /^(approval_policy|default_permissions|sandbox_mode)[[:space:]]*=/ { next }
		{ print }
		END {
			if (!defaults_written) {
				print_defaults()
			}
		}
	' "$source" > "$destination"
}

# Collects the managed and existing workspace roots without duplicates.
# Legacy sandbox roots are included so setup migrates them into the profile.
#
# @param  {string}  config
#     Existing Codex config whose workspace roots should be preserved.
# @param  {string}  destination
#     File that receives quoted TOML paths, one per line.
collect_codex_workspace_roots() {
	local config="$1" destination="$2"

	{
		sed "s|{{HOME}}|$HOME|g" "$REPO_DIR/src/adapters/codex/config.base.toml"
		printf '\n'
		cat "$config"
	} | awk '
		/^\[/ { section = $0 }
		section == "[permissions.project-edit.workspace_roots]" && /^[[:space:]]*"[^"]+"[[:space:]]*=[[:space:]]*true/ {
			root = $0
			sub(/^[[:space:]]*/, "", root)
			sub(/"[[:space:]]*=.*$/, "\"", root)
			if (!seen[root]++) {
				print root
			}
		}
		section == "[sandbox_workspace_write]" && /^writable_roots[[:space:]]*=/ {
			line = $0
			while (match(line, /"[^"]+"/)) {
				root = substr(line, RSTART, RLENGTH)
				if (!seen[root]++) {
					print root
				}
				line = substr(line, RSTART + RLENGTH)
			}
		}
	' > "$destination"
}

# Replaces the managed permission profile and removes incompatible sandbox settings.
#
# @param  {string}  config
#     Codex config file to update.
ensure_codex_permission_settings() {
	local config="$1"
	local roots_temp temp

	roots_temp=$(mktemp)
	temp=$(mktemp)
	collect_codex_workspace_roots "$config" "$roots_temp"

	awk '
		/^\[sandbox_workspace_write\]$/ || /^\[permissions\.project-edit(\.|\])/{ skip = 1; next }
		/^\[/ { skip = 0 }
		!skip { print }
	' "$config" > "$temp"

	printf '\n' >> "$temp"
	codex_config_section "permissions.project-edit" >> "$temp"
	printf '\n[permissions.project-edit.workspace_roots]\n' >> "$temp"
	awk '{ print $0 " = true" }' "$roots_temp" >> "$temp"
	printf '\n' >> "$temp"
	codex_config_section 'permissions.project-edit.filesystem.":workspace_roots"' >> "$temp"
	printf '\n' >> "$temp"
	codex_config_section "permissions.project-edit.network" >> "$temp"

	trash "$roots_temp"
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
	ensure_codex_permission_settings "$temp"
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
skill_options_requested=false  # Whether command-line skill options were supplied.
skill_exclusions_file="$HOME/.agents/skill-exclusions"  # File that stores excluded skill names.
excluded_skills=()  # Skill names excluded from the selected setup targets.
skill_operation_types=()  # Pending include or exclude operations in command-line order.
skill_operation_names=()  # Skill names associated with the pending operations.
CLAUDE_DIR="$HOME/.claude"  # Overridable so a second account can install alongside the default one.
CODEX_DIR="$HOME/.codex"    # Overridable so a second account can install alongside the default one.

while [ $# -gt 0 ]; do
	case "$1" in
		--claude)        target="claude" ;;
		--codex)         target="codex" ;;
		--both)          target="both" ;;
		--claude-dir)    CLAUDE_DIR="$2"; shift ;;
		--codex-dir)     CODEX_DIR="$2"; shift ;;
		--exclude)
			if [ "$#" -lt 2 ] || ! parse_skill_list "exclude" "$2"; then
				usage >&2
				exit 1
			fi
			skill_options_requested=true
			shift
			;;
		--include)
			if [ "$#" -lt 2 ] || ! parse_skill_list "include" "$2"; then
				usage >&2
				exit 1
			fi
			skill_options_requested=true
			shift
			;;
		--include-all)
			skill_operation_types+=("include-all")
			skill_operation_names+=("")
			skill_options_requested=true
			;;
		--refresh)       refresh=true ;;
		--skip-external) sync_external=false ;;
		--help)          usage; exit 0 ;;
		*)               usage >&2; exit 1 ;;
	esac
	shift
done

load_skill_exclusions
if ! validate_skill_operations; then
	exit 1
fi

if [ "$skill_options_requested" = true ]; then
	apply_skill_operations
	save_skill_exclusions
fi

report_excluded_skills

if [ -z "$target" ]; then
	if [ "$skill_options_requested" = true ]; then
		target="both"
	else
		target=$(prompt_target)
	fi
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
