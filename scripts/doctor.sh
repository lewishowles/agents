#!/usr/bin/env bash
# Reports problems with the installed agent configuration without changing it.

set -euo pipefail

# The folder containing this command.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The checkout whose generated files should be installed.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=scripts/lib/require-bash.sh
source "$SCRIPT_DIR/lib/require-bash.sh"
# shellcheck source=scripts/lib/setup-links.sh
source "$SCRIPT_DIR/lib/setup-links.sh"
# shellcheck source=scripts/lib/setup-checks.sh
source "$SCRIPT_DIR/lib/setup-checks.sh"
# shellcheck source=scripts/lib/setup-selection.sh
source "$SCRIPT_DIR/lib/setup-selection.sh"

# The number of required checks that found a problem.
failed_checks=0
# A comparison file created by this run, removed when the doctor exits.
doctor_config_temp=""

trap cleanup_doctor EXIT

# Prints a report of install problems for each agent set up in this home.
# Returns 1 when a required item is missing or broken, and 2 for unknown
# arguments.
#
# @param  {string}  ...
#     Only --help, which prints the usage line.
main() {
	if [ "$#" -gt 0 ]; then
		if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
			printf 'Usage: scripts/doctor.sh\n'
			return 0
		fi
		printf 'Usage: scripts/doctor.sh\n' >&2
		return 2
	fi

	# Stop Python helpers from writing bytecode under the user's home.
	export PYTHONDONTWRITEBYTECODE=1
	# Stop Bun writing its transpiler cache under the user's home when cli-style
	# starts.
	export BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
	# The values below are read by the shared setup checks, so they are global.
	# The Claude configuration folder.
	CLAUDE_DIR="$HOME/.claude"
	# The Codex configuration folder.
	CODEX_DIR="$HOME/.codex"
	# The file listing skills the user excluded from setup.
	skill_exclusions_file="$HOME/.agents/skill-exclusions"
	# The file listing optional skill collections the user included.
	skill_inclusions_file="$HOME/.agents/skill-inclusions"
	# Collections that stay off unless the user includes them.
	default_off_collections=(apple)
	# The excluded skill names, filled in by load_skill_exclusions.
	excluded_skills=()
	# The included collections, filled in by load_skill_inclusions.
	included_collections=()
	# Whether setup adds the managed hooks to the Codex config.
	setup_hooks=false
	# Whether setup writes the managed permission profile.
	setup_permissions=false
	# Whether this home contains a visible Claude installation.
	local claude_found=false
	# Whether this home contains a visible Codex installation.
	local codex_found=false
	# The agents set up in this home: claude, codex, both, or empty for neither.
	local target

	# shellcheck source=scripts/lib/cli-style-output.sh
	source "$SCRIPT_DIR/lib/cli-style-output.sh"
	load_skill_exclusions
	load_skill_inclusions
	cli_section 'Agent configuration doctor'

	if agent_is_present claude; then
		claude_found=true
	fi
	if agent_is_present codex; then
		codex_found=true
	fi
	if [ "$claude_found" = false ]; then
		cli_status skipped 'Claude' 'not set up'
	fi
	if [ "$codex_found" = false ]; then
		cli_status skipped 'Codex' 'not set up'
	fi

	target=''
	if [ "$claude_found" = true ] && [ "$codex_found" = true ]; then
		target=both
	elif [ "$claude_found" = true ]; then
		target=claude
	elif [ "$codex_found" = true ]; then
		target=codex
	fi
	check_tools "$target"
	if [ -n "$target" ]; then
		if [ "$claude_found" = true ]; then
			check_claude_links
		fi
		if [ "$codex_found" = true ]; then
			check_codex_links
			check_codex_config
		fi
		check_optional_link "$REPO_DIR/src/bin/trash" "$HOME/.local/bin/trash" 'trash wrapper'
		if ! report_skill_status "$target"; then
			# The skill report fails when two skills share a name and has already
			# printed that error, so only count it here.
			failed_checks=$((failed_checks + 1))
		fi
	fi
	check_git_hooks

	if [ "$failed_checks" -gt 0 ]; then
		cli_status error "$failed_checks required check(s) failed"
		return 1
	fi
	cli_status success 'No required problems found'
}

