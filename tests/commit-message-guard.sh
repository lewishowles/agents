#!/usr/bin/env bash
# Covers the shared guard that blocks commit messages in HCOM subordinate reports.

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

# Runs the commit-message guard with one Bash tool payload.
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
		| bash "$REPO_DIR/src/hooks/shared/guard-commit-message.sh" 2> "$output_file"
	TEST_STATUS=$?
	set -e
}

# Asserts that a send is blocked.
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

assert_blocked "hcom send @orch --intent inform -- 'Done. Suggested commit message: feat(auth): add token refresh'"
assert_blocked "hcom send @orch --intent inform -- 'Implementation complete. Commit message: fix(parser): handle empty input'"
assert_blocked $'hcom send @orch --intent inform -- "Report.\nSuggested commit message:\nchore(deps): bump lockfile"'

assert_allowed "hcom send @impl --intent request -- 'Implement the fix and omit any suggested commit message from your report'"
assert_allowed "hcom send @orch --intent inform -- 'Done. Changed src/auth.js; Scout receipt: tests PASS'"
assert_allowed "hcom send @orch --intent inform -- 'Reviewed feat(auth) branch; no findings'"
assert_allowed "git commit -m 'feat(x): y'"
assert_allowed "printf '%s' 'Suggested commit message: feat(x): y'"

printf '✓ commit-message guard tests passed\n'
