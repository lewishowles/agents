#!/usr/bin/env bash
# Covers the shared tool-call checkpoint counter: every tool call counts, the
# advisory fires once when the limit is reached, nothing fires after it, HCOM
# Scouts and Implementers get the larger worker limit from HCOM_TAG, and
# AGENT_TOOL_CALL_LIMIT overrides every other limit for a session.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

HOOK="$REPO_DIR/src/hooks/shared/tool-call-checkpoint.sh"  # Script under test.
SESSION=""  # Session ID for the current scenario; set by start_session.
STATE_FILE=""  # Counter file the hook writes under TMPDIR for the current session.
LIMIT_OVERRIDE=""  # Value passed as AGENT_TOOL_CALL_LIMIT; empty leaves it unset.
AGENT_NAME=""  # Value passed as HCOM_NAME; empty leaves it unset.
AGENT_TAG=""  # Value passed as HCOM_TAG; empty leaves it unset.

# Starts a fresh counter scenario with its own session ID and limit override.
#
# @param  {string}  name
#     Scenario name used in the session ID.
# @param  {string}  limit_override
#     AGENT_TOOL_CALL_LIMIT value for the scenario; empty leaves it unset.
# @param  {string}  agent_name
#     HCOM_NAME value for the scenario; empty leaves it unset.
# @param  {string}  agent_tag
#     HCOM_TAG value for the scenario; empty leaves it unset.
start_session() {
	local name="$1"
	local limit_override="$2"
	local agent_name="${3:-}"
	local agent_tag="${4:-}"

	SESSION="checkpoint-test-$name-$$"
	STATE_FILE="$TEST_ROOT/agent-tool-call-checkpoints/claude-$SESSION"
	LIMIT_OVERRIDE="$limit_override"
	AGENT_NAME="$agent_name"
	AGENT_TAG="$agent_tag"
}

# Runs the hook with one PreToolUse payload and captures its standard output.
#
# @param  {string}  tool_name
#     Tool name presented to the hook.
# @param  {string}  output_file
#     File that receives the hook's standard output.
run_hook() {
	local tool_name="$1"
	local output_file="$2"

	jq -n --arg session "$SESSION" --arg tool "$tool_name" \
		'{hook_event_name: "PreToolUse", session_id: $session, tool_name: $tool, tool_input: {}}' \
		| TMPDIR="$TEST_ROOT" AGENT_TOOL_CALL_LIMIT="$LIMIT_OVERRIDE" HCOM_NAME="$AGENT_NAME" HCOM_TAG="$AGENT_TAG" bash "$HOOK" claude > "$output_file"
}

# Asserts the hook produced no output and left the counter at the expected value.
#
# @param  {string}  tool_name
#     Tool name to send.
# @param  {string}  expected_count
#     Counter value expected afterwards.
assert_silent() {
	local tool_name="$1"
	local expected_count="$2"
	local output_file="$TEST_ROOT/silent.txt"
	local actual_count="missing"  # Counter value read back from the state file.

	run_hook "$tool_name" "$output_file"

	assert_empty "$output_file"
	if [[ -f "$STATE_FILE" ]]; then
		IFS= read -r actual_count < "$STATE_FILE"
	fi
	assert_equals "$actual_count" "$expected_count"
}

# Asserts the hook returned the advisory on this call.
#
# @param  {string}  tool_name
#     Tool name to send.
# @param  {string}  expected_limit
#     Tool-call limit expected in the advisory message.
assert_advisory() {
	local tool_name="$1"
	local expected_limit="$2"
	local output_file="$TEST_ROOT/advisory.json"

	run_hook "$tool_name" "$output_file"

	assert_contains "$output_file" "TOOL-CALL CHECKPOINT"
	assert_contains "$output_file" "tool-call limit of $expected_limit reached"
	assert_equals "$(jq -r '.hookSpecificOutput.hookEventName' "$output_file")" "PreToolUse"
}

# Sends silent calls until the counter reaches one below the given limit.
#
# @param  {string}  limit
#     Limit whose final call is left for the caller to send.
fill_to_limit() {
	local limit="$1"
	local count  # Counter value expected after each call.

	for count in $(seq "$(( $(cat "$STATE_FILE") + 1 ))" "$(( limit - 1 ))"); do
		assert_silent "Write" "$count"
	done
}

# Default limit: reads and edits both count, the 20th call fires, then the counter freezes.
start_session "default" ""
assert_silent "Read" "1"
assert_silent "mcp__serena__find_symbol" "2"
assert_silent "Edit" "3"
assert_silent "Bash" "4"
fill_to_limit 20
assert_advisory "Write" "20"
assert_silent "Write" "20"
assert_silent "Read" "20"

# Overridden limit: the advisory moves to the configured call.
start_session "override" "5"
assert_silent "Read" "1"
fill_to_limit 5
assert_advisory "Edit" "5"
assert_silent "Edit" "5"

# Invalid override falls back to the default limit.
start_session "invalid" "lots"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Write" "20"

# A bare HCOM name uses the worker limit from a role-only HCOM tag.
start_session "implementer" "" "maki" "Agents-implementer"
assert_silent "Read" "1"
fill_to_limit 40
assert_advisory "Edit" "40"
assert_silent "Edit" "40"

# A team-labelled HCOM tag also uses the worker limit.
start_session "team-implementer" "" "maki" "Agents-dev-tools-implementer"
assert_silent "Read" "1"
fill_to_limit 40
assert_advisory "Edit" "40"

start_session "scout" "" "rune" "Agents-scout"
assert_silent "Read" "1"
fill_to_limit 40
assert_advisory "Bash" "40"

# Reviewer and orchestrator tags keep the default limit.
start_session "reviewer" "" "maki" "Agents-reviewer"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Bash" "20"

start_session "orchestrator" "" "maki" "Agents-orchestrator"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Bash" "20"

# An explicit override beats the role limit.
start_session "worker-override" "7" "maki" "Agents-dev-tools-implementer"
assert_silent "Read" "1"
fill_to_limit 7
assert_advisory "Edit" "7"

printf '✓ tool-call checkpoint tests passed\n'