# Removes a comparison file if a check exits before normal cleanup.
cleanup_doctor() {
	if [ -n "$doctor_config_temp" ]; then
		rm -f "$doctor_config_temp"
	fi
}

# Returns success when a core link points into this checkout.
#
# @param  {string}  agent
#     The agent to detect.
agent_is_present() {
	# The agent whose installed paths are inspected.
	local agent="$1"
	case "$agent" in
		claude)
			is_repo_owned_link "$REPO_DIR/dist/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
			;;
		codex)
			is_repo_owned_link "$REPO_DIR/dist/codex/AGENTS.md" "$HOME/.agents/AGENTS.md" ||
				is_repo_owned_link "$REPO_DIR/dist/codex/AGENTS.md" "$CODEX_DIR/AGENTS.md"
			;;
	esac
}

# Reports cli-style, then the helper commands the selected agents use and fzf,
# hcom and uv. A missing cli-style fails the doctor, because setup installs it.
# A missing helper or tool shows as not installed and does not fail the doctor,
# because not every user needs them.
#
# @param  {string}  target
#     The agents to check: claude, codex or both. Empty checks only cli-style,
#     fzf, hcom and uv.
check_tools() {
	# The agents to check.
	local target="$1"
	# The command currently being checked.
	local command_name
	cli_section 'Commands'
	if cli_style_install_needed; then
		required_problem 'cli-style' 'missing; run: bun add -g @lewishowles/cli-style (or npm install -g @lewishowles/cli-style)'
	else
		cli_status success 'cli-style' 'installed'
	fi
	while IFS= read -r command_name; do
		if command -v "$command_name" >/dev/null 2>&1; then
			cli_status success "$command_name" 'installed'
		else
			cli_status skipped "$command_name" 'not installed'
		fi
	done < <(required_agent_tools "$target"; printf '%s\n' fzf hcom uv)
}

# Checks the core Claude links, and each optional feature that has at least one
# file installed.
check_claude_links() {
	# A core file, hook, theme, or rule provided by setup.
	local file_path
	# Whether any Claude hook path is present.
	local hooks_present=false
	cli_section 'Claude links'
	for file_path in CLAUDE.md .mcp.json statusline.sh; do
		check_link "$REPO_DIR/dist/claude/$file_path" "$CLAUDE_DIR/$file_path" "Claude $file_path"
	done
	if hooks_installed "$CLAUDE_DIR/settings.json" "$REPO_DIR/dist/claude/hooks" "$CLAUDE_DIR/hooks"; then
		hooks_present=true
		check_link "$REPO_DIR/dist/claude/settings.json" "$CLAUDE_DIR/settings.json" 'Claude settings.json'
	else
		cli_status skipped 'Claude settings.json' 'not installed'
	fi
	check_optional_group 'Claude hooks' "$REPO_DIR/dist/claude/hooks" "$CLAUDE_DIR/hooks" '*' "$hooks_present"
	check_optional_group 'Claude themes' "$REPO_DIR/dist/claude/themes" "$CLAUDE_DIR/themes" '*.json'
	for file_path in "$REPO_DIR"/dist/claude/rules/*.md; do
		[ -f "$file_path" ] || continue
		check_link "$file_path" "$CLAUDE_DIR/rules/${file_path##*/}" "Claude rules/${file_path##*/}"
	done
}

