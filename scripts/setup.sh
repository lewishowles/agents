#!/usr/bin/env bash
# Installs global agent configuration into Claude and Codex via symlinks.

set -euo pipefail

# The folder containing this script, resolved so aliases work from any directory.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the configuration installed by this script.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=scripts/lib/setup-links.sh
source "$REPO_DIR/scripts/lib/setup-links.sh"

# shellcheck source=scripts/lib/setup-checks.sh
source "$REPO_DIR/scripts/lib/setup-checks.sh"

# shellcheck source=scripts/lib/setup-selection.sh
source "$REPO_DIR/scripts/lib/setup-selection.sh"

# Reads the options and chooses what to install, then installs the configuration
# for Claude, Codex or both along with the shared trash wrapper and Git hooks.
#
# @param  {string}  ...
#     Command-line options passed to the script.
main() {
	parse_setup_options "$@"
	load_skill_exclusions

	load_managed_paths
	# shellcheck source=scripts/lib/cli-style-output.sh
	source "$REPO_DIR/scripts/lib/cli-style-output.sh"

	preflight_agent_tools "$target" || exit 1

	build_setup_plan "$target"
	if [ "$plan_count" -eq 0 ]; then
		printf '%s\n' 'Nothing to change.'
		exit 0
	fi

	if cli_style_install_needed; then
		printf 'Running: %s\n' "${cli_style_install_command[*]}"
		"${cli_style_install_command[@]}"
		# Load the output helpers again so the rest of setup uses the cli-style
		# that was just installed.
		# shellcheck source=scripts/lib/cli-style-output.sh
		source "$REPO_DIR/scripts/lib/cli-style-output.sh"
		if cli_style_install_needed; then
			cli_status warning 'cli-style' 'still not found after install; check that the global bin folder is on PATH'
		fi
	fi

	case "$target" in
		claude) setup_claude ;;
		codex)  setup_codex ;;
		both)   setup_claude; setup_codex ;;
	esac

	# Link the trash wrapper once, outside the per-agent setup, because ~/.local/bin is shared by
	# both agents and the user's own shell.
	cli_section "Shared command-line tools"
	cli_group_begin "Trash wrapper"
	# mkdir -p follows a symlinked ~/.local/bin, such as one kept in dotfiles, instead of replacing it.
	mkdir -p "$HOME/.local/bin"
	managed_links shared trash link_path
	cli_group_end

	configure_git_hooks

	printf '\n'
	cli_status success "Done."
}

# Sets the folders HCOM grants to Codex agents after the repository path is known.
load_managed_paths() {
	# Folders HCOM grants to the Codex agents it starts.
	HCOM_FOLDERS=("$REPO_DIR" "$HOME/.agents" "$HOME/.Trash" "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm")
}

# Gathers every change setup would make for the chosen agents into plan_items
# and plan_count, without changing installed files. Also fills
# planned_pruned_links with stale links so they are not counted for backup too.
# Returns 1 when the skills cannot be read, or when cli-style is missing and
# no package manager can install it.
#
# @param  {string}  target
#     The agents to set up: claude, codex or both.
build_setup_plan() {
	# The agents to set up.
	local target="$1"
	# The Git hook setting currently used by this checkout.
	local hooks_path

	plan_items=()
	plan_count=0
	planned_commands=()
	planned_pruned_links=()

	if ! collect_canonical_skills; then
		return 1
	fi

	if cli_style_install_needed; then
		choose_cli_style_install_command || return 1
		plan_change "Helper commands" "Run ${cli_style_install_command[*]}"
	fi

	if [ "$target" = claude ] || [ "$target" = both ]; then
		plan_claude_setup
	fi

	if [ "$target" = codex ] || [ "$target" = both ]; then
		plan_codex_setup
	fi

	if [ ! -e "$HOME/.local/bin" ] && [ ! -L "$HOME/.local/bin" ]; then
		plan_change "Directories" "Create $(display_path "$HOME/.local/bin")"
	fi
	managed_links shared trash plan_link_path
	hooks_path=$(git -C "$REPO_DIR" config --get core.hooksPath 2>/dev/null || true)
	if [ "$hooks_path" != src/hooks/git ]; then
		plan_change "Git hooks" "Set core.hooksPath to src/hooks/git in this checkout"
	fi
}

