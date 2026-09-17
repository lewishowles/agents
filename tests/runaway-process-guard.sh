#!/usr/bin/env bash
# Covers the shared guard that blocks unbounded busy-loop shell commands.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

TEST_STATUS=0

# Runs the runaway-process guard with one Bash tool payload.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  output_file
#     File that receives the hook's standard error.
run_guard() {
	local command="$1"
	local output_file="$2"

	set +e
	jq -n --arg command "$command" '{tool_name: "Bash", tool_input: {command: $command}}' \
		| bash "$REPO_DIR/src/hooks/shared/guard-runaway-process.sh" 2> "$output_file"
	TEST_STATUS=$?
	set -e
}

# Asserts that a command is blocked.
#
# @param  {string}  command
#     Shell command expected to be denied.
assert_blocked() {
	local command="$1"
	local output_file="$TEST_ROOT/blocked.txt"

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "2"
}

# Asserts that a command passes without hook output.
#
# @param  {string}  command
#     Shell command expected to be allowed.
assert_allowed() {
	local command="$1"
	local output_file="$TEST_ROOT/allowed.txt"

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$output_file"
}

assert_blocked "while :; do :; done"
assert_blocked "while true; do echo hi; done"
assert_blocked "until false; do echo waiting; done"
assert_blocked "for ((;;)); do echo x; done"
assert_blocked "for (( ; ; )); do echo x; done"
assert_blocked "_docs_check & while :; do :; done"
assert_blocked "while :; do :; done &"
assert_blocked "bash -c 'while :; do :; done'"
assert_blocked "sh -c \"until false; do :; done\""

assert_allowed "while true; do echo hi; sleep 5; done"
assert_allowed "timeout 5 bash -c 'while :; do :; done'"
assert_allowed "while :; do echo x; if [ -f /tmp/f ]; then break; fi; done"
assert_allowed "while read -r line; do echo \"\$line\"; done < file"
assert_allowed "while read -r -t 5 line; do echo \"\$line\"; done"
assert_allowed "while [ -f /tmp/lock ]; do sleep 1; done"
assert_allowed "rg -n 'while true' src/rules"
assert_allowed "git commit -m 'explain the while :; do :; done incident'"
assert_allowed "echo 'while :; do :; done' >> notes.md"
assert_allowed "npm run build"
assert_allowed "git status --short"

printf '✓ runaway-process guard tests passed\n'
