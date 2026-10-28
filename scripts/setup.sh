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

# Reads the command-line options and saves any changes to the skill selection.
# Then it either reports which skills are linked, or installs the configuration
# for Claude, Codex or both along with the shared trash wrapper and Git hooks.
#
# @param  {string}  ...
#     Command-line options passed to the script.
main() {
	# The agents to set up (claude, codex or both). It comes from the options, defaults
	# to both for the skill and status options, and is otherwise asked for.
	target=""
	# Whether to run sync.sh to regenerate dist/ before installing links.
	refresh=false
	# Whether command-line skill options were supplied.
	skill_options_requested=false
	# Whether the terminal skill selection flow was requested.
	select_requested=false
	# Whether to report skill link states without changing skill links.
	status_requested=false
	# Whether a scripted run may apply its printed plan without a terminal.
	yes_requested=false
	# The preset the user chose: skills-only, pick or everything. Empty runs the
	# full setup, which is what setup did before presets existed.
	preset=""
	# Whether to install each agent's main configuration, such as CLAUDE.md and
	# Codex's config.toml, and set this checkout's Git hooks.
	setup_core=true
	# Whether to install the chosen agents' hook files and registrations.
	setup_hooks=true
	# Whether to add the managed Codex permission profile.
	setup_permissions=true
	# Whether to grant folders to Codex agents started by HCOM.
	setup_hcom=true
	# Whether to link the Claude themes.
	setup_themes=true
	# Whether to link the shared trash wrapper.
	setup_trash=true
	# Whether to install missing helper commands and cli-style.
	setup_helpers=true
	# The file that stores excluded skill names between setup runs.
	skill_exclusions_file="$HOME/.agents/skill-exclusions"
	# The file that stores the default-off collections the user has opted in to.
	skill_inclusions_file="$HOME/.agents/skill-inclusions"
	# Collections that require an explicit choice before their skills are linked.
	default_off_collections=(apple)
	# Default-off collections selected for installation.
	included_collections=()
	# The skill names excluded from the selected setup targets.
	excluded_skills=()
	# The pending include or exclude operations in command-line order.
	skill_operation_types=()
	# The skill names associated with the pending operations.
	skill_operation_names=()
	# The canonical skill directories available for interactive selection.
	skill_paths=()
	# The Claude configuration folder, overridable for a second account.
	CLAUDE_DIR="$HOME/.claude"
	# The Codex configuration folder, overridable for a second account.
	CODEX_DIR="$HOME/.codex"
	# The local agent-tools checkout that setup installs missing commands from.
	AGENT_TOOLS_DIR="$HOME/Dev/Repositories/Packages/agent-tools"

	while [ $# -gt 0 ]; do
		case "$1" in
			--claude)        target="claude" ;;
			--codex)         target="codex" ;;
			--both)          target="both" ;;
			--preset)
				if [ "$#" -lt 2 ]; then
					usage >&2
					exit 1
				fi
				case "$2" in
					skills-only|pick|everything) preset="$2" ;;
					*)
						printf 'Unknown preset: %s\n' "$2" >&2
						usage >&2
						exit 1
						;;
				esac
				shift
				;;
			--claude-dir)    CLAUDE_DIR="$2"; shift ;;
			--codex-dir)     CODEX_DIR="$2"; shift ;;
			--select)
				select_requested=true
				skill_options_requested=true
				;;
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
			--status)        status_requested=true ;;
			--refresh)       refresh=true ;;
			--yes)           yes_requested=true ;;
			--help)          usage; exit 0 ;;
			*)               usage >&2; exit 1 ;;
		esac
		shift
	done

	if [ "$status_requested" = true ] && [ "$skill_options_requested" = true ]; then
		printf '%s\n' '--status cannot be combined with --select, --exclude, --include, or --include-all.' >&2
		usage >&2
		exit 1
	fi

	if [ "$select_requested" = true ] && [ "${#skill_operation_types[@]}" -gt 0 ]; then
		printf '%s\n' '--select cannot be combined with --exclude, --include, or --include-all.' >&2
		usage >&2
		exit 1
	fi

	if [ "$select_requested" = true ] && ! [ -t 0 ]; then
		printf '%s\n' '--select requires a terminal. Use --exclude or --include when standard input is not a terminal.' >&2
		exit 1
	fi
	if [ "$status_requested" = true ] && [ -n "$preset" ]; then
		printf '%s\n' '--status cannot be combined with --preset.' >&2
		exit 1
	fi
	if [ -z "$preset" ] && [ "$skill_options_requested" = false ] && [ "$status_requested" = false ] && [ -z "$target" ] && [ -t 0 ]; then
		preset=$(prompt_preset) || exit 1
		if [ "$preset" = cancelled ]; then
			printf '%s\n' 'Setup cancelled. Nothing changed.'
			exit 0
		fi
	fi
	case "$preset" in
		skills-only)
			setup_core=false setup_hooks=false setup_permissions=false
			setup_hcom=false setup_themes=false setup_trash=false setup_helpers=false
			;;
		pick)
			if ! [ -t 0 ]; then
				printf '%s\n' '--preset pick requires a terminal to choose features.' >&2
				exit 1
			fi
			;;
	esac
	if [ -z "$target" ]; then
		if [ "$skill_options_requested" = true ] || [ "$status_requested" = true ] || ! [ -t 0 ]; then
			target=both
		elif [ "$preset" = everything ]; then
			target=both
		else
			target=$(prompt_target)
		fi
	fi
	if [ "$preset" = pick ]; then
		pick_setup_features || exit 1
		if [ "$skill_options_requested" = false ]; then
			select_requested=true
			skill_options_requested=true
		fi
	fi

	load_skill_exclusions
	load_skill_inclusions
	if ! validate_skill_operations; then
		exit 1
	fi

	if [ "$select_requested" = true ]; then
		if ! collect_canonical_skills; then
			exit 1
		fi

		# The installed fzf version, when fzf is available.
		local fzf_version=''
		# Whether the picker opens in fzf rather than the numbered list.
		local use_fzf=false
		if command -v fzf >/dev/null 2>&1; then
			fzf_version=$(fzf --version 2>/dev/null) || fzf_version=''
			if fzf_supports_picker_actions "$fzf_version"; then
				use_fzf=true
			elif [ -n "$fzf_version" ]; then
				printf 'fzf %s cannot run this picker (it needs 0.74 or newer), so using the numbered list.\n' "$fzf_version" >&2
			else
				printf '%s\n' 'fzf version could not be read, so using the numbered list.' >&2
			fi
		fi

		if [ "$use_fzf" = true ]; then
			if ! select_skills_with_fzf; then
				printf '%s\n' 'Skill selection cancelled. Nothing changed.'
				exit 0
			fi
		else
			# The numbered selector result: 0 accepted, 1 cancelled, or 2 invalid.
			selection_status=0
			select_skills_with_numbered_list || selection_status=$?

			if [ "$selection_status" -eq 1 ]; then
				printf '%s\n' 'Skill selection cancelled. Nothing changed.'
				exit 0
			elif [ "$selection_status" -ne 0 ]; then
				exit 1
			fi
		fi
	elif [ "$skill_options_requested" = true ]; then
		apply_skill_operations
	fi

	load_managed_paths

	if [ "$status_requested" != true ] && [ "$setup_helpers" = true ]; then
		preflight_agent_tools "$target" || exit 1
	fi

	report_excluded_skills

	if [ "$status_requested" = true ]; then
		# The python3 calls in the status helpers would otherwise cache bytecode
		# in the user's home, and status must leave the home unchanged.
		export PYTHONDONTWRITEBYTECODE=1
		# shellcheck source=scripts/lib/cli-style-output.sh
		source "$REPO_DIR/scripts/lib/cli-style-output.sh"
		report_skill_status "$target"
		exit 0
	fi

	if [ "$refresh" = true ]; then
		bash "$REPO_DIR/scripts/sync.sh"
	fi

	build_setup_plan "$target"
	print_setup_plan
	if [ "$plan_count" -eq 0 ]; then
		printf '%s\n' 'Nothing to change.'
		exit 0
	fi

	if [ "$yes_requested" != true ]; then
		if ! [ -t 0 ]; then
			printf '%s\n' 'Setup needs --yes when standard input is not a terminal.' >&2
			exit 1
		fi

		printf 'Apply these changes? [y/N] '
		# The answer to the final setup confirmation.
		local answer
		IFS= read -r answer || answer=''
		case "$answer" in
			y|Y|yes|YES) ;;
			*) printf '%s\n' 'Setup cancelled. Nothing changed.'; exit 0 ;;
		esac
	fi

	if [ "$skill_options_requested" = true ] && skill_exclusions_changed; then
		save_skill_exclusions
	fi
	if [ "$skill_options_requested" = true ] && skill_inclusions_changed; then
		save_skill_inclusions
	fi
	if [ "$setup_helpers" = true ] && cli_style_install_needed; then
		printf 'Running: %s\n' "${cli_style_install_command[*]}"
		"${cli_style_install_command[@]}"
	fi
	# Helper setup always loads styled output, so a cli-style that is still missing
	# after the install stops setup with guidance. Other runs fall back to plain output.
	if [ "$setup_helpers" = true ] || ! cli_style_install_needed; then
		# shellcheck source=scripts/lib/cli-style-output.sh
		source "$REPO_DIR/scripts/lib/cli-style-output.sh"
	else
		enable_plain_setup_output
	fi

	case "$target" in
		claude) setup_claude ;;
		codex)  setup_codex ;;
		both)   setup_claude; setup_codex ;;
	esac

	# Link the trash wrapper once, outside the per-agent setup, because ~/.local/bin is shared by
	# both agents and the user's own shell.
	if [ "$setup_trash" = true ]; then
		cli_section "Shared command-line tools"
		cli_group_begin "Trash wrapper"
		# mkdir -p follows a symlinked ~/.local/bin, such as one kept in dotfiles, instead of replacing it.
		mkdir -p "$HOME/.local/bin"
		link_path "$REPO_DIR/src/bin/trash" "$HOME/.local/bin/trash" "$(display_path "$HOME/.local/bin/trash")"
		cli_group_end
	fi

	if [ "$setup_core" = true ]; then
		configure_git_hooks
	fi

	printf '\n'
	cli_status success "Done."
}