# Records one planned change under its kind.
#
# @param  {string}  kind
#     The section that owns the change.
# @param  {string}  description
#     The path or setting setup will change.
plan_change() {
	# Each change is stored as "kind|description" so it can be grouped later.
	plan_items+=("$1|$2")
	plan_count=$((plan_count + 1))
}

# Adds the Claude folders, links, stale links and missing helper commands to the
# setup plan.
plan_claude_setup() {
	# The helper command currently being checked.
	local command_name

	plan_container_dir "$CLAUDE_DIR"
	plan_container_dir "$CLAUDE_DIR/skills"
	plan_container_dir "$CLAUDE_DIR/rules"
	plan_container_dir "$CLAUDE_DIR/hooks"
	plan_container_dir "$CLAUDE_DIR/themes"

	while IFS= read -r command_name; do
		plan_helper_command "$command_name"
	done < <(required_agent_tools claude)

	managed_links claude core plan_link_path
	managed_links claude settings plan_link_path

	plan_prune_stale_repo_links "$CLAUDE_DIR/skills" "$REPO_DIR"
	plan_skill_links "$CLAUDE_DIR/skills"

	plan_prune_stale_repo_links "$CLAUDE_DIR/hooks" "$REPO_DIR/dist/claude/hooks"
	managed_links claude hooks plan_link_path

	plan_prune_stale_repo_links "$CLAUDE_DIR/themes" "$REPO_DIR/dist/claude/themes"
	managed_links claude themes plan_link_path

	plan_prune_stale_repo_links "$CLAUDE_DIR/rules" "$REPO_DIR/dist/claude/rules"
	managed_links claude rules plan_link_path
}

# Adds the install of a missing agent-tools command to the setup plan. A
# command both agents need is listed once.
#
# @param  {string}  command_name
#     The command setup installs with uv when it is missing.
plan_helper_command() {
	# The command needed by this agent setup.
	local command_name="$1"
	# A command already listed for the other agent.
	local planned

	if [ "${#planned_commands[@]}" -gt 0 ]; then
		for planned in "${planned_commands[@]}"; do
			[ "$planned" = "$command_name" ] && return
		done
	fi

	if ! command -v "$command_name" >/dev/null 2>&1; then
		plan_change "Helper commands" "Install $command_name with uv from $(display_path "$AGENT_TOOLS_DIR/packages/$command_name")"
		planned_commands+=("$command_name")
	fi
}

# Adds the Codex folders, links, config changes, HCOM folder additions and
# missing helper commands to the setup plan.
plan_codex_setup() {
	# The helper command currently being checked.
	local command_name
	# The Codex config setup would write, compared with the user's current file.
	local config_temp

	plan_container_dir "$HOME/.agents"
	plan_container_dir "$HOME/.agents/skills"
	plan_container_dir "$CODEX_DIR"
	plan_container_dir "$CODEX_DIR/hooks"

	while IFS= read -r command_name; do
		plan_helper_command "$command_name"
	done < <(required_agent_tools codex)

	managed_links codex core plan_link_path
	managed_links codex manifest plan_link_path
	plan_prune_stale_repo_links "$CODEX_DIR/hooks" "$REPO_DIR/dist/codex/hooks"
	managed_links codex hooks plan_link_path

	config_temp=$(mktemp)
	prepare_codex_config "$CODEX_DIR/config.toml" "$config_temp"
	if [ ! -f "$CODEX_DIR/config.toml" ] || ! cmp -s "$CODEX_DIR/config.toml" "$config_temp"; then
		if [ -e "$CODEX_DIR/config.toml" ] || [ -L "$CODEX_DIR/config.toml" ]; then
			plan_backup "$CODEX_DIR/config.toml"
		fi
		plan_change "Codex settings" "Write $(display_path "$CODEX_DIR/config.toml") with managed defaults, MCP servers, TUI settings, the permission profile and hooks"
	fi
	rm "$config_temp"

	plan_prune_stale_repo_links "$HOME/.agents/skills" "$REPO_DIR"
	plan_prune_stale_repo_links "$CODEX_DIR/skills" "$REPO_DIR" 1
	plan_skill_links "$HOME/.agents/skills"

	plan_hcom_folders
}

