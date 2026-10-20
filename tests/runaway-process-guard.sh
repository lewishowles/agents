#!/usr/bin/env bash
# Covers the shared guard that blocks unbounded busy-loop shell commands.

set -euo pipefail

# The folder containing this test and its shared helpers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the guard under test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# A temporary folder for captured guard output.
TEST_ROOT=$(mktemp -d)

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

# The exit status of the latest guard run.
TEST_STATUS=0

# Runs the runaway-process guard with one Bash tool payload.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  output_file
#     File that receives the hook's standard error.
run_guard() {
	# The shell command passed to the guard.
	local command="$1"
	# The file that captures the guard's standard error.
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
	# The shell command expected to be blocked.
	local command="$1"
	# The file that captures a blocked command's error output.
	local output_file="$TEST_ROOT/blocked.txt"

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "2"
}

# Asserts that a command passes without hook output.
#
# @param  {string}  command
#     Shell command expected to be allowed.
assert_allowed() {
	# The shell command expected to pass.
	local command="$1"
	# The file checked for unexpected guard output.
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
