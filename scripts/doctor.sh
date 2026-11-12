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
# shellcheck source=scripts/lib/setup-plan.sh
source "$SCRIPT_DIR/lib/setup-plan.sh"

# Link targets already read during this health check, by link path, so each
# link is read once.
declare -A remembered_link_targets=()

# The number of required checks that found a problem.
failed_checks=0
# The Codex config this run prepared, reused by the setup plan and removed on exit.
prepared_codex_config=""

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

	# The health check never changes links, so a target read once stays correct.
	remember_link_targets=true

	# Stop Python helpers from writing bytecode under the user's home.
	export PYTHONDONTWRITEBYTECODE=1
	# Stop Bun writing its transpiler cache under the user's home when cli-style
	# starts.
	export BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
	# Start from setup's default settings, so the plan below matches what a
	# plain setup run would change. Doctor takes no setup options.
	# shellcheck disable=SC2119
	parse_setup_options
	load_managed_paths
	# Whether this home contains a visible Claude installation.
	local claude_found=false
	# Whether this home contains a visible Codex installation.
	local codex_found=false
	# The agents set up in this home: claude, codex, both, or empty for neither.
	local target
	# Whether the repository skill list can be used to build the setup plan.
	local skill_status_ok=true
	# Whether the setup plan will run for this home.
	local plan_will_run=false
	# Whether setup can read the installed Codex configuration.
	local codex_config_readable=true

	# shellcheck source=scripts/lib/script-output.sh
	source "$SCRIPT_DIR/lib/script-output.sh"
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
	if [ -n "$target" ]; then
		if ! report_skill_status "$target"; then
			# The skill report fails when two skills share a name and has already
			# printed that error, so only count it here.
			failed_checks=$((failed_checks + 1))
			skill_status_ok=false
		fi
	fi
	if [ -n "$target" ] && [ "$skill_status_ok" = true ]; then
		plan_will_run=true
	fi
	# A missing cli-style belongs to the plan only when that plan will run.
	check_tools "$plan_will_run"
	if [ "$plan_will_run" = true ]; then
		if [ "$codex_found" = true ] && ! check_codex_config_read; then
			codex_config_readable=false
		fi
		report_setup_plan "$target" "$codex_config_readable"
	fi

	if [ "$failed_checks" -gt 0 ]; then
		cli_status error "$failed_checks required check(s) failed"
		return 1
	fi
	cli_status success 'No required problems found'
}

