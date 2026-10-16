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

normalised_command="${command_str//$'\n'/;}"
hcom_send_pattern='(^|[;&|][[:space:]]*)(command[[:space:]]+)?hcom[[:space:]]+send([[:space:]]|$)'
# Finds a team-send to a core role, written role first as the team rules show it. Its body arrives on stdin, so only the intent can mark it as an acknowledgement.
team_send_pattern='(^|[;&|][[:space:]]*)(command[[:space:]]+)?([^[:space:];&|]+/)?team-send[[:space:]]+(orchestrator|scout|implementer|reviewer)([[:space:]]|$)'
ack_intent_pattern='(^|[[:space:]])--intent(=|[[:space:]]+)ack([[:space:]]|$)'
# Finds acknowledgement text disguised as a result.
inform_intent_pattern='(^|[[:space:]])--intent(=|[[:space:]]+)inform([[:space:]]|$)'
# Covers common acknowledgement-only openings.
acknowledgement_text_pattern=$'^(Acknowledged|Acknowledgement|Understood|I will|I\'ll|I’ll|Will do)([[:space:][:punct:]]|$)'

# HCOM message after the option separator.
message_text="${normalised_command#* -- }"
message_text="${message_text#\'}"
message_text="${message_text#\"}"

# True when the command is an acknowledgement-only team message.
is_acknowledgement=false

if [[ "$normalised_command" =~ $hcom_send_pattern ]] \
	&& { [[ "$normalised_command" =~ $ack_intent_pattern ]] \
		|| { [[ "$normalised_command" =~ $inform_intent_pattern ]] \
			&& [[ "$message_text" =~ $acknowledgement_text_pattern ]]; }; }; then
	is_acknowledgement=true
elif [[ "$normalised_command" =~ $team_send_pattern ]] \
	&& [[ "$normalised_command" =~ $ack_intent_pattern ]]; then
	is_acknowledgement=true
fi

[[ "$is_acknowledgement" == true ]] || exit 0

# Replacement that explains the suppressed command.
no_op_command="printf 'guard-hcom-ack: acknowledgement not sent; nothing in this command ran; re-run any other work in the command without the acknowledgement\n'"

printf '%s' "$input" | jq -c --arg command "$no_op_command" --arg runtime "$runtime" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = $command)}}
	| if $runtime == "codex" then .hookSpecificOutput.permissionDecision = "allow" else . end'