# Checks the core Codex links, and the hooks when any hook file is installed.
check_codex_links() {
	# Whether any Codex hook path is present.
	local hooks_present=false
	cli_section 'Codex links'
	check_link "$REPO_DIR/dist/codex/AGENTS.md" "$HOME/.agents/AGENTS.md" 'Codex global AGENTS.md'
	check_link "$REPO_DIR/dist/codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" 'Codex AGENTS.md'
	if hooks_installed "$CODEX_DIR/hooks.json" "$REPO_DIR/dist/codex/hooks" "$CODEX_DIR/hooks"; then
		hooks_present=true
		check_link "$REPO_DIR/dist/codex/hooks.json" "$CODEX_DIR/hooks.json" 'Codex hooks.json'
	else
		cli_status skipped 'Codex hooks.json' 'not installed'
	fi
	check_optional_group 'Codex hooks' "$REPO_DIR/dist/codex/hooks" "$CODEX_DIR/hooks" '*' "$hooks_present"
}

# Compares the Codex settings with what setup would write for the features
# that are installed.
check_codex_config() {
	# The installed Codex settings file.
	local config="$CODEX_DIR/config.toml"
	# A temporary copy of the config that setup would write.
	local proposed
	cli_section 'Codex settings'
	if [ ! -f "$config" ]; then
		required_problem 'Codex config.toml' 'missing'
		return
	fi
	proposed=$(mktemp)
	doctor_config_temp="$proposed"
	if hooks_installed "$CODEX_DIR/hooks.json" "$REPO_DIR/dist/codex/hooks" "$CODEX_DIR/hooks"; then
		setup_hooks=true
	fi
	# Setup writes this table only when it installs the permission profile; a
	# root default_permissions key may be the user's own setting.
	if grep -q '^\[permissions\.project-edit\]' "$config"; then
		setup_permissions=true
	else
		cli_status skipped 'Codex permission profile' 'not installed'
	fi
	if ! prepare_codex_config "$config" "$proposed"; then
		required_problem 'Codex config.toml' 'could not compare'
		return
	fi
	if cmp -s "$config" "$proposed"; then
		cli_status success 'Codex config.toml' 'matches setup'
	else
		required_problem 'Codex config.toml' 'differs from setup'
	fi
	rm -f "$proposed"
	doctor_config_temp=""
}

# Returns success when a hook settings file or any managed hook is present.
#
# @param  {string}  settings_file
#     The installed hook settings file.
# @param  {string}  source_dir
#     The directory containing managed hooks.
# @param  {string}  target_dir
#     The directory containing installed hooks.
hooks_installed() {
	# The settings file, managed hook directory, and installed hook directory.
	local settings_file="$1" source_dir="$2" target_dir="$3"
	[ -e "$settings_file" ] || [ -L "$settings_file" ] ||
		optional_group_present "$source_dir" "$target_dir" '*'
}

# Reports an optional file as not installed when it is absent, and otherwise
# checks its link like a required one.
#
# @param  {string}  source
#     The canonical file.
# @param  {string}  target
#     The installed path.
# @param  {string}  label
#     The name shown in the report.
check_optional_link() {
	# The canonical source, installed path, and report label.
	local source="$1" target="$2" label="$3"
	if [ -e "$target" ] || [ -L "$target" ]; then
		check_link "$source" "$target" "$label"
	else
		cli_status skipped "$label" 'not installed'
	fi
}

# Reports a group of optional files as not installed when none of them are.
# Otherwise checks every file's link, so a partial install fails.
#
# @param  {string}  label
#     The name shown when the group is absent.
# @param  {string}  source_dir
#     The directory containing canonical files.
# @param  {string}  target_dir
#     The installed directory.
# @param  {string}  pattern
#     The filename pattern to check.
# @param  {string}  required
#     True to check the group even when none of its files are installed,
#     because another part of the same feature is.
check_optional_group() {
	# The group name, source folder, installed folder, and filename pattern.
	local label="$1" source_dir="$2" target_dir="$3" pattern="$4"
	# Whether another path in the feature requires this group.
	local required="${5:-false}"
	# A canonical path currently inspected.
	local file_path
	if [ "$required" = false ] && ! optional_group_present "$source_dir" "$target_dir" "$pattern"; then
		cli_status skipped "$label" 'not installed'
		return
	fi
	for file_path in "$source_dir"/$pattern; do
		[ -f "$file_path" ] || continue
		check_link "$file_path" "$target_dir/${file_path##*/}" "$label/${file_path##*/}"
	done
}

