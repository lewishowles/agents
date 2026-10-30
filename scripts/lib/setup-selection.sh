#!/usr/bin/env bash
# Reads setup's options and decides which agents, features and skills to install.
# Before calling these functions, set REPO_DIR and source setup-links.sh, which
# lists the skills, and cli-style-output.sh, which the excluded-skills report
# uses to print.
# The settings are stored in global variables that setup.sh reads, so shellcheck
# reports them as unused here.
# shellcheck disable=SC2034

# Reads setup's command-line options into the global settings, and stops with
# usage help when an option is unknown, incomplete or cannot be combined.
#
# @param  {string}  ...
#     Command-line options passed to setup.
parse_setup_options() {
	# The agents to set up (claude, codex or both). It comes from the options, defaults
	# to both for skill options, and is otherwise asked for.
	target=""
	# Whether to run sync.sh to regenerate dist/ before installing links.
	refresh=false
	# Whether command-line skill options were supplied.
	skill_options_requested=false
	# Whether the terminal skill selection flow was requested.
	select_requested=false
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
			--refresh)       refresh=true ;;
			--yes)           yes_requested=true ;;
			--help)          usage; exit 0 ;;
			*)               usage >&2; exit 1 ;;
		esac

		shift
	done

	if [ "$select_requested" = true ] && [ "${#skill_operation_types[@]}" -gt 0 ]; then
		printf '%s\n' '--select cannot be combined with --exclude, --include, or --include-all.' >&2
		usage >&2
		exit 1
	fi

	if [ "$select_requested" = true ] && ! [ -t 0 ]; then
		printf '%s\n' '--select requires a terminal. Use --exclude or --include when standard input is not a terminal.' >&2
		exit 1
	fi
}

