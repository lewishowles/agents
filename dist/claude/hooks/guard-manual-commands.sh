#!/usr/bin/env bash
# Blocks Playwright, Cypress and any agent-run command registered as manual-only,
# and tells the person the exact command to run in their own terminal instead.
#
# Browser runners are recognised by name, so they stay blocked even when agent-run
# is missing or cannot read its registry. Ordinary tools such as git and rg never
# trigger a registry lookup, which keeps the hook fast for everyday commands.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"  # Hook payload from Claude Code.
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0  # Tool about to run.
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0  # Full shell command the agent wants to run.
[[ -n "$command_str" ]] || exit 0

# The session's working directory, where agent-run looks up the repository's registered commands.
working_directory="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
if [[ -z "$working_directory" ]]; then
	working_directory="$(pwd)"
fi

# The separate commands in a chained command line, such as `make && npx playwright test`.
declare -a COMMAND_SEGMENTS=()

# The words of one command, starting at the program name after any variable assignments
# and env, command or exec prefixes.
declare -a COMMAND_WORDS=()

# A JSON list of word lists, one for each command that might match a registered command.
REGISTRY_COMMANDS_JSON='[]'

# Splits a command line into separate commands at newlines, &&, ||, ;, | and &,
# ignoring separators inside quotes or after a backslash. A separator counts even
# when it touches a word, as in `cd app; cypress run`, but the & in a redirection
# such as 2>&1 does not. Sets COMMAND_SEGMENTS.
#
# @param  {string}  command
#     The full shell command line from the tool call.
split_command_segments() {
	local command="$1"  # Shell command to split into executable segments.
	local current_segment=""  # Text collected for the current segment.
	local character=""  # Current character being inspected.
	local next_character=""  # Character after the current one for && and ||.
	local previous_character=""  # Character before a possible redirection operator.
	local quote=""  # Active single- or double-quote delimiter, if any.
	local escaped=false  # Whether the previous character escaped the current one.
	local index=0  # Current character position in the command.
	local command_length="${#command}"  # Number of characters in the command.

	COMMAND_SEGMENTS=()

	while (( index < command_length )); do
		character="${command:index:1}"

		if [[ "$escaped" == true ]]; then
			current_segment+="$character"
			escaped=false
			index=$((index + 1))
			continue
		fi

		if [[ "$character" == "\\" && "$quote" != "'" ]]; then
			current_segment+="$character"
			escaped=true
			index=$((index + 1))
			continue
		fi

		if [[ -n "$quote" ]]; then
			current_segment+="$character"
			if [[ "$character" == "$quote" ]]; then
				quote=""
			fi
			index=$((index + 1))
			continue
		fi

		if [[ "$character" == "'" || "$character" == '"' ]]; then
			quote="$character"
			current_segment+="$character"
			index=$((index + 1))
			continue
		fi

		if [[ "$character" == "&" || "$character" == "|" ]]; then
			previous_character=""
			if (( index > 0 )); then
				previous_character="${command:index-1:1}"
			fi
			next_character="${command:index+1:1}"
			if [[ "$character" == "&" && ( "$previous_character" == ">" || "$previous_character" == "<" || "$next_character" == ">" ) ]]; then
				current_segment+="$character"
				index=$((index + 1))
				continue
			fi
			if [[ "$next_character" == "$character" ]]; then
				index=$((index + 1))
			fi
			COMMAND_SEGMENTS+=("$current_segment")
			current_segment=""
			index=$((index + 1))
			continue
		fi

		if [[ "$character" == ";" || "$character" == $'\n' ]]; then
			COMMAND_SEGMENTS+=("$current_segment")
			current_segment=""
			index=$((index + 1))
			continue
		fi

		current_segment+="$character"
		index=$((index + 1))
	done

	COMMAND_SEGMENTS+=("$current_segment")
}