# Adds the folders that setup will append to HCOM's Codex arguments to the
# setup plan. ~/.agents is listed even before it exists, because setup
# creates it before updating HCOM.
plan_hcom_folders() {
	# The current HCOM argument string for Codex agents.
	local codex_args
	# The current HCOM arguments split into option and value tokens.
	local -a existing_args=()
	# The folder HCOM should grant to Codex agents.
	local folder
	# The position of one token in the current arguments.
	local argument_index
	# The folder that follows an --add-dir option, with ~ expanded.
	local existing_folder
	# Whether the folder already appears after an --add-dir option.
	local folder_present

	if ! command -v hcom >/dev/null 2>&1; then
		return
	fi

	if ! codex_args=$(hcom config codex_args); then
		printf '%s\n' 'HCOM arguments could not be read; setup will skip HCOM additions.' >&2
		return
	fi

	read -r -a existing_args <<< "$codex_args"
	for folder in "${HCOM_FOLDERS[@]}"; do
		if [ ! -d "$folder" ] && [ "$folder" != "$HOME/.agents" ]; then
			continue
		fi

		folder_present=false
		for argument_index in "${!existing_args[@]}"; do
			[ "${existing_args[$argument_index]}" = --add-dir ] || continue
			existing_folder="${existing_args[$((argument_index + 1))]:-}"
			existing_folder="${existing_folder/#\~\//$HOME/}"
			if [ "$existing_folder" = "$folder" ]; then
				folder_present=true
				break
			fi
		done

		if [ "$folder_present" = false ]; then
			plan_change "HCOM" "Add --add-dir $(display_path "$folder") to hcom config codex_args"
		fi
	done
}

# Installs Claude's skill links, main configuration, hooks, themes and helper commands.
setup_claude() {
	# The managed folder or generated file currently installed for Claude.
	local file
	# The display label used for a managed Claude folder.
	local label

	cli_section "Claude global setup ($(display_path "$CLAUDE_DIR"))"

	cli_group_begin "Claude directories"
	for file in "$CLAUDE_DIR" "$CLAUDE_DIR/skills"; do
		label="${file##*/}"
		if [ "$file" = "$CLAUDE_DIR" ]; then
			label=$(display_path "$file")
		fi
		ensure_container_dir "$file" "$label"
	done
	ensure_container_dir "$CLAUDE_DIR/rules" rules
	ensure_container_dir "$CLAUDE_DIR/hooks" hooks
	ensure_container_dir "$CLAUDE_DIR/themes" themes
	cli_group_end

	cli_group_begin "Claude command-line tools"
	ensure_friction
	ensure_team_send
	ensure_doc_paths
	cli_group_end

	cli_group_begin "Claude files"
	managed_links claude core link_path
	managed_links claude settings link_path
	cli_group_end

	cli_group_begin "Claude skills"
	prune_stale_repo_links "$CLAUDE_DIR/skills" "$REPO_DIR" "skills"
	link_configured_skills "$CLAUDE_DIR/skills"
	cli_group_end

	cli_group_begin "Claude hooks"
	prune_stale_repo_links "$CLAUDE_DIR/hooks" "$REPO_DIR/dist/claude/hooks" "hooks"
	managed_links claude hooks link_path
	cli_group_end

	cli_group_begin "Claude themes"
	prune_stale_repo_links "$CLAUDE_DIR/themes" "$REPO_DIR/dist/claude/themes" "themes"
	managed_links claude themes link_path
	cli_group_end

	cli_group_begin "Claude rules"
	prune_stale_repo_links "$CLAUDE_DIR/rules" "$REPO_DIR/dist/claude/rules" "rules"
	managed_links claude rules link_path
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
	if ! uv tool install --from "$AGENT_TOOLS_DIR/packages/friction" friction >/dev/null; then
		cli_group_status failed "friction" "global installation failed"
		return 1
	fi

	if ! command -v friction >/dev/null 2>&1; then
		cli_group_status failed "friction" "installation did not expose friction"
		return 1
	fi

	cli_group_status success "friction" "installed globally"
}