# Defines plain versions of the cli-style output functions for runs where
# cli-style is not installed, such as skills only. The plain cli_group_status
# defined below already covers link results.
enable_plain_setup_output() {
	cli_section() { printf '\n%s\n' "$1"; }
	cli_group_begin() { printf '%s\n' "$1"; }
	cli_group_end() { :; }
	cli_status() {
		printf '%s' "$2"
		if [ -n "${3:-}" ]; then
			printf ': %s' "$3"
		fi
		printf '\n'
	}
}

# Sets the folders, files and links that both the preview and the installer
# manage, so the preview and the installer read the same lists. Call it after
# the agent folders are known.
load_managed_paths() {
	# The generated files linked from dist/claude into the Claude folder.
	CLAUDE_FILES=(CLAUDE.md settings.json .mcp.json statusline.sh)
	# The generated files linked for Codex core setup, in the same order as the
	# installed paths and labels below.
	CODEX_LINK_SOURCES=("$REPO_DIR/dist/codex/AGENTS.md" "$REPO_DIR/dist/codex/AGENTS.md")
	# The installed paths for the Codex core links.
	CODEX_LINK_TARGETS=("$HOME/.agents/AGENTS.md" "$CODEX_DIR/AGENTS.md")
	# The names shown for the Codex core links.
	CODEX_LINK_LABELS=(AGENTS.md 'Codex AGENTS.md')
	# The generated Codex hook manifest, installed only when hooks are chosen.
	CODEX_HOOKS_SOURCE="$REPO_DIR/dist/codex/hooks.json"
	# The installed Codex hook manifest path.
	CODEX_HOOKS_TARGET="$CODEX_DIR/hooks.json"
	# The name shown for the Codex hook manifest.
	CODEX_HOOKS_LABEL='Codex hooks'
	# Folders HCOM grants to the Codex agents it starts.
	HCOM_FOLDERS=("$REPO_DIR" "$HOME/.agents" "$HOME/.Trash" "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm")
}

# Prints a plain skill problem, such as a duplicate skill name, while the plan is
# built and before cli-style may be installed. Loading the cli-style output
# library after confirmation replaces this with styled output.
#
# @param  {string}  result
#     The kind of result, such as warning or error.
# @param  {string}  label
#     What the message is about.
# @param  {string}  detail
#     Further explanation, if any.
cli_group_status() {
	# The kind of result.
	local result="$1"
	# What the message is about.
	local label="$2"
	# Further explanation, if any.
	local detail="${3:-}"

	printf '%s: %s (%s)\n' "$label" "$detail" "$result" >&2
}

# Returns success when saving the requested skill exclusions would change the
# saved file: when the list differs, when there is no file yet, or when every
# skill is now included and the file should be removed.
skill_exclusions_changed() {
	if [ "${#excluded_skills[@]}" -eq 0 ]; then
		[ -e "$skill_exclusions_file" ] || [ -L "$skill_exclusions_file" ]
	elif [ ! -f "$skill_exclusions_file" ]; then
		return 0
	else
		if ! cmp -s "$skill_exclusions_file" <(printf '%s\n' "${excluded_skills[@]}"); then
			return 0
		fi
		return 1
	fi
}

# Returns success when saving the collections the user opted in to would change
# the saved file: when the list differs, when there is no file yet, or when no
# opt-ins remain and the file should be removed.
skill_inclusions_changed() {
	if [ "${#included_collections[@]}" -eq 0 ]; then
		[ -e "$skill_inclusions_file" ] || [ -L "$skill_inclusions_file" ]
	elif [ ! -f "$skill_inclusions_file" ]; then
		return 0
	else
		if ! cmp -s "$skill_inclusions_file" <(printf '%s\n' "${included_collections[@]}"); then
			return 0
		fi
		return 1
	fi
}

