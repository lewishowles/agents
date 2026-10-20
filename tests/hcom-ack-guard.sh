#!/usr/bin/env bash
# Covers the shared guard that suppresses acknowledgement-only HCOM messages.
#
# The guard rewrites an acknowledgement send to a no-op on both runtimes through
# hookSpecificOutput.updatedInput. On Codex the response also allows the
# replaced command, because Codex rejects a replacement without that decision.

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

# The exit status of the most recent hook run.
TEST_STATUS=0
# The standard output of the most recent hook run.
STDOUT_FILE="$TEST_ROOT/stdout.txt"
# The standard error of the most recent hook run.
STDERR_FILE="$TEST_ROOT/stderr.txt"
# The replacement command returned for acknowledgement sends.
EXPECTED_NO_OP_COMMAND="printf 'guard-hcom-ack: acknowledgement not sent; nothing in this command ran; re-run any other work in the command without the acknowledgement\n'"

# Runs the HCOM acknowledgement guard with one Bash tool payload. The payload
# carries a working directory as well as the command, so the Codex assertion can
# check that the rewrite keeps the rest of the tool input.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  runtime
#     Runtime argument for the hook ("codex" for Codex, empty for Claude).
run_guard() {
	# The shell command placed in the tool payload.
	local command="$1"
	# The runtime argument forwarded to the hook.
	local runtime="${2:-}"

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
	# The acknowledgement command expected to be rewritten.
	local command="$1"

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
	# The acknowledgement command expected to be rewritten.
	local command="$1"

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
	# The command expected to pass without hook output.
	local command="$1"

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

assert_swallowed "team-send scout --intent ack --reply-to 42 < body.txt"
assert_swallowed "team-send reviewer --intent=ack --reply-to 42 < body.txt"
assert_swallowed "command team-send orchestrator --intent ack --reply-to 42 < body.txt"
assert_swallowed "/usr/local/bin/team-send implementer --intent=ack --reply-to 42 < body.txt"
assert_swallowed "printf 'done'; team-send scout --intent ack --reply-to 42 < body.txt"
assert_swallowed "printf 'Received.' | team-send orchestrator --intent ack --reply-to 42"

assert_swallowed_codex "team-send scout --intent ack --reply-to 42 < body.txt"
assert_swallowed_codex "command /usr/local/bin/team-send reviewer --intent=ack --reply-to 42 < body.txt"
assert_swallowed_codex "printf 'Received.' | team-send orchestrator --intent ack --reply-to 42"

assert_swallowed "git diff -- README.md && hcom send @peer --intent ack -- ok"
assert_swallowed_codex "git diff -- README.md && hcom send @peer --intent ack -- ok"
assert_swallowed "rg -- foo src | team-send scout --intent ack --reply-to 42"
assert_swallowed_codex "rg -- foo src | team-send scout --intent ack --reply-to 42"

# A here-string followed by a real acknowledgement, which must still be blocked.
here_string_then_ack=$(cat <<'COMMAND'
cat <<<word
hcom send @peer --intent ack -- ok
COMMAND
)

# An arithmetic shift followed by a real acknowledgement, which must still be blocked.
arithmetic_shift_then_ack=$(cat <<'COMMAND'
x=$((1<<4))
hcom send @peer --intent ack -- ok
COMMAND
)

# An arithmetic shift with spaces followed by a real acknowledgement.
spaced_arithmetic_shift_then_ack=$(cat <<'COMMAND'
x=$(( 1 << 4 ))
hcom send @peer --intent ack -- ok
COMMAND
)

# A tab-stripping heredoc whose closing word has two leading tabs before a real acknowledgement.
tabbed_heredoc_then_ack=$(cat <<'COMMAND'
cat <<-EOF
body
		EOF
hcom send @peer --intent ack -- ok
COMMAND
)

# Two heredoc bodies followed by a real acknowledgement.
two_heredocs_then_ack=$(cat <<'COMMAND'
cat <<A <<B
first body
A
second body
B
hcom send @peer --intent ack -- ok
COMMAND
)

assert_swallowed "$here_string_then_ack"
assert_swallowed_codex "$here_string_then_ack"
assert_swallowed "$arithmetic_shift_then_ack"
assert_swallowed_codex "$arithmetic_shift_then_ack"
assert_swallowed "$spaced_arithmetic_shift_then_ack"
assert_swallowed_codex "$spaced_arithmetic_shift_then_ack"
assert_swallowed "$tabbed_heredoc_then_ack"
assert_swallowed_codex "$tabbed_heredoc_then_ack"
assert_swallowed "$two_heredocs_then_ack"
assert_swallowed_codex "$two_heredocs_then_ack"

# The report in HCOM event 8059 quotes a refused acknowledgement in a heredoc.
report_with_quoted_ack=$(cat <<'COMMAND'
cat >> /tmp/components-task-review-receipt.txt <<'EOF'

Delivery note: the earlier `hcom send @components-orchestrator --intent ack --reply-to 7959 --name vari --file ...` attempt was rejected by `guard-hcom-ack` with “acknowledgement not sent; nothing in this command ran”.
EOF
team-send orchestrator --intent inform --reply-to 7959 < /tmp/components-task-review-receipt.txt
COMMAND
)

# A report whose heredoc body quotes a team-send acknowledgement, sent as inform in the same call.
team_quote_with_inform=$(cat <<'COMMAND'
cat > /tmp/team-report.txt <<'EOF'
team-send scout --intent ack
EOF
team-send orchestrator --intent inform --reply-to 42 < /tmp/team-report.txt
COMMAND
)

# A send-looking line inside the second of two heredoc bodies is still message text.
ack_inside_second_heredoc=$(cat <<'COMMAND'
cat <<A <<B
first body
A
hcom send @peer --intent ack -- ok
B
COMMAND
)

assert_allowed "hcom send @peer --intent request -- 'Run checks'"
assert_allowed "hcom send @peer --intent inform -- 'Checks passed'"
assert_allowed "hcom send @peer --intent inform -- 'Correction: formatter log is available'"
assert_allowed "hcom send @peer --intent inform -- 'Checks passed; earlier command used --intent ack'"
assert_allowed "hcom send @peer --intent inform -- 'Checks passed; hcom send @peer --intent ack was rejected'"
assert_allowed "rg -n -- '--intent ack' teams/hcom"
assert_allowed "printf '%s' 'hcom send @peer --intent ack'"
assert_allowed "team-send scout --intent request < body.txt"
assert_allowed "team-send reviewer --intent inform < body.txt"
assert_allowed "team-send scout --intent inform < acknowledgement.txt"
assert_allowed "printf 'Checks passed' | team-send orchestrator --intent inform --reply-to 42"
assert_allowed "printf '%s' 'team-send scout --intent ack'"
assert_allowed "printf 'a && hcom send @p --intent ack -- x'"
assert_allowed "$report_with_quoted_ack"
assert_allowed "$team_quote_with_inform"
assert_allowed "$ack_inside_second_heredoc"

printf '✓ HCOM acknowledgement guard tests passed\n'