# Reports whether an installed path links to its file in this checkout, and
# counts any other state as a required problem.
#
# @param  {string}  source
#     The canonical file or directory.
# @param  {string}  target
#     The installed path.
# @param  {string}  label
#     The name shown in the report.
check_link() {
	# The canonical source, installed path, and report label.
	local source="$1" target="$2" label="$3"
	if is_repo_owned_link "$source" "$target"; then
		if [ -e "$target" ]; then
			cli_status success "$label" 'correct'
		else
			required_problem "$label" 'broken link'
		fi
	elif [ -L "$target" ]; then
		if [ -e "$target" ]; then
			required_problem "$label" 'wrong target'
		else
			required_problem "$label" 'broken link to wrong target'
		fi
	elif [ -e "$target" ]; then
		required_problem "$label" 'real file in the way'
	else
		required_problem "$label" 'missing'
	fi
}

# Returns success when at least one file in the group is installed, even as a
# broken link.
#
# @param  {string}  source_dir
#     The directory containing canonical files.
# @param  {string}  target_dir
#     The installed directory.
# @param  {string}  pattern
#     The filename pattern to check.
optional_group_present() {
	# The source folder, installed folder, and filename pattern.
	local source_dir="$1" target_dir="$2" pattern="$3"
	# A canonical file whose installed path is checked.
	local file_path
	for file_path in "$source_dir"/$pattern; do
		[ -f "$file_path" ] || continue
		if [ -e "$target_dir/${file_path##*/}" ] || [ -L "$target_dir/${file_path##*/}" ]; then
			return 0
		fi
	done
	return 1
}

# Reports whether each skill is installed, excluded, off by default, missing or
# conflicting for the selected agents, with the command that fixes each one.
# A missing or wrong link for a selected skill counts as a doctor failure.
# Leftover links for unselected skills show as skipped and unmanaged content
# as a warning; neither fails. Returns 1 after printing the error when two
# skills share a name.
#
# @param  {string}  target
#     The selected Claude, Codex, or both agent targets.
report_skill_status() {
	# The selected agent targets included in this report.
	local target="$1"
	# The agent roots selected for the read-only report.
	local -a status_agents=()
	# The current agent root whose skill links are reported.
	local status_agent
	# The agent name displayed in the report heading.
	local status_label
	# The installed skill link folder for the current agent.
	local status_skills_dir
	# The canonical skill folders included in this report.
	local skill_paths=()
	# The canonical skill folder currently being reported.
	local status_skill
	# The canonical name used to label and locate the installed skill link.
	local status_name
	# The installed skill path checked for a link or conflict.
	local status_link
	# The collection containing the skill currently reported.
	local status_collection
	# Whether the current skill belongs to a collection that is off.
	local collection_off
	# The command that opts in to the current collection.
	local opt_in_hint

	case "$target" in
		claude) status_agents=("claude") ;;
		codex) status_agents=("codex") ;;
		both) status_agents=("claude" "codex") ;;
	esac

	for status_agent in "${status_agents[@]}"; do
		case "$status_agent" in
			claude)
				status_label="Claude"
				status_skills_dir="$CLAUDE_DIR/skills"
				;;
			codex)
				status_label="Codex"
				status_skills_dir="$HOME/.agents/skills"
				;;
		esac

		cli_section "$status_label skills ($(display_path "$status_skills_dir"))"
		if ! collect_canonical_skills; then
			return 1
		fi

		if [ "${#skill_paths[@]}" -gt 0 ]; then
			for status_skill in "${skill_paths[@]}"; do
				status_name=$(basename "$status_skill")
				status_link="$status_skills_dir/$status_name"
				status_collection=$(picker_collection_of "$status_skill")
				collection_off=false
				if collection_is_off "$status_collection"; then
					collection_off=true
				fi
				opt_in_hint="the $status_collection collection is off; run: scripts/setup.sh --$status_agent --include $status_name (adds every $status_collection skill)"

				if skill_is_selected "$status_skill"; then
					if is_repo_owned_link "$status_skill" "$status_link" && [ -e "$status_link" ]; then
						cli_status success "installed $status_name" "skills/$status_name"
					elif [ -e "$status_link" ] || [ -L "$status_link" ]; then
						check_link "$status_skill" "$status_link" "skills/$status_name"
					else
						required_problem "missing $status_name" "run: scripts/setup.sh --$status_agent --include $status_name"
					fi
				elif { [ -e "$status_link" ] || [ -L "$status_link" ]; } && ! is_repo_owned_link "$status_skill" "$status_link"; then
					if excluded_skill_exists "$status_name"; then
						cli_status warning "conflicting $status_name" "run: trash $(display_path "$status_link")"
					else
						cli_status warning "conflicting $status_name" "$opt_in_hint"
					fi
				elif excluded_skill_exists "$status_name"; then
					if is_repo_owned_link "$status_skill" "$status_link"; then
						cli_status skipped "excluded $status_name" "link still present; run: scripts/setup.sh --$status_agent --exclude $status_name"
					else
						cli_status skipped "excluded $status_name" "saved in ~/.agents/skill-exclusions"
					fi
				elif [ "$collection_off" = true ]; then
					if is_repo_owned_link "$status_skill" "$status_link"; then
						cli_status skipped "off by default $status_name" "link still present; $opt_in_hint, or run: trash $(display_path "$status_link")"
					else
						cli_status skipped "off by default $status_name" "$opt_in_hint"
					fi
				fi
			done
		fi
	done
	report_stale_skill_exclusions
}