# Gathers every change setup would make for the chosen agents into plan_items
# and plan_count, without changing installed files. Also fills
# planned_pruned_links with the stale links the preview lists for removal, so
# the same paths are not listed for backup too. Returns 1 when the skills cannot
# be read, or when cli-style is missing and no package manager can install it.
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

	if [ "$skill_options_requested" = true ] && skill_exclusions_changed; then
		if [ "${#excluded_skills[@]}" -eq 0 ]; then
			plan_change "Selection" "Remove $(display_path "$skill_exclusions_file")"
		else
			plan_change "Selection" "Write $(display_path "$skill_exclusions_file") with the selected exclusions"
		fi
	fi
	if [ "$skill_options_requested" = true ] && skill_inclusions_changed; then
		if [ "${#included_collections[@]}" -eq 0 ]; then
			plan_change "Selection" "Remove $(display_path "$skill_inclusions_file")"
		else
			plan_change "Selection" "Write $(display_path "$skill_inclusions_file") with the collections you opted in to"
		fi
	fi

	if [ "$setup_helpers" = true ] && cli_style_install_needed; then
		choose_cli_style_install_command || return 1
		plan_change "Helper commands" "Run ${cli_style_install_command[*]}"
	fi

	if [ "$target" = claude ] || [ "$target" = both ]; then
		plan_claude_setup
	fi

	if [ "$target" = codex ] || [ "$target" = both ]; then
		plan_codex_setup
	fi

	if [ "$setup_trash" = true ]; then
		if [ ! -e "$HOME/.local/bin" ] && [ ! -L "$HOME/.local/bin" ]; then
			plan_change "Directories" "Create $(display_path "$HOME/.local/bin")"
		fi
		plan_link_path "$REPO_DIR/src/bin/trash" "$HOME/.local/bin/trash"
	fi
	if [ "$setup_core" = true ]; then
		hooks_path=$(git -C "$REPO_DIR" config --get core.hooksPath 2>/dev/null || true)
		if [ "$hooks_path" != src/hooks/git ]; then
			plan_change "Git hooks" "Set core.hooksPath to src/hooks/git in this checkout"
		fi
	fi
}

# Records one change under the kind printed in the preview.
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

# Prints the collected changes grouped by the part of setup they affect, in a
# fixed section order. Prints nothing when there are no changes.
print_setup_plan() {
	# The section currently being printed.
	local kind
	# One recorded change, stored as "kind|description".
	local item

	if [ "$plan_count" -eq 0 ]; then
		return
	fi

	for kind in "Directories" "Backups" "Links" "Helper commands" "Codex settings" "HCOM" "Selection" "Git hooks"; do
		# Whether this section contains at least one planned change.
		local shown=false
		for item in "${plan_items[@]}"; do
			if [ "${item%%|*}" != "$kind" ]; then
				continue
			fi

			if [ "$shown" = false ]; then
				printf '\n%s:\n' "$kind"
				shown=true
			fi

			printf '  - %s\n' "${item#*|}"
		done
	done
}

# Adds the Claude folders, links, stale links and missing helper commands to the
# setup preview.
plan_claude_setup() {
	# The managed folder or generated file currently being checked.
	local file
	# The helper command currently being checked.
	local command_name

	plan_container_dir "$CLAUDE_DIR"
	plan_container_dir "$CLAUDE_DIR/skills"
	if [ "$setup_core" = true ]; then
		plan_container_dir "$CLAUDE_DIR/rules"
	fi
	if [ "$setup_hooks" = true ]; then
		plan_container_dir "$CLAUDE_DIR/hooks"
	fi
	if [ "$setup_themes" = true ]; then
		plan_container_dir "$CLAUDE_DIR/themes"
	fi

	if [ "$setup_helpers" = true ]; then
		while IFS= read -r command_name; do
			plan_helper_command "$command_name"
		done < <(required_agent_tools claude)
	fi

	if [ "$setup_core" = true ]; then
		for file in "${CLAUDE_FILES[@]}"; do
			if [ "$file" = settings.json ] && [ "$setup_hooks" = false ]; then
				continue
			fi
			plan_link_path "$REPO_DIR/dist/claude/$file" "$CLAUDE_DIR/$file"
		done
	fi

	plan_prune_stale_repo_links "$CLAUDE_DIR/skills" "$REPO_DIR"
	if [ "${#excluded_skills[@]}" -gt 0 ]; then
		plan_skill_links "$CLAUDE_DIR/skills" "${excluded_skills[@]}"
	else
		plan_skill_links "$CLAUDE_DIR/skills"
	fi

	if [ "$setup_hooks" = true ]; then
		plan_prune_stale_repo_links "$CLAUDE_DIR/hooks" "$REPO_DIR/dist/claude/hooks"
		for file in "$REPO_DIR"/dist/claude/hooks/*; do
			[ -f "$file" ] || continue
			plan_link_path "$file" "$CLAUDE_DIR/hooks/${file##*/}"
		done
	fi

	if [ "$setup_themes" = true ]; then
		plan_prune_stale_repo_links "$CLAUDE_DIR/themes" "$REPO_DIR/dist/claude/themes"
		for file in "$REPO_DIR"/dist/claude/themes/*.json; do
			[ -f "$file" ] || continue
			plan_link_path "$file" "$CLAUDE_DIR/themes/${file##*/}"
		done
	fi

	if [ "$setup_core" = true ]; then
		plan_prune_stale_repo_links "$CLAUDE_DIR/rules" "$REPO_DIR/dist/claude/rules"
		for file in "$REPO_DIR"/dist/claude/rules/*.md; do
			[ -f "$file" ] || continue
			plan_link_path "$file" "$CLAUDE_DIR/rules/${file##*/}"
		done
	fi
}