# Removes the Codex config this run prepared when doctor exits.
cleanup_doctor() {
	if [ -n "$prepared_codex_config" ]; then
		rm -f "$prepared_codex_config"
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

# Reports cli-style, hcom and uv. The plan counts an installable cli-style
# when it runs; this check counts it when no plan will run or no installer exists.
#
# @param  {string}  plan_will_run
#     true when the detected agents have a usable skill list for the plan.
check_tools() {
	# Whether setup's plan will report a missing cli-style.
	local plan_will_run="$1"
	cli_section 'Commands'
	if cli_style_install_needed; then
		if [ "$plan_will_run" = true ] && choose_cli_style_install_command >/dev/null 2>&1; then
			cli_status skipped 'cli-style' 'missing; setup will install it'
		else
			required_problem 'cli-style' 'missing; run: bun add -g @lewishowles/cli-style (or npm install -g @lewishowles/cli-style)'
		fi
	else
		cli_status success 'cli-style' 'installed'
	fi
	# An optional command shown in the report.
	local command_name
	for command_name in hcom uv; do
		if command -v "$command_name" >/dev/null 2>&1; then
			cli_status success "$command_name" 'installed'
		else
			cli_status skipped "$command_name" 'not installed'
		fi
	done
}

# Fails the doctor when setup cannot build a new Codex config.toml from the
# installed one, which also means the setup plan cannot compare them. When the
# build succeeds, the new config is kept so the setup plan can compare it without
# building it again.
check_codex_config_read() {
	# The temporary output of the config builder.
	local proposed
	proposed=$(mktemp)
	prepared_codex_config="$proposed"
	if ! prepare_codex_config "$CODEX_DIR/config.toml" "$proposed"; then
		required_problem 'Codex config.toml' 'could not compare'
		rm -f "$proposed"
		prepared_codex_config=""
		return 1
	fi
}

# Lists each change setup would make, grouped by kind, and counts every one as
# a required problem that the matching setup command fixes.
#
# @param  {string}  target
#     The detected agents: claude, codex or both.
# @param  {string}  codex_config_readable
#     Whether the Codex config can be compared with setup's output.
report_setup_plan() {
	# The detected setup target.
	local target="$1"
	# Whether to include planned Codex config changes.
	local codex_config_readable="$2"
	# The setup command that makes the listed changes.
	local setup_command="scripts/setup.sh --$target"
	# One kind of change, such as Links or Backups.
	local kind

	if ! build_setup_plan "$target" "$prepared_codex_config"; then
		cli_section 'Setup changes'
		# check_tools has already counted the missing cli-style.
		if cli_style_install_needed && ! choose_cli_style_install_command >/dev/null 2>&1; then
			cli_status skipped 'Setup' 'cannot list changes until cli-style is installed'
		else
			required_problem 'Setup plan' 'could not be built'
		fi
		return
	fi
	if [ "$codex_config_readable" = false ]; then
		omit_unreadable_codex_config_items
	fi

	cli_section 'Setup changes'
	if [ "$plan_count" -eq 0 ]; then
		cli_status success 'Setup' 'Nothing to change.'
		return
	fi

	while IFS= read -r kind; do
		report_plan_kind "$kind" "$setup_command"
	done < <(plan_kinds)
}

# Removes Codex config changes from a plan when its source cannot be read.
# The matched text follows plan_backup in setup-links.sh and the Codex settings
# kind in setup-plan.sh; update these matches if either plan wording changes.
omit_unreadable_codex_config_items() {
	# The displayed path of the unreadable config.
	local config_path
	# A plan item being checked.
	local item
	# The plan items that can still be reported.
	local -a readable_items=()
	config_path=$(display_path "$CODEX_DIR/config.toml")
	for item in "${plan_items[@]}"; do
		case "$item" in
			'Codex settings|'*|"Backups|Save $config_path in "*|"Backups|Remove older backup $config_path.bak."*) continue ;;
		esac
		readable_items+=("$item")
	done
	plan_items=("${readable_items[@]}")
	plan_count=${#plan_items[@]}
}

# Prints each kind of planned change once, in the order setup planned them.
plan_kinds() {
	# One planned change, stored as kind|description.
	local item
	# The kinds already printed, so each appears once.
	local -A seen_kinds=()
	# The kind of the current change.
	local kind

	for item in "${plan_items[@]}"; do
		kind="${item%%|*}"
		if [ -z "${seen_kinds[$kind]:-}" ]; then
			seen_kinds[$kind]=1
			printf '%s\n' "$kind"
		fi
	done
}

# Lists the planned changes of one kind as required problems.
#
# @param  {string}  kind
#     The kind of change to list.
# @param  {string}  setup_command
#     The setup command shown as the fix.
report_plan_kind() {
	# The kind to list and the command that fixes it.
	local kind="$1" setup_command="$2"
	# One planned change, stored as kind|description.
	local item

	cli_section "$kind"
	for item in "${plan_items[@]}"; do
		if [ "${item%%|*}" = "$kind" ]; then
			required_problem "${item#*|}" "run: $setup_command"
		fi
	done
}

# Reports whether each skill is installed, excluded, missing or conflicting.
# The setup plan counts changes to skill links as required problems. Returns 1
# after printing the error when two skills share a name.
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
				status_name=${status_skill##*/}
				status_link="$status_skills_dir/$status_name"
				if skill_is_selected "$status_skill"; then
					if is_repo_owned_link "$status_skill" "$status_link" && [ -e "$status_link" ]; then
						cli_status success "installed $status_name" "skills/$status_name"
					elif [ -e "$status_link" ] || [ -L "$status_link" ]; then
						cli_status skipped "conflicting $status_name" "run: scripts/setup.sh --$status_agent"
					else
						cli_status skipped "missing $status_name" "run: scripts/setup.sh --$status_agent"
					fi
				elif { [ -e "$status_link" ] || [ -L "$status_link" ]; } && ! is_repo_owned_link "$status_skill" "$status_link"; then
					display_path_to_reply "$status_link"
					cli_status warning "conflicting $status_name" "run: trash $REPLY"
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