# Sets COMMAND_WORDS to the words of one command, starting at its program name, with
# surrounding quotes and grouping brackets removed, so `(npx cypress run)` reads as
# `npx cypress run`. A command that only changes directory leaves it empty.
#
# @param  {string}  command
#     One command from the command line, with no separators.
extract_command_words() {
	local command="$1"  # Shell command to split into words.
	local -a words=()  # Whitespace-delimited shell words from the command.
	local word  # Current word being inspected.
	local index=0  # Current position while removing command prefixes.
	local word_count=0  # Number of words in the command.
	local last_index=0  # Position of the final command word while removing closing brackets.

	read -r -a words <<< "$command"
	word_count="${#words[@]}"

	while (( index < word_count )); do
		word="${words[index]}"

		if [[ "$word" =~ ^[[:alpha:]_][[:alnum:]_]*= ]]; then
			index=$((index + 1))
			continue
		fi

		if [[ "$word" == "env" ]]; then
			index=$((index + 1))
			while (( index < word_count )); do
				word="${words[index]}"
				if [[ "$word" =~ ^[[:alpha:]_][[:alnum:]_]*= || "$word" == -* ]]; then
					index=$((index + 1))
					continue
				fi
				break
			done
			continue
		fi

		if [[ "$word" == "command" || "$word" == "exec" ]]; then
			index=$((index + 1))
			continue
		fi

		if [[ "$word" == "cd" ]]; then
			index=$((index + 1))
			while (( index < word_count )); do
				word="${words[index]}"
				index=$((index + 1))
				if [[ "$word" == "&&" || "$word" == ";" ]]; then
					break
				fi
			done
			continue
		fi

		break
	done

	COMMAND_WORDS=("${words[@]:index}")

	for index in "${!COMMAND_WORDS[@]}"; do
		COMMAND_WORDS[index]="${COMMAND_WORDS[index]#\'}"
		COMMAND_WORDS[index]="${COMMAND_WORDS[index]%\'}"
		COMMAND_WORDS[index]="${COMMAND_WORDS[index]#\"}"
		COMMAND_WORDS[index]="${COMMAND_WORDS[index]%\"}"
	done

	while [[ "${COMMAND_WORDS[0]:-}" == "(" || "${COMMAND_WORDS[0]:-}" == "{" ]]; do
		COMMAND_WORDS=("${COMMAND_WORDS[@]:1}")
	done
	while [[ "${COMMAND_WORDS[0]:-}" == \(* || "${COMMAND_WORDS[0]:-}" == \{* ]]; do
		COMMAND_WORDS[0]="${COMMAND_WORDS[0]:1}"
	done

	last_index=$(( ${#COMMAND_WORDS[@]} - 1 ))
	while (( last_index >= 0 )) && [[ "${COMMAND_WORDS[last_index]}" == ")" || "${COMMAND_WORDS[last_index]}" == "}" ]]; do
		COMMAND_WORDS=("${COMMAND_WORDS[@]:0:last_index}")
		last_index=$((last_index - 1))
	done
	if (( last_index >= 0 )); then
		while [[ "${COMMAND_WORDS[last_index]}" == *\) || "${COMMAND_WORDS[last_index]}" == *\} ]]; do
			COMMAND_WORDS[last_index]="${COMMAND_WORDS[last_index]%?}"
		done
	fi
}

# Prints `playwright` or `cypress` when COMMAND_WORDS runs one, either directly, by
# path, or through npx, bunx, yarn, pnpm, uv run or npm exec. Returns 1 otherwise.
find_browser_runner() {
	local first_word="${COMMAND_WORDS[0]:-}"  # First executable word after shell prefixes.
	local first_command_name="${first_word##*/}"  # Basename used to match wrappers and direct runners.
	local runner_index=0  # Position of the runner after its package-manager wrapper.
	local runner=""  # Browser runner name, when one is present.
	local wrapper_subcommand="${COMMAND_WORDS[1]:-}"  # Wrapper subcommand or bare runner name.
	local wrapper_subcommand_name="${wrapper_subcommand##*/}"  # Basename used for pnpm's bare runner form.

	case "$first_command_name" in
		playwright|cypress)
			runner="$first_command_name"
			;;
		npx)
			runner_index=1
			while (( runner_index < ${#COMMAND_WORDS[@]} )); do
				case "${COMMAND_WORDS[runner_index]}" in
					-p|--package)
						runner_index=$((runner_index + 2))
						;;
					--package=*)
						runner_index=$((runner_index + 1))
						;;
					--)
						runner_index=$((runner_index + 1))
						break
						;;
					-*)
						runner_index=$((runner_index + 1))
						;;
					*)
						break
						;;
				esac
			done
			;;
		bunx)
			runner_index=1
			while (( runner_index < ${#COMMAND_WORDS[@]} )) && [[ "${COMMAND_WORDS[runner_index]}" == -* ]]; do
				runner_index=$((runner_index + 1))
			done
			;;
		yarn)
			runner_index=1
			if [[ "${COMMAND_WORDS[runner_index]:-}" == "run" || "${COMMAND_WORDS[runner_index]:-}" == "exec" ]]; then
				runner_index=$((runner_index + 1))
			fi
			;;
		pnpm)
			if [[ "${COMMAND_WORDS[1]:-}" == "exec" || "${COMMAND_WORDS[1]:-}" == "dlx" ]]; then
				runner_index=2
			elif [[ "$wrapper_subcommand_name" == "playwright" || "$wrapper_subcommand_name" == "cypress" ]]; then
				runner_index=1
			else
				return 1
			fi
			;;
		uv)
			[[ "${COMMAND_WORDS[1]:-}" == "run" ]] || return 1
			runner_index=2
			;;
		npm)
			[[ "${COMMAND_WORDS[1]:-}" == "exec" ]] || return 1
			runner_index=2
			;;
		*)
			return 1
			;;
	esac

	if [[ -z "$runner" ]]; then
		while (( runner_index < ${#COMMAND_WORDS[@]} )) && [[ "${COMMAND_WORDS[runner_index]}" == -* ]]; do
			runner_index=$((runner_index + 1))
		done
		runner="${COMMAND_WORDS[runner_index]:-}"
		runner="${runner##*/}"
	fi

	case "$runner" in
		playwright|cypress)
			printf '%s' "$runner"
			return 0
			;;
		*)
			return 1
			;;
	esac
}