# Adds the install of a missing agent-tools command to the setup preview. A
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
# missing helper commands to the setup preview.
plan_codex_setup() {
	# The managed folder or generated file currently being checked.
	local file
	# The helper command currently being checked.
	local command_name
	# The position of the current managed Codex link.
	local index
	# The Codex config setup would write, compared with the user's current file.
	local config_temp
	# The settings the preview says the Codex config will hold.
	local config_description
	# The position of the last setting named in the config description.
	local last_item

	plan_container_dir "$HOME/.agents"
	plan_container_dir "$HOME/.agents/skills"
	if [ "$setup_core" = true ]; then
		plan_container_dir "$CODEX_DIR"
	fi
	if [ "$setup_hooks" = true ]; then
		plan_container_dir "$CODEX_DIR/hooks"
	fi

	if [ "$setup_helpers" = true ]; then
		while IFS= read -r command_name; do
			plan_helper_command "$command_name"
		done < <(required_agent_tools codex)
	fi

	if [ "$setup_core" = true ]; then
		for index in "${!CODEX_LINK_SOURCES[@]}"; do
			plan_link_path "${CODEX_LINK_SOURCES[$index]}" "${CODEX_LINK_TARGETS[$index]}"
		done
	fi
	if [ "$setup_hooks" = true ]; then
		plan_link_path "$CODEX_HOOKS_SOURCE" "$CODEX_HOOKS_TARGET"
		plan_prune_stale_repo_links "$CODEX_DIR/hooks" "$REPO_DIR/dist/codex/hooks"
		for file in "$REPO_DIR"/dist/codex/hooks/*; do
			[ -f "$file" ] || continue
			plan_link_path "$file" "$CODEX_DIR/hooks/${file##*/}"
		done
	fi

	if [ "$setup_core" = true ]; then
		config_temp=$(mktemp)
		prepare_codex_config "$CODEX_DIR/config.toml" "$config_temp"
		if [ ! -f "$CODEX_DIR/config.toml" ] || ! cmp -s "$CODEX_DIR/config.toml" "$config_temp"; then
			if [ -e "$CODEX_DIR/config.toml" ] || [ -L "$CODEX_DIR/config.toml" ]; then
				plan_backup "$CODEX_DIR/config.toml"
			fi
			# The Codex settings included in the planned config update.
			local -a config_items=('managed defaults' 'MCP servers' 'TUI settings')
			if [ "$setup_permissions" = true ]; then
				config_items+=('the permission profile')
			fi
			if [ "$setup_hooks" = true ]; then
				config_items+=('hooks')
			fi
			last_item=$((${#config_items[@]} - 1))
			config_description=$(printf '%s, ' "${config_items[@]:0:$last_item}")
			config_description="${config_description%, } and ${config_items[$last_item]}"
			plan_change "Codex settings" "Write $(display_path "$CODEX_DIR/config.toml") with $config_description"
		fi
		rm "$config_temp"
	fi

	plan_prune_stale_repo_links "$HOME/.agents/skills" "$REPO_DIR"
	plan_prune_stale_repo_links "$CODEX_DIR/skills" "$REPO_DIR" 1
	if [ "${#excluded_skills[@]}" -gt 0 ]; then
		plan_skill_links "$HOME/.agents/skills" "${excluded_skills[@]}"
	else
		plan_skill_links "$HOME/.agents/skills"
	fi

	if [ "$setup_hcom" = true ]; then
		plan_hcom_folders
	fi
}

# Adds the folders that setup will append to HCOM's Codex arguments to the
# setup preview. ~/.agents is listed even before it exists, because setup
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

# Parses a comma-separated skill list into the pending setup operations.
#
# @param  {string}  operation
#     Operation to apply to each listed skill.
# @param  {string}  value
#     Comma-separated skill names supplied on the command line.
parse_skill_list() {
	# The include or exclude action applied to each requested skill.
	local operation="$1"
	# The comma-separated skill names supplied on the command line.
	local value="$2"
	# The current skill name, trimmed before it is queued with its action.
	local skill_name
	# The individual skill names supplied in this option.
	local -a names=()

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

# Prints the options this script accepts.
usage() {
	printf 'Usage: %s [--preset skills-only|pick|everything] [--claude|--codex|--both] [--claude-dir <path>] [--codex-dir <path>] [--select] [--exclude <skill>[,<skill>...]] [--include <skill>[,<skill>...]] [--include-all] [--status] [--refresh] [--yes]\n' "$(basename "$0")"
}

# Rejects unknown exclusions and includes unless an include clears a saved name.
#
# @return  {integer}
#     0 when every requested skill name is known, or 1 otherwise.
validate_skill_operations() {
	# The position of the skill operation currently being validated.
	local index
	# The skill name checked against canonical and saved exclusions.
	local skill_name
	# The include or exclude action associated with this skill name.
	local operation

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

# Returns 0 when a canonical skill folder has the requested name.
#
# @param  {string}  requested_name
#     Skill name to find in the canonical skills directory.
canonical_skill_exists() {
	# The skill name being looked up among canonical skill folders.
	local requested_name="$1"
	# The canonical skill folder compared with the requested name.
	local skill

	for skill in "$REPO_DIR"/skills/*/*; do
		[ -d "$skill" ] || continue
		if [ "$(basename "$skill")" = "$requested_name" ]; then
			return 0
		fi
	done

	return 1
}

# Returns success when fzf is 0.74 or newer, the first release with the Tab
# actions the picker uses. fzf prints build details after the version, such as
# "0.74.5 (Homebrew)", so only the leading version number is read.
#
# @param  {string}  version
#     The output of fzf --version.
fzf_supports_picker_actions() {
	# The version reported by fzf.
	local version="$1"
	# The major version number.
	local major
	# The minor version number.
	local minor

	if [[ ! $version =~ ^([0-9]+)\.([0-9]+)\.[0-9]+($|[[:space:]]|-) ]]; then
		return 1
	fi

	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	[ "$major" -gt 0 ] || [ "$minor" -ge 74 ]
}

# Selects included skills with fzf and updates the exclusions from its output.
#
# @return  {integer}
#     0 when fzf returns a selection, or 1 when the selection is cancelled.
select_skills_with_fzf() {
	# The fzf actions run when the list loads. fzf cannot preselect rows, so these
	# walk down the list once, ticking each included skill, then return to the top.
	local fzf_bind='load:'
	# The selection instructions displayed above the fzf skill list.
	local fzf_header='Tab toggles a skill or collection, Enter confirms, Esc cancels. Ticked skills are installed.'
	# The ticked rows returned by fzf.
	local selected_output
	# The temporary script fzf runs when Tab is pressed.
	local picker_script
	# The temporary file containing every picker row, including rows hidden by a search.
	local picker_rows
	# Whether fzf returned a selection or was cancelled.
	local fzf_status=0
	# The canonical skill folder currently added to the fzf list.
	local skill_path
	# The current skill name, used to preselect its row and recover each selection.
	local skill_name
	# Whether a row returned by fzf is a heading or a skill.
	local row_kind
	# The collection the current skill belongs to.
	local collection_name=''
	# The number of skills in the current collection.
	local collection_count=0
	# The previous collection, used to insert one heading per collection.
	local previous_collection=''
	# The width of the longest skill name, used to align descriptions.
	local name_width
	# The rows shown in fzf: a heading for each collection, followed by its skills.
	local -a skill_entries=()
	# The canonical skill names left selected after the fzf prompt closes.
	local -a selected_skills=()

	name_width=$(picker_name_width)
	for skill_path in "${skill_paths[@]}"; do
		collection_name=$(picker_collection_of "$skill_path")
		if [ "$collection_name" != "$previous_collection" ]; then
			collection_count=$(picker_collection_count "$collection_name")
			skill_entries+=("heading"$'\t'"$collection_name"$'\t'"$collection_name ($collection_count)")
			fzf_bind="${fzf_bind}down+"
			previous_collection="$collection_name"
		fi

		skill_name=$(basename "$skill_path")
		skill_entries+=("skill"$'\t'"$skill_name"$'\t'"$(picker_entry "$skill_path" '  ' 0 "$name_width" true)")
		if skill_is_selected "$skill_path"; then
			fzf_bind="${fzf_bind}toggle+"
		fi
		fzf_bind="${fzf_bind}down+"
	done
	fzf_bind="${fzf_bind}first"

	# fzf runs the Tab command in a fresh shell that cannot see this script's
	# functions, so the handler and every row go in files that last until the
	# picker closes.
	picker_script=$(mktemp)
	picker_rows=$(mktemp)
	{
		declare -f picker_tab_actions
		# The arguments belong to the Tab script, so they must stay unexpanded here.
		# shellcheck disable=SC2016
		printf '%s\n' 'picker_tab_actions "$1" "$2" "$3"'
	} > "$picker_script"
	printf '%s\n' "${skill_entries[@]}" > "$picker_rows"

	# fzf fills in {} with the current row and {+f} with the ticked rows when
	# Tab is pressed. The handler runs under this script's Bash interpreter.
	selected_output=$(printf '%s\n' "${skill_entries[@]}" | fzf --ansi --layout=reverse --multi --delimiter=$'\t' --with-nth=3 --header "$fzf_header" --bind "$fzf_bind" --bind "tab:transform('$BASH' '$picker_script' '$picker_rows' {} {+f})") || fzf_status=$?
	trash "$picker_script" "$picker_rows"
	if [ "$fzf_status" -ne 0 ]; then
		return 1
	fi

	while IFS=$'\t' read -r row_kind skill_name _; do
		if [ "$row_kind" = skill ]; then
			selected_skills+=("$skill_name")
		fi
	done <<< "$selected_output"

	# macOS Bash 3.2 treats an empty array expansion as unset under set -u.
	if [ "${#selected_skills[@]}" -gt 0 ]; then
		set_exclusions_from_selected_skills "${selected_skills[@]}"
	else
		set_exclusions_from_selected_skills
	fi
}

# Prints the fzf actions for a Tab press. On a skill row, Tab toggles that skill
# and moves down. On a collection heading, Tab ticks every skill in the
# collection, or unticks them all when all are already ticked. It clears the
# search first so skills the search hides are included, then returns the cursor
# to the heading.
#
# @param  {string}  rows_file
#     The file containing every picker row.
# @param  {string}  current_row
#     The row under the cursor.
# @param  {string}  selected_file
#     A file from fzf listing ticked rows, or the current row when none is ticked.
picker_tab_actions() {
	# The file containing every picker row, including rows hidden by a search.
	local rows_file="$1"
	# The row under the cursor, which may be a collection heading.
	local current_row="$2"
	# The file listing the ticked rows.
	local selected_file="$3"
	# The kind of the row under the cursor.
	local current_kind="${current_row%%$'\t'*}"
	# The picker row being read.
	local row
	# The kind of the row being read.
	local row_kind
	# The skill name in the row's second field.
	local skill_name
	# The position of the row being read, counted from 1 as fzf's pos action does.
	local position=0
	# The position of the heading to restore after changing its skills.
	local heading_position=0
	# Whether a skill in the collection is currently unticked.
	local any_unticked=false
	# The positions of skills under the heading.
	local -a positions=()

	if [ "$current_kind" != heading ]; then
		printf 'toggle+down\n'
		return
	fi

	while IFS= read -r row; do
		position=$((position + 1))
		row_kind="${row%%$'\t'*}"
		if [ "$row" = "$current_row" ]; then
			heading_position=$position
			continue
		fi
		if [ "$heading_position" -eq 0 ]; then
			continue
		fi
		if [ "$row_kind" = heading ]; then
			break
		fi
		positions+=("$position")
		skill_name="${row#*$'\t'}"
		skill_name="${skill_name%%$'\t'*}"
		if ! grep -Fq $'skill\t'"$skill_name"$'\t' "$selected_file"; then
			any_unticked=true
		fi
	done < "$rows_file"

	printf 'clear-query+wait'
	for position in "${positions[@]}"; do
		if [ "$any_unticked" = true ]; then
			printf '+pos(%s)+select' "$position"
		else
			printf '+pos(%s)+deselect' "$position"
		fi
	done
	printf '+pos(%s)\n' "$heading_position"
}

# Prints the number of canonical skills in a collection.
#
# @param  {string}  collection_name
#     The collection folder name.
picker_collection_count() {
	# The collection being counted.
	local collection_name="$1"
	# The skill path inspected for the collection.
	local skill_path
	# The count of skills in the collection.
	local count=0

	for skill_path in "${skill_paths[@]}"; do
		if [ "${skill_path%/*}" = "$REPO_DIR/skills/$collection_name" ]; then
			count=$((count + 1))
		fi
	done
	printf '%s\n' "$count"
}

# Prints the length of the longest skill name in the picker.
picker_name_width() {
	# The canonical skill path currently measured.
	local skill_path
	# The current skill name.
	local skill_name
	# The longest name length found so far.
	local name_width=0

	for skill_path in "${skill_paths[@]}"; do
		skill_name="${skill_path##*/}"
		if [ "${#skill_name}" -gt "$name_width" ]; then
			name_width=${#skill_name}
		fi
	done
	printf '%s\n' "$name_width"
}

# Prints one picker row with an aligned name and its description, dimmed on request.
# The numbered list shortens or drops the description to fit the terminal.
#
# @param  {string}  skill_path
#     The canonical skill folder to display.
# @param  {string}  prefix
#     The tick box and number in the numbered picker, or the gap after fzf's marker.
# @param  {integer}  width
#     The numbered row width, or zero to leave truncation to fzf.
# @param  {integer}  name_width
#     The width of the longest skill name.
# @param  {boolean}  dim_description
#     Whether to dim the description.
picker_entry() {
	# The skill folder shown in the picker.
	local skill_path="$1"
	# The text printed before the skill name.
	local prefix="$2"
	# The maximum number of columns available.
	local width="$3"
	# The width reserved for the skill name.
	local name_width="$4"
	# Whether the description should use dim text.
	local dim_description="$5"
	# The skill name shown in the picker.
	local skill_name
	# The description shown beside the skill name.
	local description
	# The full row before it is shortened.
	local entry

	skill_name=$(basename "$skill_path")
	description=$(picker_description "$skill_path")
	entry="$prefix$skill_name"
	if [ -n "$description" ]; then
		printf -v entry '%s%-*s  ' "$prefix" "$name_width" "$skill_name"
		if [ "$width" -gt 0 ] && [ "$(( ${#entry} + 1 ))" -ge "$width" ]; then
			printf '%s\n' "$prefix$skill_name"
			return
		fi
		if [ "$width" -gt 0 ] && [ "$(( ${#entry} + ${#description} ))" -gt "$width" ]; then
			# A byte locale can cut a UTF-8 character in half. Drop any incomplete
			# trailing character before adding the ellipsis.
			description=$(printf '%s' "${description:0:$((width - ${#entry} - 1))}" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || true)
			description="${description}…"
		fi
		if [ "$dim_description" = true ] && [ -z "${NO_COLOR+x}" ]; then
			entry="${entry}"$'\033[2m'"${description}"$'\033[22m'
		else
			entry="$entry$description"
		fi
	fi
	printf '%s\n' "$entry"
}

# Prints a skill's frontmatter description on one line, without surrounding
# quotes or a leading "Use this skill", and with the first letter capitalised.
# Prints nothing when the skill has no SKILL.md or description. Handles
# single-line values and folded blocks
# (`description: >` followed by indented lines), the same format that
# scripts/build/build-docs.py reads, without making setup depend on Python.
#
# @param  {string}  skill_path
#     The canonical skill folder whose SKILL.md is read.
picker_description() {
	# The skill folder whose description is read.
	local skill_path="$1"
	# The frontmatter description after joining its lines.
	local description

	[ -f "$skill_path/SKILL.md" ] || return 0

	# Reads only the frontmatter between the opening and closing --- lines, and
	# joins the indented lines of a folded description with single spaces.
	description=$(awk '
		NR == 1 { if ($0 != "---") exit; next }
		$0 == "---" { exit }
		/^description:[[:space:]]*/ {
			sub(/^description:[[:space:]]*/, "")
			if ($0 ~ /^[>|][-+]?[[:space:]]*$/) { folded = 1; next }
			print
			exit
		}
		folded && (/^[[:space:]]/ || $0 == "") {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "")
			if ($0 != "") printf "%s%s", separator, $0
			if ($0 != "") separator = " "
			next
		}
		folded { exit }
	' "$skill_path/SKILL.md" | sed -E "s/^'(.*)'$/\1/; s/^\"(.*)\"$/\1/; s/^Use this skill[[:space:]]+//; s/[[:space:]]+/ /g; s/[[:space:]]+$//" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')
	printf '%s\n' "$description"
}

# Replaces the saved choices with the picker's selection. Choosing any skill in a
# default-off collection opts that collection in. Unchosen skills are saved as
# exclusions only in collections that are on, so the exclusions file never
# lists skills from a collection that is off. The caller must have collected
# skill_paths.
#
# @param  {string}  ...
#     Canonical skill names selected for installation.
set_exclusions_from_selected_skills() {
	# The selected skill compared against each canonical skill.
	local selected_skill
	# The canonical skill folder whose inclusion is being checked.
	local skill_path
	# The canonical skill name checked against the selection.
	local skill_name
	# Whether the canonical skill remains selected.
	local selected=false
	# The collection containing the current skill.
	local collection_name

	excluded_skills=()
	included_collections=()
	for skill_path in "${skill_paths[@]}"; do
		collection_name=$(picker_collection_of "$skill_path")
		if ! default_off_collection_exists "$collection_name"; then
			continue
		fi
		for selected_skill in "$@"; do
			if [ "$selected_skill" = "${skill_path##*/}" ] && ! included_collection_exists "$collection_name"; then
				included_collections+=("$collection_name")
				break
			fi
		done
	done
	for skill_path in "${skill_paths[@]}"; do
		skill_name=$(basename "$skill_path")
		collection_name=$(picker_collection_of "$skill_path")
		selected=false
		for selected_skill in "$@"; do
			if [ "$selected_skill" = "$skill_name" ]; then
				selected=true
				break
			fi
		done

		if [ "$selected" = false ] && ! collection_is_off "$collection_name"; then
			excluded_skills+=("$skill_name")
		fi
	done
}

# Selects skills from a numbered terminal list, where each entered number or
# collection name flips the ticks shown, and updates the saved choices.
#
# @return  {integer}
#     0 when entries are accepted, 1 when cancelled, or 2 for an invalid entry.
select_skills_with_numbered_list() {
	# The user's response to the numbered skill selector.
	local selection
	# The position of the current skill in the numbered list.
	local index
	# The number or collection name currently being validated.
	local toggled_entry
	# Whether the current canonical skill remains selected.
	local keep_skill=false
	# The current skill name displayed in the numbered list.
	local skill_name
	# The collection of the current skill.
	local collection_name
	# The collection displayed on the previous row.
	local previous_collection=''
	# The terminal width used to shorten each displayed entry.
	local picker_width
	# The width of the longest skill name, used to align descriptions.
	local name_width
	# The number of canonical skills in the picker.
	local skill_count
	# The number of digits in the final skill number.
	local number_width
	# Whether descriptions may be dimmed in this output.
	local dim_description=false
	# The selection marker and number printed before a skill name.
	local prefix
	# The skill numbers or collection names the user chose to toggle.
	local -a toggled_entries=()
	# The canonical skill names retained by the numbered selector.
	local -a selected_skills=()

	picker_width=$(picker_terminal_width)
	name_width=$(picker_name_width)
	skill_count=${#skill_paths[@]}
	number_width=${#skill_count}
	if [ -t 1 ]; then
		dim_description=true
	fi
	for index in "${!skill_paths[@]}"; do
		collection_name=$(picker_collection_of "${skill_paths[$index]}")
		if [ "$collection_name" != "$previous_collection" ]; then
			printf '\n%s (%s)\n' "$collection_name" "$(picker_collection_count "$collection_name")"
			previous_collection="$collection_name"
		fi
		skill_name=$(basename "${skill_paths[$index]}")
		if ! skill_is_selected "${skill_paths[$index]}"; then
			printf -v prefix '[ ] %*d. ' "$number_width" "$((index + 1))"
		else
			printf -v prefix '[x] %*d. ' "$number_width" "$((index + 1))"
		fi
		picker_entry "${skill_paths[$index]}" "$prefix" "$picker_width" "$name_width" "$dim_description"
	done

	printf 'Enter skill numbers or collection names to toggle, separated by spaces (or q to cancel): '
	if ! read -r selection; then
		return 1
	fi

	if [ "$selection" = 'q' ]; then
		return 1
	fi

	read -r -a toggled_entries <<< "$selection"
	if [ "${#toggled_entries[@]}" -gt 0 ]; then
		for toggled_entry in "${toggled_entries[@]}"; do
			if [[ "$toggled_entry" =~ ^[1-9][0-9]*$ ]]; then
				if [ "$toggled_entry" -gt "${#skill_paths[@]}" ]; then
					printf 'Invalid skill number: %s\n' "$toggled_entry" >&2
					return 2
				fi
			elif [ "$(picker_collection_count "$toggled_entry")" -eq 0 ]; then
				printf 'Invalid skill number or collection: %s\n' "$toggled_entry" >&2
				return 2
			fi
		done
	fi

	for index in "${!skill_paths[@]}"; do
		if skill_is_selected "${skill_paths[$index]}"; then
			keep_skill=true
		else
			keep_skill=false
		fi
		collection_name=$(picker_collection_of "${skill_paths[$index]}")
		if [ "${#toggled_entries[@]}" -gt 0 ]; then
			for toggled_entry in "${toggled_entries[@]}"; do
				if [ "$toggled_entry" = "$collection_name" ] || [ "$toggled_entry" = "$((index + 1))" ]; then
					if [ "$keep_skill" = true ]; then
						keep_skill=false
					else
						keep_skill=true
					fi
					break
				fi
			done
		fi

		if [ "$keep_skill" = true ]; then
			selected_skills+=("$(basename "${skill_paths[$index]}")")
		fi
	done

	# macOS Bash 3.2 treats an empty array expansion as unset under set -u.
	if [ "${#selected_skills[@]}" -gt 0 ]; then
		set_exclusions_from_selected_skills "${selected_skills[@]}"
	else
		set_exclusions_from_selected_skills
	fi
}

# Prints the terminal width, using COLUMNS, /dev/tty, then 80.
picker_terminal_width() {
	# The terminal dimensions reported directly by stty.
	local terminal_size
	# The column count extracted from the terminal dimensions.
	local terminal_width

	if [[ ${COLUMNS:-} =~ ^[0-9]+$ ]] && [ "$COLUMNS" -gt 0 ]; then
		printf '%s\n' "$COLUMNS"
		return
	fi

	if terminal_size=$(stty size 2>/dev/null < /dev/tty); then
		terminal_width="${terminal_size##* }"
		if [[ $terminal_width =~ ^[0-9]+$ ]] && [ "$terminal_width" -gt 0 ]; then
			printf '%s\n' "$terminal_width"
			return
		fi
	fi

	printf '80\n'
}

# Writes the current exclusions, removing the file when no exclusions remain.
save_skill_exclusions() {
	# The excluded skill name currently saved to the selection file.
	local skill_name
	# The temporary file used to replace the saved exclusions atomically.
	local temp

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

# Writes selected default-off collections, removing the file when none remain.
save_skill_inclusions() {
	# A selected collection written to the saved file.
	local collection_name
	# The temporary file used to replace the saved inclusions.
	local temp

	if [ "${#included_collections[@]}" -eq 0 ]; then
		if [ -e "$skill_inclusions_file" ] || [ -L "$skill_inclusions_file" ]; then
			trash "$skill_inclusions_file"
		fi
		return 0
	fi

	mkdir -p "$HOME/.agents"
	temp=$(mktemp)
	for collection_name in "${included_collections[@]}"; do
		printf '%s\n' "$collection_name" >> "$temp"
	done
	mv "$temp" "$skill_inclusions_file"
}

# Applies the validated skill operations in their command-line order.
apply_skill_operations() {
	# The position of the pending skill operation being applied.
	local index
	# The include or exclude action currently being applied.
	local operation
	# The skill name affected by the current action.
	local skill_name

	if [ "${#skill_operation_types[@]}" -eq 0 ]; then
		return 0
	fi

	for index in "${!skill_operation_types[@]}"; do
		operation="${skill_operation_types[$index]}"
		skill_name="${skill_operation_names[$index]}"
		case "$operation" in
			exclude) add_excluded_skill "$skill_name" ;;
			include)
				remove_excluded_skill "$skill_name"
				include_skill_collection "$skill_name"
				;;
			include-all)
				excluded_skills=()
				included_collections=("${default_off_collections[@]}")
				;;
		esac
	done
}

# Opts in the default-off collection containing an included skill.
#
# @param  {string}  skill_name
#     The skill explicitly included on the command line.
include_skill_collection() {
	# The included skill name.
	local skill_name="$1"
	# A canonical skill folder compared with the included name.
	local skill_path
	# The collection containing the included skill.
	local collection_name

	for skill_path in "$REPO_DIR"/skills/*/*; do
		[ -d "$skill_path" ] || continue
		[ "${skill_path##*/}" = "$skill_name" ] || continue
		collection_name=$(picker_collection_of "$skill_path")
		if default_off_collection_exists "$collection_name" && ! included_collection_exists "$collection_name"; then
			included_collections+=("$collection_name")
		fi
		return
	done
}

# Adds a skill name to the current exclusion list once.
#
# @param  {string}  skill_name
#     Skill name to exclude from future setup runs.
add_excluded_skill() {
	# The skill name to add to the exclusion list.
	local skill_name="$1"

	if ! excluded_skill_exists "$skill_name"; then
		excluded_skills+=("$skill_name")
	fi
}

# Removes a skill name from the current exclusion list.
#
# @param  {string}  skill_name
#     Skill name to include in future setup runs.
remove_excluded_skill() {
	# The skill name to remove from the exclusion list.
	local skill_name="$1"
	# The exclusion currently checked against the requested name.
	local excluded_skill
	# The exclusions kept after the requested skill is removed.
	local -a remaining_skills=()

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

# Tells the user which skills this run skips and where that list is saved,
# so a missing skill is explained rather than looking like a broken install.
report_excluded_skills() {
	# The exclusion names joined for the terminal report.
	local formatted

	if [ "${#excluded_skills[@]}" -eq 0 ]; then
		return 0
	fi

	formatted=$(format_excluded_skills)
	printf 'Excluded: %s (from ~/.agents/skill-exclusions; run with --include-all to restore)\n' "$formatted"
}

# Joins the current exclusions into one comma-separated list for output.
format_excluded_skills() {
	# The exclusion names joined for the terminal report.
	local formatted=''
	# The excluded skill name currently appended to the report.
	local skill_name

	for skill_name in "${excluded_skills[@]}"; do
		if [ -n "$formatted" ]; then
			formatted="$formatted, $skill_name"
		else
			formatted="$skill_name"
		fi
	done

	printf '%s' "$formatted"
}

# Asks which preset to use and prints skills-only, pick, everything or
# cancelled. Returns 1 when the answer is not one of the choices.
prompt_preset() {
	# The preset number entered at the terminal prompt.
	local choice
	printf 'Choose a setup preset: [1] Skills only  [2] Pick features  [3] Everything (or q to cancel): ' >&2
	IFS= read -r choice || return 1
	case "$choice" in
		1) printf 'skills-only' ;;
		2) printf 'pick' ;;
		3) printf 'everything' ;;
		q|Q) printf 'cancelled' ;;
		*) printf 'Invalid preset.\n' >&2; return 1 ;;
	esac
}

