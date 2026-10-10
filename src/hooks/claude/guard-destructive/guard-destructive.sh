#!/usr/bin/env bash
#
# guard-destructive — PreToolUse:Bash hook for Claude and Codex.
#
# Enforces the handful of this repo's rules that are unconditional "never"
# statements (no stated "unless the user explicitly asks" exception): sudo,
# filesystem wipes, git config mutation, and rm (trash is the mandated
# replacement). Rules with a documented exception — force-push, hard reset,
# --no-verify, etc. — stay prose-governed, since a stateless hook can't tell
# whether that exception was granted for this call.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

# Writes the block reason to stderr and exits 2, which both Claude and Codex
# treat as "deny this tool call" for a PreToolUse hook.
#
# @param  {string}  reason
#     Human-readable reason shown to the model.
block() {
	printf 'guard-destructive: blocked — %s. Run it yourself in a terminal if it is genuinely needed.\n' "$1" >&2
	exit 2
}

[[ "$command_str" =~ (^|[[:space:]])sudo([[:space:]]|$) ]] && block "sudo (privilege escalation)"
[[ "$command_str" =~ (^|[[:space:]])mkfs([.[:alnum:]]*)?([[:space:]]|$) ]] && block "mkfs (filesystem creation/wipe)"
[[ "$command_str" =~ (^|[[:space:]])dd([[:space:]].*)?[[:space:]]of=/dev/ ]] && block "dd writing to a block device"
[[ "$command_str" =~ (^|[[:space:]])git[[:space:]]+config([[:space:]]|$) ]] && block "git config mutation"

if [[ "$command_str" =~ (^|[;&|][[:space:]]*)rm([[:space:]]|$) ]] \
	&& ! [[ "$command_str" =~ (^|[[:space:]])(git|npm|pnpm|yarn)[[:space:]]+rm([[:space:]]|$) ]]; then
	block "rm — use trash instead"
fi

exit 0
