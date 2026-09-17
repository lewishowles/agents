#!/usr/bin/env bash
# Covers the shared guard that suppresses acknowledgement-only HCOM messages.
#
# On Claude (no runtime argument) an acknowledgement send is rewritten to a
# no-op through hookSpecificOutput.updatedInput. On Codex it is a hard block
# (exit 2), because Codex does not support input rewriting.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

TEST_STATUS=0  # Exit status of the most recent hook run.
STDOUT_FILE="$TEST_ROOT/stdout.txt"  # Standard output of the most recent hook run.
STDERR_FILE="$TEST_ROOT/stderr.txt"  # Standard error of the most recent hook run.

# Runs the HCOM acknowledgement guard with one Bash tool payload.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  runtime
#     Runtime argument for the hook ("codex" for the block path, empty for Claude).
run_guard() {
	local command="$1"  # Shell command placed in the tool payload.
	local runtime="${2:-}"  # Runtime argument forwarded to the hook.

	set +e
	jq -n --arg command "$command" '{tool_name: "Bash", tool_input: {command: $command}}' \
		| bash "$REPO_DIR/src/hooks/shared/guard-hcom-ack.sh" ${runtime:+"$runtime"} > "$STDOUT_FILE" 2> "$STDERR_FILE"
	TEST_STATUS=$?
	set -e
}

# Asserts that an acknowledgement send is rewritten to a no-op on Claude.
#
# @param  {string}  command
#     Shell command expected to be suppressed.
assert_swallowed() {
	local command="$1"  # Acknowledgement command expected to be rewritten.

	run_guard "$command"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$STDERR_FILE"
	assert_contains "$STDOUT_FILE" '"updatedInput"'
}

# Asserts that an acknowledgement send is blocked on Codex.
#
# @param  {string}  command
#     Shell command expected to be denied.
assert_blocked_codex() {
	local command="$1"  # Acknowledgement command expected to be blocked.

	run_guard "$command" "codex"

	assert_equals "$TEST_STATUS" "2"
}

# Asserts that a non-acknowledgement command passes untouched on both runtimes.
#
# @param  {string}  command
#     Shell command expected to be allowed.
assert_allowed() {
	local command="$1"  # Command expected to pass without hook output.

	run_guard "$command"
	assert_equals "$TEST_STATUS" "0"
	assert_empty "$STDOUT_FILE"
	assert_empty "$STDERR_FILE"

	run_guard "$command" "codex"
	assert_equals "$TEST_STATUS" "0"
	assert_empty "$STDOUT_FILE"
	assert_empty "$STDERR_FILE"
}

assert_swallowed "hcom send @peer --intent ack -- 'Acknowledged'"
assert_swallowed "hcom send @peer --intent=ack -- 'Acknowledged'"
assert_swallowed "command hcom send @peer --intent ack -- 'Acknowledged'"
assert_swallowed "printf 'done'; hcom send @peer --intent ack -- 'Acknowledged'"
assert_swallowed "hcom send @peer --intent inform -- 'Acknowledged. I will run the checks.'"
assert_swallowed 'hcom send @peer --intent=inform -- "I will run the checks now."'
assert_swallowed "hcom send @peer --intent inform -- 'Understood, starting now.'"

assert_blocked_codex "hcom send @peer --intent ack -- 'Acknowledged'"
assert_blocked_codex "hcom send @peer --intent inform -- 'Understood, starting now.'"

assert_allowed "hcom send @peer --intent request -- 'Run checks'"
assert_allowed "hcom send @peer --intent inform -- 'Checks passed'"
assert_allowed "hcom send @peer --intent inform -- 'Correction: formatter log is available'"
assert_allowed "rg -n -- '--intent ack' teams/hcom"
assert_allowed "printf '%s' 'hcom send @peer --intent ack'"

printf '✓ HCOM acknowledgement guard tests passed\n'
