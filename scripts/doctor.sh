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
	# The excluded skill names, filled in by load_skill_exclusions.
	excluded_skills=()
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
		check_managed_group shared trash optional 'trash wrapper'
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

# Reports cli-style, then the helper commands the selected agents use, hcom
# and uv. A missing cli-style fails the doctor, because setup installs it.
# A missing helper or tool shows as not installed and does not fail the doctor,
# because not every user needs them.
#
# @param  {string}  target
#     The agents to check: claude, codex or both. Empty checks only cli-style,
#     hcom and uv.
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
	done < <(required_agent_tools "$target"; printf '%s\n' hcom uv)
}

# Checks the core Claude links, and each optional feature that has at least one
# file installed.
check_claude_links() {
	# Whether missing hook links fail the check, which they do once settings or
	# any hook is installed.
	local hooks_requirement=optional
	cli_section 'Claude links'
	check_managed_group claude core required
	if hooks_installed claude "$CLAUDE_DIR/settings.json"; then
		hooks_requirement=required
		check_managed_group claude settings required
	else
		cli_status skipped 'Claude settings.json' 'not installed'
	fi
	check_managed_group claude hooks "$hooks_requirement"
	check_managed_group claude themes optional
	check_managed_group claude rules required
}

# Checks the core Codex links, and the hooks when any hook file is installed.
check_codex_links() {
	# Whether missing hook links fail the check, which they do once the hook
	# manifest or any hook is installed.
	local hooks_requirement=optional
	cli_section 'Codex links'
	check_managed_group codex core required
	if hooks_installed codex "$CODEX_DIR/hooks.json"; then
		hooks_requirement=required
		check_managed_group codex manifest required
	else
		cli_status skipped 'Codex hooks.json' 'not installed'
	fi
	check_managed_group codex hooks "$hooks_requirement"
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
	if hooks_installed codex "$CODEX_DIR/hooks.json"; then
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
# @param  {string}  agent
#     The agent whose hooks are checked: claude or codex.
# @param  {string}  settings_file
#     The installed hook settings file.
hooks_installed() {
	# The agent and installed hook settings file.
	local agent="$1" settings_file="$2"
	# Whether any managed hook is installed.
	local present=false
	if [ -e "$settings_file" ] || [ -L "$settings_file" ]; then
		return 0
	fi
	managed_links "$agent" hooks check_managed_link_presence
	[ "$present" = true ]
}

# Checks each link in one group that setup manages. An optional group with
# nothing installed is reported as skipped, but once any of its links is
# installed, every link is checked so a partial install fails.
#
# @param  {string}  agent
#     The agent whose links are checked: claude, codex, or shared.
# @param  {string}  group
#     The group of links, as named by managed_links.
# @param  {string}  requirement
#     Either required, or optional when the group may not be installed.
# @param  {string}  skip_label
#     The name shown when a shared group is not installed. Shared groups
#     need it because they have no agent name to show. Optional.
check_managed_group() {
	# The agent and link group being checked.
	local agent="$1" group="$2"
	# Whether a missing group counts as a failure.
	local requirement="$3"
	# The agent name shown before each label. The link callbacks below read it.
	local link_prefix=''
	# The name shown when an optional group is skipped.
	local group_label="${4:-$group}"
	# Whether any link in the group is installed. The presence callback sets it.
	local present=false

	if [ "$agent" = claude ]; then
		link_prefix='Claude '
	elif [ "$agent" = codex ]; then
		link_prefix='Codex '
	fi
	if [ -n "$link_prefix" ]; then
		group_label="$link_prefix$group"
	fi
	if [ "$requirement" = optional ]; then
		managed_links "$agent" "$group" check_managed_link_presence
		if [ "$present" = false ]; then
			cli_status skipped "$group_label" 'not installed'
			return
		fi
	fi
	managed_links "$agent" "$group" check_managed_link
}

# Notes whether one link in an optional group is installed, counting a broken
# symlink as installed. It sets present to true in the calling function.
#
# @param  {string}  source
#     The repository file, which this check ignores.
# @param  {string}  target
#     The installed path to look for.
# @param  {string}  label
#     The link's label, which this check ignores.
check_managed_link_presence() {
	if [ -e "$2" ] || [ -L "$2" ]; then
		present=true
	fi
}

# Checks one managed link and shows it with the agent name from the calling
# check_managed_group, such as "Claude hooks/guard.sh".
#
# @param  {string}  source
#     The repository file the link should point at.
# @param  {string}  target
#     The installed path to check.
# @param  {string}  label
#     The link's label, without the agent name.
check_managed_link() {
	check_link "$1" "$2" "$link_prefix$3"
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

# Reports whether each skill is installed, excluded, missing or conflicting
# for the selected agents, with the command that fixes each one.
# A missing or wrong link for an installed skill counts as a doctor failure.
# Leftover links for excluded skills show as skipped and unmanaged content
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
				if skill_is_selected "$status_skill"; then
					if is_repo_owned_link "$status_skill" "$status_link" && [ -e "$status_link" ]; then
						cli_status success "installed $status_name" "skills/$status_name"
					elif [ -e "$status_link" ] || [ -L "$status_link" ]; then
						check_link "$status_skill" "$status_link" "skills/$status_name"
					else
						required_problem "missing $status_name" "run: scripts/setup.sh --$status_agent"
					fi
				elif { [ -e "$status_link" ] || [ -L "$status_link" ]; } && ! is_repo_owned_link "$status_skill" "$status_link"; then
					cli_status warning "conflicting $status_name" "run: trash $(display_path "$status_link")"
				elif excluded_skill_exists "$status_name"; then
					if is_repo_owned_link "$status_skill" "$status_link"; then
						cli_status skipped "excluded $status_name" "link still present; run: scripts/setup.sh --$status_agent"
					else
						cli_status skipped "excluded $status_name" "listed in scripts/skill-exclusions.txt"
					fi
				fi
			done
		fi
	done
	report_stale_skill_exclusions
}

# Warns about each repository exclusion that names no skill in this checkout, such
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
				cli_section 'Repository skill exclusions (scripts/skill-exclusions.txt)'
				heading_printed=true
			fi
			cli_status warning "stale exclusion $excluded_skill" 'remove it from scripts/skill-exclusions.txt'
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