# Settles the preset, the agents to set up and the optional features, asking in
# the terminal when the options leave them open. When the skill picker will run,
# it checks for fzf first, so nobody answers questions for a run that cannot finish.
choose_setup_features() {
	if [ -z "$preset" ] && [ "$skill_options_requested" = false ] && [ -z "$target" ] && [ -t 0 ]; then
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

	if [ "$select_requested" = true ] || { [ "$preset" = pick ] && [ "$skill_options_requested" = false ]; }; then
		require_usable_skill_picker
	fi

	if [ -z "$target" ]; then
		if [ "$skill_options_requested" = true ] || ! [ -t 0 ]; then
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

# Stops before prompts or changes when the interactive picker cannot run.
require_usable_skill_picker() {
	# The installed fzf version, when fzf is available.
	local fzf_version=''
	if command -v fzf >/dev/null 2>&1; then
		fzf_version=$(fzf --version 2>/dev/null) || fzf_version=''
	fi

	if ! fzf_supports_picker_actions "$fzf_version"; then
		# shellcheck source=scripts/lib/cli-style-output.sh
		source "$REPO_DIR/scripts/lib/cli-style-output.sh"
		cli_status error 'Interactive skill selection needs fzf 0.74 or newer. Install it, or choose skills with --include and --exclude.' >&2
		exit 1
	fi
}

# Works out which skills to install from the saved choices plus either the
# skill picker or the --include and --exclude options.
choose_setup_skills() {
	load_skill_exclusions
	load_skill_inclusions
	if ! validate_skill_operations; then
		exit 1
	fi

	if [ "$select_requested" = true ]; then
		if ! collect_canonical_skills; then
			exit 1
		fi

		if ! select_skills_with_fzf; then
			printf '%s\n' 'Skill selection cancelled. Nothing changed.'
			exit 0
		fi
	elif [ "$skill_options_requested" = true ]; then
		apply_skill_operations
	fi
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
	printf 'Usage: %s [--preset skills-only|pick|everything] [--claude|--codex|--both] [--claude-dir <path>] [--codex-dir <path>] [--select] [--exclude <skill>[,<skill>...]] [--include <skill>[,<skill>...]] [--include-all] [--refresh] [--yes]\n' "$(basename "$0")"
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
		skill_entries+=("skill"$'\t'"$skill_name"$'\t'"$(picker_entry "$skill_path" "$name_width")")
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
		printf 'source %q\n' "$REPO_DIR/scripts/lib/setup-selection.sh"
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

# Prints one fzf picker row for a skill. The name is padded so descriptions
# line up, and the description is dim unless NO_COLOR is set.
#
# @param  {string}  skill_path
#     The canonical skill folder to display.
# @param  {integer}  name_width
#     The width of the longest skill name.
picker_entry() {
	# The skill folder shown in the picker.
	local skill_path="$1"
	# The width reserved for the skill name.
	local name_width="$2"
	# The skill name shown in the picker.
	local skill_name
	# The description shown beside the skill name.
	local description
	# The row printed for fzf.
	local entry

	skill_name=$(basename "$skill_path")
	description=$(picker_description "$skill_path")
	entry="  $skill_name"
	if [ -n "$description" ]; then
		printf -v entry '  %-*s  ' "$name_width" "$skill_name"
		if [ -z "${NO_COLOR+x}" ]; then
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

# Reads persisted skill exclusions without creating the exclusions file.
load_skill_exclusions() {
	# The saved skill name currently added to the exclusion list.
	local skill_name

	[ -f "$skill_exclusions_file" ] || return 0

	while IFS= read -r skill_name; do
		[ -n "$skill_name" ] || continue
		if ! excluded_skill_exists "$skill_name"; then
			excluded_skills+=("$skill_name")
		fi
	done < "$skill_exclusions_file"
}

# Reads saved collection opt-ins without creating the inclusions file.
load_skill_inclusions() {
	# The collection currently read from the saved file.
	local collection_name

	[ -f "$skill_inclusions_file" ] || return 0

	while IFS= read -r collection_name; do
		if default_off_collection_exists "$collection_name" && ! included_collection_exists "$collection_name"; then
			included_collections+=("$collection_name")
		fi
	done < "$skill_inclusions_file"
}

# Returns success when a collection is off until explicitly selected.
#
# @param  {string}  collection_name
#     The collection to check.
default_off_collection_exists() {
	# The collection to check against the default-off list.
	local collection_name="$1"
	# A collection in the default-off list.
	local default_off_collection

	for default_off_collection in "${default_off_collections[@]}"; do
		[ "$default_off_collection" = "$collection_name" ] && return 0
	done
	return 1
}

# Returns success when a default-off collection was selected previously.
#
# @param  {string}  collection_name
#     The collection to check.
included_collection_exists() {
	# The collection to check against saved opt-ins.
	local collection_name="$1"
	# A saved collection opt-in.
	local included_collection

	if [ "${#included_collections[@]}" -gt 0 ]; then
		for included_collection in "${included_collections[@]}"; do
			[ "$included_collection" = "$collection_name" ] && return 0
		done
	fi
	return 1
}

# Returns success when a default-off collection has not been opted in to.
#
# @param  {string}  collection_name
#     The collection to check.
collection_is_off() {
	# The collection checked against its default and saved choice.
	local collection_name="$1"

	if default_off_collection_exists "$collection_name" && ! included_collection_exists "$collection_name"; then
		return 0
	fi
	return 1
}

# Returns success when the skill is not excluded and its default-off collection,
# if any, has been opted in to.
#
# @param  {string}  skill_path
#     The canonical skill folder.
skill_is_selected() {
	# The canonical skill folder being checked.
	local skill_path="$1"
	# The collection containing the skill.
	local collection_name
	collection_name=$(picker_collection_of "$skill_path")

	if excluded_skill_exists "${skill_path##*/}"; then
		return 1
	fi
	if collection_is_off "$collection_name"; then
		return 1
	fi
	return 0
}

# Returns 0 when the current exclusion list contains a skill name.
#
# @param  {string}  skill_name
#     Skill name to find in the current exclusion list.
excluded_skill_exists() {
	# The skill name looked up in the current exclusion list.
	local skill_name="$1"
	# The saved exclusion compared with the requested skill.
	local excluded_skill

	if [ "${#excluded_skills[@]}" -gt 0 ]; then
		for excluded_skill in "${excluded_skills[@]}"; do
			if [ "$excluded_skill" = "$skill_name" ]; then
				return 0
			fi
		done
	fi

	return 1
}

# Prints the collection name for a canonical skill folder.
#
# @param  {string}  skill_path
#     The canonical skill folder.
picker_collection_of() {
	# The canonical skill folder.
	local skill_path="$1"
	# The parent collection folder.
	local collection_path="${skill_path%/*}"

	printf '%s\n' "${collection_path##*/}"
}

# Returns success when a skill name appears in an exclusion list.
#
# @param  {string}  slug
#     The skill name to check.
# @param  {string}  ...
#     Excluded skill names.
skill_is_excluded() {
	# The skill name to look for.
	local slug="$1"
	# The excluded skill name currently being compared.
	local excluded_skill
	shift

	for excluded_skill in "$@"; do
		if [ "$excluded_skill" = "$slug" ]; then
			return 0
		fi
	done
	return 1
}
