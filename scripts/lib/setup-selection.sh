#!/usr/bin/env bash
# Reads setup options and the repository list of skills left out of installs.
# Before sourcing this file, set REPO_DIR and source setup-links.sh.
# shellcheck disable=SC2034

# The repository list of skill names left out of installs.
skill_exclusions_file="$REPO_DIR/scripts/skill-exclusions.txt"

# Reads the supported setup options into settings shared with setup.sh.
#
# @param  {string}  ...
#     Command-line options passed to setup.
parse_setup_options() {
	# The agents to set up, or both when no agent is specified.
	target="both"
	# Whether hooks are installed. Setup always installs them; doctor reads the
	# answer from the machine, and the shared Codex config builder uses it.
	setup_hooks=true
	# Whether the managed Codex permission profile is installed. Setup always
	# installs it; doctor reads the answer from the machine, and the shared Codex
	# config builder uses it.
	setup_permissions=true
	# The Claude configuration folder, overridable for a second account.
	CLAUDE_DIR="$HOME/.claude"
	# The Codex configuration folder, overridable for a second account.
	CODEX_DIR="$HOME/.codex"
	# The local agent-tools checkout that provides missing commands.
	AGENT_TOOLS_DIR="$HOME/Dev/Repositories/Packages/agent-tools"
	# The skill names excluded from both agents.
	excluded_skills=()
	# The canonical skill folders, filled by collect_canonical_skills.
	skill_paths=()

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--claude) target="claude" ;;
			--codex) target="codex" ;;
			--both) target="both" ;;
			--claude-dir|--codex-dir)
				if [ "$#" -lt 2 ]; then
					usage >&2
					exit 1
				fi
				if [ "$1" = --claude-dir ]; then
					CLAUDE_DIR="$2"
				else
					CODEX_DIR="$2"
				fi
				shift
				;;
			--help) usage; exit 0 ;;
			*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
		esac
		shift
	done
}

# Prints the supported setup options.
usage() {
	printf 'Usage: %s [--claude|--codex|--both] [--claude-dir <path>] [--codex-dir <path>]\n' "$(basename "$0")"
}

# Fills excluded_skills from the repository exclusion list, skipping blank
# lines and lines that start with #. Returns 1 when the list file is missing.
load_skill_exclusions() {
	# A skill name read from the repository list.
	local skill_name

	if [ ! -f "$skill_exclusions_file" ]; then
		printf 'Missing skill exclusion list: %s\n' "$skill_exclusions_file" >&2
		return 1
	fi

	excluded_skills=()
	while IFS= read -r skill_name || [ -n "$skill_name" ]; do
		case "$skill_name" in
			''|\#*) continue ;;
		esac
		excluded_skills+=("$skill_name")
	done < "$skill_exclusions_file"
}

# Returns success when the named skill is in the repository exclusion list.
#
# @param  {string}  skill_name
#     The skill folder name to check.
excluded_skill_exists() {
	# The skill name being checked.
	local skill_name="$1"
	# A skill name in the repository exclusion list.
	local excluded_skill

	if [ "${#excluded_skills[@]}" -eq 0 ]; then
		return 1
	fi

	for excluded_skill in "${excluded_skills[@]}"; do
		if [ "$excluded_skill" = "$skill_name" ]; then
			return 0
		fi
	done
	return 1
}

# Returns success when setup installs the canonical skill folder.
#
# @param  {string}  skill_path
#     The canonical skill folder.
skill_is_selected() {
	! excluded_skill_exists "${1##*/}"
}