# Returns 0 when a program might be a registered command. Everyday shell tools
# return 1 so that most commands never wait for agent-run.
#
# @param  {string}  first_word
#     The program name, which may include a path.
is_registry_candidate() {
	local first_word="$1"  # First executable word to classify.
	local command_name="${first_word##*/}"  # Basename used for path-qualified commands.

	case "$command_name" in
		""|:|true|false|cd|pwd|echo|printf|test|\[|command|env|export|unset|read|cat|head|tail|cut|sort|uniq|tr|sed|awk|grep|rg|find|ls|du|df|file|stat|git|mkdir|cp|mv|trash|chmod|touch|date|basename|dirname|sleep|which|type)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

# Returns 0 when any command in REGISTRY_COMMANDS_JSON starts with the words of a
# registered command marked manual. A missing or failing agent-run counts as having
# no registrations, so this never blocks because agent-run is unavailable.
has_manual_registration() {
	local list_json=""  # JSON response from agent-run.

	command -v agent-run >/dev/null 2>&1 || return 1

	if ! list_json="$(cd "$working_directory" && agent-run list --json 2>/dev/null)"; then
		return 1
	fi

	if jq -e --argjson command_segments "$REGISTRY_COMMANDS_JSON" '
		.ok == true
		and (.data.commands | type == "array")
		and any(.data.commands[]?;
			. as $record
			| ($record.manual == true)
			and (($record.argv // null) | type == "array")
			and ((($record.argv // []) | length) > 0)
			and any($command_segments[];
				. as $command_words
				| (($command_words | length) >= ($record.argv | length))
				and (($command_words[0:($record.argv | length)]) == $record.argv)
			)
		)
	' <<< "$list_json" >/dev/null 2>&1; then
		return 0
	fi

	return 1
}

# Refuses the tool call and tells the person the exact command to run themselves.
#
# @param  {string}  reason
#     What was found, shown in the message, such as `raw playwright command`.
block() {
	local reason="$1"  # Reason shown alongside the command to run manually.

	printf 'guard-manual-commands: blocked %s. Run it yourself in a terminal: cd %q && %s\n' \
		"$reason" "$working_directory" "$command_str" >&2
	exit 2
}

split_command_segments "$command_str"

# Check for browser runners first, anywhere in the command line, so they are blocked
# without needing agent-run.
# command_segment holds one command from the line being checked.
for command_segment in "${COMMAND_SEGMENTS[@]}"; do
	extract_command_words "$command_segment"
	[[ "${#COMMAND_WORDS[@]}" -gt 0 ]] || continue

	# Browser runner name returned by the current segment, when present.
	browser_runner=""
	if browser_runner="$(find_browser_runner)"; then
		block "raw $browser_runner command"
	fi
done

# Gather every command that might be registered, so agent-run is asked at most once.
for command_segment in "${COMMAND_SEGMENTS[@]}"; do
	extract_command_words "$command_segment"
	[[ "${#COMMAND_WORDS[@]}" -gt 0 ]] || continue

	first_word="${COMMAND_WORDS[0]}"  # The program this command runs.
	is_registry_candidate "$first_word" || continue

	# This command's words as a JSON list, for comparison with registered argv lists.
	command_words_json="$(jq -cn --args '$ARGS.positional' -- "${COMMAND_WORDS[@]}")" || exit 0
	REGISTRY_COMMANDS_JSON="$(jq -c --argjson command_words "$command_words_json" '. + [$command_words]' <<< "$REGISTRY_COMMANDS_JSON")" || exit 0
done

[[ "$REGISTRY_COMMANDS_JSON" != '[]' ]] || exit 0

if has_manual_registration; then
	block "manual-only command"
fi

exit 0