# Ensures team-send is available for HCOM team messages.
ensure_team_send() {
	if command -v team-send >/dev/null 2>&1; then
		cli_group_status muted "team-send" "globally installed"
		return
	fi

	if ! command -v uv >/dev/null 2>&1; then
		cli_group_status failed "team-send" "missing and uv is not installed"
		return 1
	fi

	cli_group_status warning "team-send" "installing globally"
	if ! uv tool install --from "$AGENT_TOOLS_DIR/packages/team-send" team-send >/dev/null; then
		cli_group_status failed "team-send" "global installation failed"
		return 1
	fi

	if ! command -v team-send >/dev/null 2>&1; then
		cli_group_status failed "team-send" "installation did not expose team-send"
		return 1
	fi

	cli_group_status success "team-send" "installed globally"
}

# Ensures doc-paths, the checker for Markdown links to missing files, is
# available for validation and the writing and project-audit skills.
ensure_doc_paths() {
	if command -v doc-paths >/dev/null 2>&1; then
		cli_group_status muted "doc-paths" "globally installed"
		return
	fi

	if ! command -v uv >/dev/null 2>&1; then
		cli_group_status failed "doc-paths" "missing and uv is not installed"
		return 1
	fi

	cli_group_status warning "doc-paths" "installing globally"
	if ! uv tool install --from "$AGENT_TOOLS_DIR/packages/doc-paths" doc-paths >/dev/null; then
		cli_group_status failed "doc-paths" "global installation failed"
		return 1
	fi

	if ! command -v doc-paths >/dev/null 2>&1; then
		cli_group_status failed "doc-paths" "installation did not expose doc-paths"
		return 1
	fi

	cli_group_status success "doc-paths" "installed globally"
}

# Links every skill except the names in the repository exclusion list.
# Removes installed links for excluded skills.
# Returns 1 without creating any links when two collections hold a skill with
# the same name.
#
# @param  {string}  target_dir
#     Directory to install skill symlinks into.
link_configured_skills() {
	# The agent skill folder receiving links to canonical skills.
	local target_dir="$1"
	# The canonical skill folder checked against saved choices.
	local skill_path
	# The installed link for the skill currently being checked.
	local skill_link
	# The canonical skills, collected with duplicate-name checks.
	local skill_paths=()

	if ! collect_canonical_skills; then
		return 1
	fi
	if [ "${#skill_paths[@]}" -eq 0 ]; then
		return 0
	fi

	for skill_path in "${skill_paths[@]}"; do
		skill_link="$target_dir/${skill_path##*/}"
		if ! skill_is_selected "$skill_path"; then
			if is_repo_owned_link "$skill_path" "$skill_link"; then
				trash "$skill_link"
				cli_group_status warning "removed excluded skill" "skills/${skill_path##*/}"
			fi
			continue
		fi

		link_path "$skill_path" "$skill_link" "skills/${skill_path##*/}"
	done
}

# Installs Codex's skill links, main configuration, hooks, permission profile,
# HCOM folders and helper commands.
setup_codex() {
	# The managed Codex folder currently ensured by setup.
	local folder
	# The label displayed when a Codex folder needs replacement.
	local label

	cli_section "Codex global setup ($(display_path "$CODEX_DIR"))"

	cli_group_begin "Codex directories"
	for folder in "$HOME/.agents" "$HOME/.agents/skills"; do
		label=$(display_path "$folder")
		ensure_container_dir "$folder" "$label"
	done
	ensure_container_dir "$CODEX_DIR" "$(display_path "$CODEX_DIR")"
	ensure_container_dir "$CODEX_DIR/hooks" hooks
	cli_group_end

	cli_group_begin "Codex command-line tools"
	ensure_team_send
	ensure_doc_paths
	cli_group_end

	cli_group_begin "Codex files"
	managed_links codex core link_path
	managed_links codex manifest link_path
	prune_stale_repo_links "$CODEX_DIR/hooks" "$REPO_DIR/dist/codex/hooks" "hooks"
	managed_links codex hooks link_path
	ensure_codex_config
	cli_group_end

	cli_group_begin "Codex skills"
	prune_stale_repo_links "$HOME/.agents/skills" "$REPO_DIR" "skills"
	prune_stale_repo_links "$CODEX_DIR/skills" "$REPO_DIR" "legacy skills" "1"
	link_configured_skills "$HOME/.agents/skills"
	cli_group_end

	setup_hcom_codex_folders
}