# Asks which optional features to install and turns off each one the user
# leaves out. Claude-only runs do not offer the two Codex features, so the
# numbers depend on the target. Exits without changes when the user cancels,
# or returns 1 for an unknown feature number.
pick_setup_features() {
	# The selected feature numbers entered at the terminal prompt.
	local answer
	# The selected numbers split without expanding filename patterns.
	local -a selected_numbers=()
	# The features offered to the selected target, with their display names.
	local -a offered_features=('hooks:Hooks')
	# The feature number currently displayed or applied.
	local number
	# The internal name and display name of the current feature.
	local feature
	# The space printed before each numbered choice.
	local separator=' '

	setup_hooks=false setup_permissions=false setup_hcom=false
	setup_themes=false setup_trash=false setup_helpers=false
	if [ "$target" != claude ]; then
		offered_features+=('permissions:Codex permission profile' 'hcom:HCOM additions')
	fi
	offered_features+=('themes:Themes' 'trash:Trash wrapper' 'helpers:Helper commands')

	printf 'Choose features:'
	for number in "${!offered_features[@]}"; do
		feature="${offered_features[$number]}"
		printf '%s[%d] %s' "$separator" "$((number + 1))" "${feature#*:}"
		separator='  '
	done
	printf '\n'
	printf 'Enter feature numbers separated by spaces (all for everything, q to cancel): '
	IFS= read -r answer || return 1
	case "$answer" in
		q|Q) printf '%s\n' 'Setup cancelled. Nothing changed.'; exit 0 ;;
		all)
			answer=''
			for number in "${!offered_features[@]}"; do
				answer="$answer $((number + 1))"
			done
			;;
	esac
	read -r -a selected_numbers <<< "$answer"
	# Choosing no numbers keeps every optional feature off. Return before the
	# loop because Bash 3.2 treats an empty array as unset under set -u.
	[ "${#selected_numbers[@]}" -gt 0 ] || return 0
	for number in "${selected_numbers[@]}"; do
		# Only 1 to 6 are looked up, so 0 cannot select the last feature through
		# index -1 and text is never evaluated as arithmetic. A number past the
		# offered list, such as 5 on a Claude-only run, is rejected.
		case "$number" in
			[1-6]) feature="${offered_features[$((number - 1))]:-}" ;;
			*) feature='' ;;
		esac
		if [ -z "$feature" ]; then
			printf 'Unknown feature number: %s\n' "$number" >&2
			return 1
		fi
		case "${feature%%:*}" in
			hooks) setup_hooks=true ;;
			permissions) setup_permissions=true ;;
			hcom) setup_hcom=true ;;
			themes) setup_themes=true ;;
			trash) setup_trash=true ;;
			helpers) setup_helpers=true ;;
		esac
	done
}

