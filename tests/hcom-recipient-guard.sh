#!/usr/bin/env bash
# Checks that HCOM sends name a recipient, and that core team roles reach
# teammates through team-send rather than a role tag.

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
# @param  {string}  sender_tag
#     The sender's HCOM tag, when present.
run_guard() {
	# The shell command presented to the guard.
	local command="$1"
	# The sender's HCOM tag, if one is supplied.
	local sender_tag="${2:-}"
	# The guard's environment, with HCOM_TAG unset unless a sender tag is given.
	local -a guard_env=(env -u HCOM_TAG)
	if [[ -n "$sender_tag" ]]; then
		guard_env=(env HCOM_TAG="$sender_tag")
	fi

	set +e
	jq -n --arg command "$command" '{tool_name: "Bash", tool_input: {command: $command}}' \
		| "${guard_env[@]}" bash "$REPO_DIR/src/hooks/shared/guard-hcom-recipient.sh" > "$STDOUT_FILE" 2> "$STDERR_FILE"
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

# Checks that a core-role sender cannot send to a role tag.
#
# @param  {string}  command
#     Shell command expected to be blocked.
# @param  {string}  role
#     The recipient role that team-send must resolve.
assert_role_blocked() {
	# The role-tag send expected to be blocked.
	local command="$1"
	# The recipient role expected in the guidance.
	local role="$2"

	run_guard "$command" 'agent-tools-implementer'

	assert_equals "$TEST_STATUS" "2"
	assert_empty "$STDOUT_FILE"
	assert_contains "$STDERR_FILE" 'guard-hcom-recipient: blocked:'
	assert_contains "$STDERR_FILE" 'Nothing in this command ran.'
	assert_contains "$STDERR_FILE" "team-send $role"
	assert_contains "$STDERR_FILE" 'if team-send refuses, report that instead of sending by hand.'
}

# Checks that a command leaves the hook without output.
#
# @param  {string}  command
#     Shell command expected to pass.
# @param  {string}  sender_tag
#     The sender's HCOM tag, when present.
assert_allowed() {
	# A command expected to pass: it names an agent or @bigboss rather than a role
	# tag, comes from a sender that is not a core role or has no tag, or sends
	# nothing through HCOM.
	local command="$1"
	# The sender's HCOM tag, if one is supplied.
	local sender_tag="${2:-}"

	run_guard "$command" "$sender_tag"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$STDOUT_FILE"
	assert_empty "$STDERR_FILE"
}

assert_blocked 'hcom send --intent inform --file /tmp/report.txt'
# The guard must see the command exactly as typed, so ${#items[@]} stays unexpanded.
# shellcheck disable=SC2016
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
# The guard must see the command exactly as typed, so $(mktemp) and $receipt_file stay unexpanded.
# shellcheck disable=SC2016
assert_allowed 'receipt_file=$(mktemp); hcom send @agent-tools-orchestrator- --intent inform --file "$receipt_file"'
assert_allowed 'hcom list --json'
assert_allowed 'hcom events --last 1'
assert_allowed "printf '%s' 'hcom send --intent inform --file /tmp/report.txt'"
assert_allowed $'cat <<\'EOF\'\nhcom send --file /tmp/report.txt\nEOF\nhcom list --json'

# Each core role, sent to as a role tag with and without its trailing hyphen.
for role in orchestrator scout implementer reviewer; do
	assert_role_blocked "hcom send @agent-tools-$role --intent inform --file /tmp/report.txt" "$role"
	assert_role_blocked "hcom send @agent-tools-$role- --intent inform --file /tmp/report.txt" "$role"
done

assert_role_blocked 'hcom send @bigboss @agent-tools-scout- --intent inform --file /tmp/report.txt' scout
assert_role_blocked 'hcom send @agent-tools-scout-lohi @agent-tools-reviewer --intent inform --file /tmp/report.txt' reviewer
assert_role_blocked 'hcom send @agent-tools-scout --file /tmp/report.txt; echo done' scout
assert_role_blocked 'hcom send --help; hcom send @agent-tools-scout- --file /tmp/report.txt' scout

run_guard 'hcom send --intent inform --file /tmp/report.txt' 'agent-tools-implementer'
assert_equals "$TEST_STATUS" "2"
assert_empty "$STDOUT_FILE"
assert_contains "$STDERR_FILE" 'team-send <role>'
assert_contains "$STDERR_FILE" 'if team-send refuses, report that instead of sending by hand.'

assert_allowed 'hcom send @agent-tools-scout-lohi --intent inform --file /tmp/report.txt' 'agent-tools-implementer'
assert_allowed 'hcom send @bigboss --intent inform --file /tmp/report.txt' 'agent-tools-implementer'
assert_allowed 'hcom send @agent-tools-scout- --help' 'agent-tools-implementer'
assert_allowed 'hcom send @agent-tools-scout- --intent inform --file /tmp/report.txt' 'agent-tools-observer'
assert_allowed 'hcom send @agent-tools-scout- --intent inform --file /tmp/report.txt'
assert_allowed "hcom send @agent-tools-scout-lohi -- 'Report for @agent-tools-reviewer-'" 'agent-tools-implementer'
assert_allowed 'hcom send @agent-tools-scout-lohi --file @agent-tools-reviewer-' 'agent-tools-implementer'
assert_allowed 'hcom send @agent-tools-scout-lohi --base64 @agent-tools-reviewer-' 'agent-tools-implementer'

printf '✓ HCOM recipient guard tests passed\n'
