#!/usr/bin/env bash
# Builds the changes setup would make without changing the installation.
# Before sourcing this file, set REPO_DIR and source setup-links.sh,
# setup-checks.sh, and setup-selection.sh.
# The plan values are read by setup.sh and doctor.sh, and
# cli_style_install_command is set by setup-checks.sh.
# shellcheck disable=SC2034,SC2154

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
# @param  {string}  prepared_codex_config
#     A Codex config that is already prepared, or empty to prepare one here.
build_setup_plan() {
	# The agents to set up.
	local target="$1"
	# A Codex config that is already prepared, or empty.
	local prepared_codex_config="${2:-}"
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
		plan_codex_setup "$prepared_codex_config"
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
#
# @param  {string}  prepared_config
#     A Codex config that is already prepared, or empty to prepare one here.
plan_codex_setup() {
	# A Codex config that is already prepared, or empty.
	local prepared_config="${1:-}"
	# The helper command currently being checked.
	local command_name
	# The Codex config setup would write, compared with the user's current file.
	local config_temp
	# Whether this function must remove the config it creates.
	local remove_config_temp=false

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

	if [ -n "$prepared_config" ]; then
		config_temp="$prepared_config"
	else
		config_temp=$(mktemp)
		remove_config_temp=true
		prepare_codex_config "$CODEX_DIR/config.toml" "$config_temp"
	fi
	if [ ! -f "$CODEX_DIR/config.toml" ] || ! cmp -s "$CODEX_DIR/config.toml" "$config_temp"; then
		if [ -e "$CODEX_DIR/config.toml" ] || [ -L "$CODEX_DIR/config.toml" ]; then
			plan_backup "$CODEX_DIR/config.toml"
		fi
		plan_change "Codex settings" "Write $(display_path "$CODEX_DIR/config.toml") with managed defaults, MCP servers, TUI settings, the permission profile and hooks"
	fi
	if [ "$remove_config_temp" = true ]; then
		rm "$config_temp"
	fi

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
		printf '%s\n' 'HCOM arguments could not be read, so HCOM changes are not listed.' >&2
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