# Ensures $CODEX_DIR/config.toml contains the managed defaults, MCP server
# entries, feature flags, memory settings, and TUI status line. Legacy inline
# hooks are removed only when hooks are chosen.
ensure_codex_config() {
	# The user's Codex configuration file updated by setup.
	local config="$CODEX_DIR/config.toml"
	# The completed managed configuration before it replaces the user's file.
	local temp

	temp=$(mktemp)
	prepare_codex_config "$config" "$temp"

	if [ -f "$config" ] && cmp -s "$config" "$temp"; then
		rm "$temp"
		cli_group_status muted "Codex config" "already configured"
		return
	fi

	if [ -e "$config" ] || [ -L "$config" ]; then
		# The saved copy of the configuration before setup replaces it.
		local backup
		backup=$(backup_path "$config")
		mv "$temp" "$config"
		cli_group_status success "configured Codex settings" "backup at $(display_path "$backup")"
	else
		mv "$temp" "$config"
		cli_group_status success "configured Codex settings"
	fi
}

# Adds the folders sandboxed Codex agents need to the --add-dir list that HCOM
# passes to every Codex agent it starts, which HCOM stores in ~/.hcom/config.toml.
# Only folders that exist on this machine are added, and entries the user added are
# kept as written. Agents that are already running keep the list they started with.
setup_hcom_codex_folders() {
	# The current HCOM arguments split into option and value tokens.
	local -a existing_args=()
	# The current HCOM argument string. Missing folders are appended to it, so the
	# user's own options and spacing stay as written.
	local codex_args
	# The required folder currently checked for an existing permission.
	local folder
	# The token position in the existing HCOM argument list.
	local argument_index
	# The folder path following an existing --add-dir option.
	local existing_folder
	# Whether HCOM already grants the current folder.
	local folder_present
	# Whether any folder was added.
	local changed=0

	if ! command -v hcom >/dev/null 2>&1; then
		cli_status skipped "HCOM" "not installed"
		return
	fi

	# A failing hcom command is reported rather than stopping the rest of setup.
	if ! codex_args=$(hcom config codex_args); then
		cli_status warning "HCOM" "could not read Codex arguments; run: hcom config codex_args"
		return
	fi

	read -r -a existing_args <<< "$codex_args"

	for folder in "${HCOM_FOLDERS[@]}"; do
		if [ ! -d "$folder" ]; then
			continue
		fi

		folder_present=0

		for argument_index in "${!existing_args[@]}"; do
			if [ "${existing_args[$argument_index]}" != "--add-dir" ]; then
				continue
			fi

			existing_folder="${existing_args[$((argument_index + 1))]:-}"
			existing_folder="${existing_folder/#\~\//$HOME/}"
			if [ "$existing_folder" = "$folder" ]; then
				folder_present=1
				break
			fi
		done

		if [ "$folder_present" -eq 0 ]; then
			codex_args="${codex_args:+$codex_args }--add-dir $folder"
			changed=1
		fi
	done

	if [ "$changed" -eq 0 ]; then
		cli_status muted "HCOM" "Codex folders already configured"
		return
	fi

	if ! hcom config codex_args "$codex_args"; then
		cli_status warning "HCOM" "could not update Codex arguments; check hcom config codex_args --info, then rerun setup"
		return
	fi

	cli_status success "HCOM" "Codex folders updated; relaunch from a fresh terminal"
}

# Configures git to use src/hooks/git/ as the hook directory for this repo.
# This installs the pre-push hook without touching ~/.git/hooks directly.
configure_git_hooks() {
	cli_section "Git hooks"
	if [ "$(git -C "$REPO_DIR" config --get core.hooksPath 2>/dev/null || true)" = src/hooks/git ]; then
		cli_status muted "git hooks path" "already set"
		return
	fi

	if ! git -C "$REPO_DIR" config core.hooksPath src/hooks/git &>/dev/null; then
		cli_status warning "Could not set core.hooksPath" "not a git repo?"
		return
	fi

	cli_status success "git hooks path set" "src/hooks/git/"
}

main "$@"