# Asks which agents to set up and prints claude, codex or both. The question
# goes to standard error so the caller captures only the answer.
prompt_target() {
	printf 'Which agent(s)? [1] Claude  [2] Codex  [3] Both: ' >&2
	# The agent selection entered at the terminal prompt.
	read -r choice

	case "$choice" in
		1) printf 'claude' ;;
		2) printf 'codex' ;;
		3) printf 'both' ;;
		*) printf 'Invalid choice.\n' >&2; exit 1 ;;
	esac
}

# Installs Claude's skill links, plus its main configuration, hooks, themes and
# helper commands when the matching setup_* flag is true.
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
	if [ "$setup_core" = true ]; then
		ensure_container_dir "$CLAUDE_DIR/rules" rules
	fi
	if [ "$setup_hooks" = true ]; then
		ensure_container_dir "$CLAUDE_DIR/hooks" hooks
	fi
	if [ "$setup_themes" = true ]; then
		ensure_container_dir "$CLAUDE_DIR/themes" themes
	fi
	cli_group_end

	if [ "$setup_helpers" = true ]; then
		cli_group_begin "Claude command-line tools"
		ensure_friction
		ensure_team_send
		ensure_doc_paths
		cli_group_end
	fi

	if [ "$setup_core" = true ]; then
		cli_group_begin "Claude files"
		for file in "${CLAUDE_FILES[@]}"; do
			if [ "$file" = settings.json ] && [ "$setup_hooks" = false ]; then
				continue
			fi
			link_path "$REPO_DIR/dist/claude/$file" "$CLAUDE_DIR/$file" "$file"
		done
		cli_group_end
	fi

	cli_group_begin "Claude skills"
	prune_stale_repo_links "$CLAUDE_DIR/skills" "$REPO_DIR" "skills"
	link_configured_skills "$CLAUDE_DIR/skills"
	cli_group_end

	if [ "$setup_hooks" = true ]; then
		cli_group_begin "Claude hooks"
		prune_stale_repo_links "$CLAUDE_DIR/hooks" "$REPO_DIR/dist/claude/hooks" "hooks"
		# The generated hook file currently being linked into Claude's configuration.
		local hook
		for hook in "$REPO_DIR"/dist/claude/hooks/*; do
			[ -f "$hook" ] || continue
			link_path "$hook" "$CLAUDE_DIR/hooks/$(basename "$hook")" "hooks/$(basename "$hook")"
		done
		cli_group_end
	fi

	if [ "$setup_themes" = true ]; then
		cli_group_begin "Claude themes"
		prune_stale_repo_links "$CLAUDE_DIR/themes" "$REPO_DIR/dist/claude/themes" "themes"
		# The generated theme file linked into Claude's configuration folder.
		local theme
		for theme in "$REPO_DIR"/dist/claude/themes/*.json; do
			[ -f "$theme" ] || continue
			link_path "$theme" "$CLAUDE_DIR/themes/$(basename "$theme")" "themes/$(basename "$theme")"
		done
		cli_group_end
	fi

	if [ "$setup_core" = true ]; then
		cli_group_begin "Claude rules"
		prune_stale_repo_links "$CLAUDE_DIR/rules" "$REPO_DIR/dist/claude/rules" "rules"
		# The generated rule file linked into Claude's configuration folder.
		local rule
		for rule in "$REPO_DIR"/dist/claude/rules/*.md; do
			[ -f "$rule" ] || continue
			link_path "$rule" "$CLAUDE_DIR/rules/$(basename "$rule")" "rules/$(basename "$rule")"
		done
		cli_group_end
	fi
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

# Links selected skills, removes links for user exclusions, and leaves links
# already present for default-off collections that have not been opted in to.
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
	# The collection containing the current skill.
	local collection_name
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
		if excluded_skill_exists "${skill_path##*/}"; then
			if is_repo_owned_link "$skill_path" "$skill_link"; then
				trash "$skill_link"
				cli_group_status warning "removed excluded skill" "skills/${skill_path##*/}"
			fi
			continue
		fi

		collection_name=$(picker_collection_of "$skill_path")
		if collection_is_off "$collection_name"; then
			continue
		fi

		link_path "$skill_path" "$skill_link" "skills/${skill_path##*/}"
	done
}

