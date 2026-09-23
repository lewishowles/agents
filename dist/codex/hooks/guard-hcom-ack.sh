#!/usr/bin/env bash
# Suppresses acknowledgement-only HCOM messages from agent tool calls.
#
# Claude honours `hookSpecificOutput.updatedInput`, so on Claude the send is
# rewritten to a no-op: the attempt leaves no error to react to and no reason to
# retry. Codex does not support input rewriting, so it still gets a hard block.
# Pass "codex" as the first argument from the Codex hook wiring.

set -euo pipefail

runtime="${1:-claude}"

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

normalised_command="${command_str//$'\n'/;}"
hcom_send_pattern='(^|[;&|][[:space:]]*)(command[[:space:]]+)?hcom[[:space:]]+send([[:space:]]|$)'
ack_intent_pattern='(^|[[:space:]])--intent(=|[[:space:]]+)ack([[:space:]]|$)'
inform_intent_pattern='(^|[[:space:]])--intent(=|[[:space:]]+)inform([[:space:]]|$)'  # Finds acknowledgement text disguised as a result.
acknowledgement_text_pattern=$'^(Acknowledged|Acknowledgement|Understood|I will|I\'ll|I’ll|Will do)([[:space:][:punct:]]|$)'  # Covers common acknowledgement-only openings.

message_text="${normalised_command#* -- }"  # HCOM message after the option separator.
message_text="${message_text#\'}"
message_text="${message_text#\"}"

is_acknowledgement=false  # True when the command is an acknowledgement-only HCOM send.

if [[ "$normalised_command" =~ $hcom_send_pattern ]] \
	&& { [[ "$normalised_command" =~ $ack_intent_pattern ]] \
		|| { [[ "$normalised_command" =~ $inform_intent_pattern ]] \
			&& [[ "$message_text" =~ $acknowledgement_text_pattern ]]; }; }; then
	is_acknowledgement=true
fi

[[ "$is_acknowledgement" == true ]] || exit 0

if [[ "$runtime" == "codex" ]]; then
	printf 'guard-hcom-ack: blocked: HCOM team roles do not send acknowledgement messages. Nothing in this command ran. Re-run any other work it contained without the acknowledgement, finish the task, and send your terminal result, blocker, decision, or correction. If there was no task, wait silently.\n' >&2
	exit 2
fi

no_op_command="printf 'guard-hcom-ack: acknowledgement not sent; HCOM roles wait silently\n'"  # Replacement that sends nothing and leaves no error to react to.

printf '%s' "$input" | jq -c --arg command "$no_op_command" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = $command)}}'
