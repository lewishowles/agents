#!/usr/bin/env bash
#
# guard-runaway-process — PreToolUse:Bash hook for Claude and Codex.
#
# Blocks the one shell shape behind the "ad-hoc verification safety" rule: a
# command whose loop is an unbounded busy spin with nothing to yield the CPU or
# end the loop. A previous agent used `while :; do :; done` to fake a hung
# process, lost track of the background child, and left it running at ~100% CPU
# for eight days.
#
# Only a header that is literally `while :` / `while true` / `until false` /
# `for (( ; ; ))` counts, and only when the command carries no `sleep`,
# `timeout`, `break`, or `read -t`. A conditional loop (`while read`,
# `while [ -f lock ]`) or a poll that sleeps between iterations is left alone,
# as is `timeout … bash -c 'while :; …'`, the sanctioned bounded form.
#
# Quoted spans are stripped before the main check so a command that only mentions
# the pattern in text (a commit message, an `echo`, an `rg` search) is not
# blocked. A busy loop handed straight to `bash -c` / `sh -c` is still caught
# unless a `timeout` wraps it.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

# Start-of-statement boundary: line start, or a separator, or an opening quote
# (so a loop inside `bash -c '…'` is still anchored).
boundary='(^|[[:space:];&|('\''"])'

# A loop header that never terminates on its own. Required to be followed by `;`
# or `do` so a bare mention such as `rg while true` is not read as a loop.
while_spin="${boundary}"'while[[:space:]]+(:|true)[[:space:]]*(;|$|do([[:space:]]|$))'
until_spin="${boundary}"'until[[:space:]]+false[[:space:]]*(;|$|do([[:space:]]|$))'
for_spin="${boundary}"'for[[:space:]]*\(\([[:space:]]*;[[:space:]]*;[[:space:]]*\)\)'

# Anything that makes the loop yield the CPU or stop. Presence anywhere in the
# scanned text is enough to allow it; matching loosely here favours letting the
# command through.
mitigation='(^|[[:space:]])(sleep|usleep|timeout)([[:space:]]|$)|(^|[[:space:];{}(&|])[[:space:]]*break([[:space:]]|;|$)|read[[:space:]][^;&|]*-[a-zA-Z]*t'

# A command that runs a script string, where the busy loop sits inside the `-c`
# argument rather than in the command text itself.
exec_c='(^|[[:space:]])(bash|sh|zsh|dash|ksh)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-c([[:space:]]|$)'
has_timeout='(^|[[:space:]])timeout([[:space:]]|$)'

# Reports whether the given text contains an unbounded busy-loop header.
#
# @param  {string}  text
#     Command text to scan.
has_spin() {
	# Command text to scan for a busy-loop header.
	local text="$1"

	[[ "$text" =~ $while_spin || "$text" =~ $until_spin || "$text" =~ $for_spin ]]
}

# Writes the block reason to stderr and exits 2, which both Claude and Codex
# treat as "deny this tool call" for a PreToolUse hook.
#
# @param  {string}  reason
#     Human-readable reason shown to the model.
block() {
	printf 'guard-runaway-process: blocked — %s. Use sleep, timeout, or a blocking read, and give any wait a short explicit bound (see the ad-hoc verification safety rule).\n' "$1" >&2
	exit 2
}

# Command text with single- and double-quoted spans removed, so text that only
# mentions a busy loop does not trip the guard.
unquoted="$(printf '%s' "$command_str" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')" || exit 0

if has_spin "$unquoted" && ! [[ "$unquoted" =~ $mitigation ]]; then
	block "unbounded busy loop with no sleep, timeout, or break"
fi

if [[ "$command_str" =~ $exec_c ]] \
	&& has_spin "$command_str" \
	&& ! [[ "$command_str" =~ $has_timeout ]] \
	&& ! [[ "$command_str" =~ $mitigation ]]; then
	block "unbounded busy loop passed to a shell with no timeout"
fi

exit 0