# Installs Codex's skill links, plus its main configuration, hooks, permission
# profile, HCOM folders and helper commands when the matching setup_* flag is true.
setup_codex() {
	# The managed Codex folder currently ensured by setup.
	local folder
	# The label displayed when a Codex folder needs replacement.
	local label
	# The position of the current managed Codex link.
	local index

	cli_section "Codex global setup ($(display_path "$CODEX_DIR"))"

	cli_group_begin "Codex directories"
	for folder in "$HOME/.agents" "$HOME/.agents/skills"; do
		label=$(display_path "$folder")
		ensure_container_dir "$folder" "$label"
	done
	if [ "$setup_core" = true ]; then
		ensure_container_dir "$CODEX_DIR" "$(display_path "$CODEX_DIR")"
	fi
	if [ "$setup_hooks" = true ]; then
		ensure_container_dir "$CODEX_DIR/hooks" hooks
	fi
	cli_group_end

	if [ "$setup_helpers" = true ]; then
		cli_group_begin "Codex command-line tools"
		ensure_team_send
		ensure_doc_paths
		cli_group_end
	fi

	if [ "$setup_core" = true ] || [ "$setup_hooks" = true ]; then
		cli_group_begin "Codex files"
		if [ "$setup_core" = true ]; then
			for index in "${!CODEX_LINK_SOURCES[@]}"; do
				link_path "${CODEX_LINK_SOURCES[$index]}" "${CODEX_LINK_TARGETS[$index]}" "${CODEX_LINK_LABELS[$index]}"
			done
		fi
		if [ "$setup_hooks" = true ]; then
			link_path "$CODEX_HOOKS_SOURCE" "$CODEX_HOOKS_TARGET" "$CODEX_HOOKS_LABEL"
			prune_stale_repo_links "$CODEX_DIR/hooks" "$REPO_DIR/dist/codex/hooks" "hooks"
			# The generated hook file currently being linked into Codex's configuration.
			local hook
			for hook in "$REPO_DIR"/dist/codex/hooks/*; do
				[ -f "$hook" ] || continue
				link_path "$hook" "$CODEX_DIR/hooks/$(basename "$hook")" "hooks/$(basename "$hook")"
			done
		fi
		if [ "$setup_core" = true ]; then
			ensure_codex_config
		fi
		cli_group_end
	fi

	cli_group_begin "Codex skills"
	prune_stale_repo_links "$HOME/.agents/skills" "$REPO_DIR" "skills"
	prune_stale_repo_links "$CODEX_DIR/skills" "$REPO_DIR" "legacy skills" "1"
	link_configured_skills "$HOME/.agents/skills"
	cli_group_end

	if [ "$setup_hcom" = true ]; then
		setup_hcom_codex_folders
	fi
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
