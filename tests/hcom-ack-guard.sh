#!/usr/bin/env bash
# Covers the shared guard that suppresses acknowledgement-only HCOM messages.
#
# The guard rewrites an acknowledgement send to a no-op on both runtimes through
# hookSpecificOutput.updatedInput. On Codex the response also allows the
# replaced command, because Codex rejects a replacement without that decision.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

TEST_STATUS=0  # Exit status of the most recent hook run.
STDOUT_FILE="$TEST_ROOT/stdout.txt"  # Standard output of the most recent hook run.
STDERR_FILE="$TEST_ROOT/stderr.txt"  # Standard error of the most recent hook run.
EXPECTED_NO_OP_COMMAND="printf 'guard-hcom-ack: acknowledgement not sent; nothing in this command ran; re-run any other work in the command without the acknowledgement\n'"  # Command returned for acknowledgement sends.

# Runs the HCOM acknowledgement guard with one Bash tool payload. The payload
# carries a working directory as well as the command, so the Codex assertion can
# check that the rewrite keeps the rest of the tool input.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  runtime
#     Runtime argument for the hook ("codex" for Codex, empty for Claude).
run_guard() {
	local command="$1"  # Shell command placed in the tool payload.
	local runtime="${2:-}"  # Runtime argument forwarded to the hook.

	set +e
	jq -n --arg command "$command" '{tool_name: "Bash", tool_input: {command: $command, workdir: "/tmp"}}' \
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

	if ! jq -e --arg command "$EXPECTED_NO_OP_COMMAND" \
		'.hookSpecificOutput == {hookEventName: "PreToolUse", updatedInput: {command: $command, workdir: "/tmp"}}' \
		"$STDOUT_FILE" > /dev/null; then
		printf 'Actual Claude hook output:\n' >&2
		cat "$STDOUT_FILE" >&2
		fail 'Expected a PreToolUse rewrite with the no-op command, preserved workdir, and no permission decision'
	fi
}

# Asserts that an acknowledgement send is rewritten to a no-op on Codex.
#
# @param  {string}  command
#     Shell command expected to be suppressed.
assert_swallowed_codex() {
	local command="$1"  # Acknowledgement command expected to be rewritten.

	run_guard "$command" "codex"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$STDERR_FILE"
	if ! jq -e --arg command "$EXPECTED_NO_OP_COMMAND" \
		'.hookSpecificOutput == {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: {command: $command, workdir: "/tmp"}}' \
		"$STDOUT_FILE" > /dev/null; then
		printf 'Actual Codex hook output:\n' >&2
		cat "$STDOUT_FILE" >&2
		fail 'Expected an allowed PreToolUse rewrite with the no-op command and preserved workdir'
	fi
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

assert_swallowed_codex "hcom send @peer --intent ack -- 'Acknowledged'"
assert_swallowed_codex "hcom send @peer --intent inform -- 'Understood, starting now.'"

assert_allowed "hcom send @peer --intent request -- 'Run checks'"
assert_allowed "hcom send @peer --intent inform -- 'Checks passed'"
assert_allowed "hcom send @peer --intent inform -- 'Correction: formatter log is available'"
assert_allowed "rg -n -- '--intent ack' teams/hcom"
assert_allowed "printf '%s' 'hcom send @peer --intent ack'"

printf '✓ HCOM acknowledgement guard tests passed\n'
