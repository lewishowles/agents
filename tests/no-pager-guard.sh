#!/usr/bin/env bash
# Covers the shared guard that blocks misplaced `git ... --no-pager`.

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

# Runs the no-pager guard with one Bash tool payload.
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
		| bash "$REPO_DIR/src/hooks/shared/guard-no-pager.sh" 2> "$output_file"
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

assert_blocked "git diff --no-pager"
assert_blocked "git log --oneline --no-pager"
assert_blocked "git -C /tmp/repo show HEAD --no-pager"
assert_blocked "printf 'x'; git diff --no-pager -- src"

assert_allowed "git --no-pager diff"
assert_allowed "git --no-pager log --oneline"
assert_allowed "git -C /tmp/repo --no-pager diff"
assert_allowed "git -c core.pager=cat --no-pager log"
assert_allowed "git status --short"
assert_allowed "rg -n -- '--no-pager' src/rules"

printf '✓ no-pager guard tests passed\n'
