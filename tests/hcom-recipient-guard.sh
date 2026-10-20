#!/usr/bin/env bash
# Checks that HCOM sends name a role tag before their message body.

set -euo pipefail

# The folder containing this test and its shared helpers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the guard under test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# The temporary folder for output from each hook run.
TEST_ROOT=$(mktemp -d)

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

# The exit status of the last hook run.
TEST_STATUS=0
# The standard output of the last hook run.
STDOUT_FILE="$TEST_ROOT/stdout.txt"
# The standard error of the last hook run.
STDERR_FILE="$TEST_ROOT/stderr.txt"

# Runs the recipient guard with one Bash tool command.
#
# @param  {string}  command
#     Shell command presented to the hook.
run_guard() {
	# The shell command presented to the guard.
	local command="$1"

	set +e
	jq -n --arg command "$command" '{tool_name: "Bash", tool_input: {command: $command}}' \
		| bash "$REPO_DIR/src/hooks/shared/guard-hcom-recipient.sh" > "$STDOUT_FILE" 2> "$STDERR_FILE"
	TEST_STATUS=$?
	set -e
}

# Checks that a send without a recipient is blocked with routing guidance.
#
# @param  {string}  command
#     Shell command expected to be blocked.
assert_blocked() {
	# The send expected to be blocked for lacking a recipient.
	local command="$1"

	run_guard "$command"

	assert_equals "$TEST_STATUS" "2"
	assert_empty "$STDOUT_FILE"
	assert_contains "$STDERR_FILE" '@<repo>-<role>-'
}

# Checks that a command leaves the hook without output.
#
# @param  {string}  command
#     Shell command expected to pass.
assert_allowed() {
	# A command expected to pass because it names a recipient or sends nothing through HCOM.
	local command="$1"

	run_guard "$command"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$STDOUT_FILE"
	assert_empty "$STDERR_FILE"
}

assert_blocked 'hcom send --intent inform --file /tmp/report.txt'
assert_blocked 'n=${#items[@]}; hcom send --intent inform --file /tmp/r.txt'
assert_blocked 'hcom send -- --help'
assert_blocked 'hcom send -- -h'
assert_blocked 'hcom send --reply-to 123 --intent inform --file /tmp/report.txt'
assert_blocked "hcom send --intent inform -- 'Report for @agent-tools-orchestrator-'"
assert_blocked 'hcom send --intent inform --file @agent-tools-orchestrator-'
assert_blocked "printf '@agent-tools-orchestrator-' | hcom send --intent inform"
assert_blocked "receipt_file=\$(mktemp); printf 'done'; hcom send --intent inform --file \"\$receipt_file\""
assert_blocked 'hcom send @agent-tools-orchestrator- --intent inform --file /tmp/report.txt; hcom send --reply-to 123 --file /tmp/report.txt'
assert_blocked $'receipt_file=$(mktemp)\ncat > "$receipt_file" <<\'EOF\'\n@agent-tools-orchestrator-\nEOF\nhcom send --intent inform --file "$receipt_file"'
assert_blocked $'cat <<< EOF\nhcom send --intent inform --file /tmp/report.txt'
assert_blocked $'echo "a <<EOF"\nhcom send --intent inform --file /tmp/report.txt'
assert_blocked $'# It\'s a comment\nhcom send --intent inform --file /tmp/report.txt'
assert_blocked $'printf done # It\'s a comment\nhcom send --intent inform --file /tmp/report.txt'
assert_blocked '/opt/homebrew/bin/hcom send --intent inform --file /tmp/report.txt'
assert_blocked 'hcom --name leti send --intent inform --file /tmp/report.txt'

assert_allowed 'hcom send @agent-tools-orchestrator- --intent inform --file /tmp/report.txt'
assert_allowed 'hcom send --help -- --file /tmp/report.txt'
assert_allowed 'hcom send -h -- --file /tmp/report.txt'
assert_allowed '/opt/homebrew/bin/hcom --name leti send @agent-tools-orchestrator- --file /tmp/report.txt'
assert_allowed "hcom send @agent-tools-orchestrator- --intent inform -- 'Done'"
assert_allowed 'hcom send @agent-tools-orchestrator- --intent inform --reply-to 123 --file /tmp/report.txt'
assert_allowed 'receipt_file=$(mktemp); hcom send @agent-tools-orchestrator- --intent inform --file "$receipt_file"'
assert_allowed 'hcom list --json'
assert_allowed 'hcom events --last 1'
assert_allowed "printf '%s' 'hcom send --intent inform --file /tmp/report.txt'"
assert_allowed $'cat <<\'EOF\'\nhcom send --file /tmp/report.txt\nEOF\nhcom list --json'

printf '✓ HCOM recipient guard tests passed\n'