# Warns about each saved exclusion that names no skill in this checkout, such
# as a skill that was renamed or merged. Reads the skill list that
# report_skill_status has just collected, so it must be called from there.
report_stale_skill_exclusions() {
	# A saved skill name checked against the canonical skill folders.
	local excluded_skill
	# A canonical skill folder compared with the saved name.
	local skill_path
	# Whether the saved name matches a current skill.
	local found
	# Whether the heading for these warnings has been printed yet.
	local heading_printed=false

	if [ "${#excluded_skills[@]}" -eq 0 ]; then
		return 0
	fi

	for excluded_skill in "${excluded_skills[@]}"; do
		found=false
		for skill_path in "${skill_paths[@]}"; do
			if [ "${skill_path##*/}" = "$excluded_skill" ]; then
				found=true
				break
			fi
		done
		if [ "$found" = false ]; then
			# Both agents share the exclusions file, so its warnings get their
			# own heading instead of appearing under the last agent's skills.
			if [ "$heading_printed" = false ]; then
				cli_section 'Saved skill exclusions (~/.agents/skill-exclusions)'
				heading_printed=true
			fi
			cli_status warning "stale exclusion $excluded_skill" 'remove it from ~/.agents/skill-exclusions, or run: scripts/setup.sh --include-all'
		fi
	done
}

# Reports whether this checkout's Git hooks come from src/hooks/git.
check_git_hooks() {
	# The configured Git hook directory, if any.
	local hooks_path
	hooks_path=$(git -C "$REPO_DIR" config --get core.hooksPath 2>/dev/null || true)
	if [ "$hooks_path" = src/hooks/git ]; then
		cli_status success 'Git core.hooksPath' 'src/hooks/git'
	else
		required_problem 'Git core.hooksPath' 'does not match src/hooks/git'
	fi
}

# Counts and reports a required problem.
#
# @param  {string}  label
#     The affected item.
# @param  {string}  detail
#     The problem found.
required_problem() {
	failed_checks=$((failed_checks + 1))
	cli_status error "$1" "$2"
}

main "$@"
