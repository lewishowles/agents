#!/usr/bin/env bash
# Suppresses acknowledgement-only HCOM messages from agent tool calls.
#
# On both Claude and Codex the send is rewritten to a no-op, so the attempt
# leaves no error to react to and no reason to retry. Codex only accepts a
# replaced command when the hook also allows it.
# Pass "codex" as the first argument from the Codex hook wiring.

set -euo pipefail

runtime="${1:-claude}"

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

# The command with heredoc bodies removed. A heredoc is message content, even when the same Bash call sends the file it writes, so text quoted there must not count as a send.
command_without_heredocs=""
# The end words of heredocs opened on the same command line, in body order.
heredoc_delimiters=()
# Whether each of those heredocs ignores leading tabs on its closing line, as the <<- form does.
heredoc_strip_tabs=()
# Finds a heredoc opening and captures its operator and end word. The space before << and the letter that starts the end word rule out here-strings and number shifts such as $((1 << 4)). A shift by a variable, such as (( a << b )), still looks like a heredoc, and so does quoted text that contains << and a word.
heredoc_pattern="(^|[[:space:]])(<<-?)[[:space:]]*['\"]?([[:alpha:]_][[:alnum:]_]*)"
# The part of a command line still to check for heredoc openings.
remaining_line=""
# A possible heredoc closing line after any allowed leading tabs are removed.
closing_line=""

while IFS= read -r line || [[ -n "$line" ]]; do
	if [[ ${#heredoc_delimiters[@]} -gt 0 ]]; then
		closing_line="$line"
		if [[ "${heredoc_strip_tabs[0]}" == true ]]; then
			while [[ "$closing_line" == $'\t'* ]]; do
				closing_line="${closing_line#$'\t'}"
			done
		fi
		if [[ "$closing_line" == "${heredoc_delimiters[0]}" ]]; then
			heredoc_delimiters=("${heredoc_delimiters[@]:1}")
			heredoc_strip_tabs=("${heredoc_strip_tabs[@]:1}")
		fi
		continue
	fi
	command_without_heredocs+="$line"$'\n'
	remaining_line="$line"
	while [[ "$remaining_line" =~ $heredoc_pattern ]]; do
		heredoc_delimiters+=("${BASH_REMATCH[3]}")
		if [[ "${BASH_REMATCH[2]}" == '<<-' ]]; then
			heredoc_strip_tabs+=(true)
		else
			heredoc_strip_tabs+=(false)
		fi
		remaining_line="${remaining_line#*"${BASH_REMATCH[0]}"}"
	done
done <<< "$command_str"

# The remaining command on one line, with each line break treated as a command separator.
normalised_command="${command_without_heredocs//$'\n'/;}"
# Finds an hcom send at the start of one command.
hcom_send_pattern='^(command[[:space:]]+)?hcom[[:space:]]+send([[:space:]]|$)'
# Finds a team-send to a core role, written role first as the team rules show it. Its body arrives on stdin, so only the intent can mark it as an acknowledgement.
team_send_pattern='^(command[[:space:]]+)?([^[:space:]]+/)?team-send[[:space:]]+(orchestrator|scout|implementer|reviewer)([[:space:]]|$)'
ack_intent_pattern='(^|[[:space:]])--intent(=|[[:space:]]+)ack([[:space:]]|$)'
# Finds acknowledgement text disguised as a result.
inform_intent_pattern='(^|[[:space:]])--intent(=|[[:space:]]+)inform([[:space:]]|$)'
# Covers common acknowledgement-only openings.
acknowledgement_text_pattern=$'^(Acknowledged|Acknowledgement|Understood|I will|I\'ll|I’ll|Will do)([[:space:][:punct:]]|$)'

# True when the command is an acknowledgement-only team message.
is_acknowledgement=false

# The separate commands in the Bash call, split at unquoted command separators.
command_segments=()
# The command being collected before the next unquoted semicolon, ampersand, or pipe.
command_segment=""
# The quote character the scan is inside, or empty outside quotes.
quote=""
# True when the previous character was a backslash, so this one is taken literally.
escaped=false

for ((index = 0; index < ${#normalised_command}; index++)); do
	# The character being scanned.
	character="${normalised_command:index:1}"

	if [[ "$escaped" == true ]]; then
		escaped=false
	elif [[ "$character" == $'\\' && "$quote" != "'" ]]; then
		escaped=true
	elif [[ -n "$quote" ]]; then
		[[ "$character" == "$quote" ]] && quote=""
	elif [[ "$character" == "'" || "$character" == '"' ]]; then
		quote="$character"
	elif [[ "$character" == ';' || "$character" == '&' || "$character" == '|' ]]; then
		command_segments+=("$command_segment")
		command_segment=""
		continue
	fi
	command_segment+="$character"
done

command_segments+=("$command_segment")

# One command from the Bash call, checked without its neighbours' options.
for send_command in "${command_segments[@]}"; do
	# Drop leading spaces so the send patterns can anchor to the start of the command.
	send_command="${send_command#"${send_command%%[![:space:]]*}"}"

	# This command's options, before the message separator. Only these can set its intent.
	send_options="${send_command%% -- *}"

	if [[ "$send_command" =~ $hcom_send_pattern ]]; then
		if [[ "$send_options" =~ $ack_intent_pattern ]]; then
			is_acknowledgement=true
		elif [[ "$send_options" =~ $inform_intent_pattern && "$send_command" == *' -- '* ]]; then
			# The inline HCOM message after the separator, without its opening quote.
			message_text="${send_command#* -- }"
			message_text="${message_text#\'}"
			message_text="${message_text#\"}"
			[[ "$message_text" =~ $acknowledgement_text_pattern ]] && is_acknowledgement=true
		fi
	elif [[ "$send_command" =~ $team_send_pattern && "$send_options" =~ $ack_intent_pattern ]]; then
		is_acknowledgement=true
	fi

	[[ "$is_acknowledgement" == true ]] && break
done

[[ "$is_acknowledgement" == true ]] || exit 0

# Replacement that explains the suppressed command.
no_op_command="printf 'guard-hcom-ack: acknowledgement not sent; nothing in this command ran; re-run any other work in the command without the acknowledgement\n'"

printf '%s' "$input" | jq -c --arg command "$no_op_command" --arg runtime "$runtime" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = $command)}}
	| if $runtime == "codex" then .hookSpecificOutput.permissionDecision = "allow" else . end'
