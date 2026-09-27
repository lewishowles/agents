#!/usr/bin/env bash
# Covers the shared tool-call checkpoint. Only sessions with an HCOM team tag
# count tool calls, and the planning and insights review workflows skip the
# count. For counted sessions, every tool call counts, the advisory fires once
# when the limit is reached, and nothing fires after it. HCOM Scouts and
# Implementers get the larger worker limit from HCOM_TAG, and
# AGENT_TOOL_CALL_LIMIT overrides every other limit for a session. PreCompact
# returns the same handoff context with or without a team tag.

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
AGENT_TAG=""  # Value passed as HCOM_TAG; __UNSET__ removes it.
PLANNING_WORKFLOW=""  # Value passed as HCOM_PLANNING_WORKFLOW.
INSIGHTS_REVIEW_WORKFLOW=""  # Value passed as HCOM_INSIGHTS_REVIEW_WORKFLOW.

# Starts a fresh counter scenario with its own session ID and limit override.
#
# @param  {string}  name
#     Scenario name used in the session ID.
# @param  {string}  limit_override
#     AGENT_TOOL_CALL_LIMIT value for the scenario; empty leaves it unset.
# @param  {string}  agent_name
#     HCOM_NAME value for the scenario; empty leaves it unset.
# @param  {string}  agent_tag
#     HCOM_TAG value for the scenario. It defaults to a reviewer tag so the
#     hook counts calls; pass an empty string for an empty tag, or __UNSET__
#     to remove the variable.
start_session() {
	local name="$1"
	local limit_override="$2"
	local agent_name="${3:-}"
	local agent_tag="${4-Agents-reviewer}"

	SESSION="checkpoint-test-$name-$$"
	STATE_FILE="$TEST_ROOT/agent-tool-call-checkpoints/claude-$SESSION"
	LIMIT_OVERRIDE="$limit_override"
	AGENT_NAME="$agent_name"
	AGENT_TAG="$agent_tag"
	PLANNING_WORKFLOW=""
	INSIGHTS_REVIEW_WORKFLOW=""
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
	local -a hook_env=(env -u HCOM_TAG TMPDIR="$TEST_ROOT" AGENT_TOOL_CALL_LIMIT="$LIMIT_OVERRIDE" HCOM_NAME="$AGENT_NAME" HCOM_PLANNING_WORKFLOW="$PLANNING_WORKFLOW" HCOM_INSIGHTS_REVIEW_WORKFLOW="$INSIGHTS_REVIEW_WORKFLOW")  # The env command that runs the hook with this scenario's variables; HCOM_TAG is removed unless the scenario sets it.

	if [[ "$AGENT_TAG" != "__UNSET__" ]]; then
		hook_env+=("HCOM_TAG=$AGENT_TAG")
	fi

	jq -n --arg session "$SESSION" --arg tool "$tool_name" \
		'{hook_event_name: "PreToolUse", session_id: $session, tool_name: $tool, tool_input: {}}' \
		| "${hook_env[@]}" bash "$HOOK" claude > "$output_file"
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
assert_advisory() {
	local tool_name="$1"
	local output_file="$TEST_ROOT/advisory.json"

	run_hook "$tool_name" "$output_file"

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

# Untagged sessions stay silent even after the configured threshold.
start_session "tag-unset" "2" "" "__UNSET__"
assert_silent "Read" "missing"
assert_silent "Edit" "missing"
assert_silent "Write" "missing"

start_session "tag-empty" "2" "" ""
assert_silent "Read" "missing"
assert_silent "Edit" "missing"
assert_silent "Write" "missing"

# Both review workflows skip counting for tagged peers.
start_session "planning" "2" "maki" "Agents-reviewer"
PLANNING_WORKFLOW="1"
assert_silent "Read" "missing"
assert_silent "Edit" "missing"
assert_silent "Write" "missing"

start_session "insights-review" "2" "maki" "Agents-reviewer"
INSIGHTS_REVIEW_WORKFLOW="1"
assert_silent "Read" "missing"
assert_silent "Edit" "missing"
assert_silent "Write" "missing"

# PreCompact returns the same context checkpoint with and without HCOM_TAG for both runtimes.
for runtime in claude codex; do
	jq -n '{hook_event_name: "PreCompact"}' | env -u HCOM_TAG bash "$HOOK" "$runtime" > "$TEST_ROOT/precompact-untagged.json"
	jq -n '{hook_event_name: "PreCompact"}' | HCOM_TAG="Agents-reviewer" bash "$HOOK" "$runtime" > "$TEST_ROOT/precompact-tagged.json"
	assert_equals "$(cat "$TEST_ROOT/precompact-untagged.json")" "$(cat "$TEST_ROOT/precompact-tagged.json")"
	if [[ "$runtime" == "claude" ]]; then
		assert_equals "$(jq -r '(.hookSpecificOutput.additionalContext // "") | startswith("CONTEXT CHECKPOINT")' "$TEST_ROOT/precompact-untagged.json")" "true"
	else
		assert_equals "$(jq -r '(.systemMessage // "") | startswith("CONTEXT CHECKPOINT")' "$TEST_ROOT/precompact-untagged.json")" "true"
	fi
done

# Default limit: reads and edits both count, the 20th call fires, then the counter freezes.
start_session "default" ""
assert_silent "Read" "1"
assert_silent "mcp__serena__find_symbol" "2"
assert_silent "Edit" "3"
assert_silent "Bash" "4"
fill_to_limit 20
assert_advisory "Write"
assert_silent "Write" "20"
assert_silent "Read" "20"

# Overridden limit: the advisory moves to the configured call.
start_session "override" "5"
assert_silent "Read" "1"
fill_to_limit 5
assert_advisory "Edit"
assert_silent "Edit" "5"

# Invalid override falls back to the default limit.
start_session "invalid" "lots"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Write"

# A bare HCOM name uses the worker limit from a role-only HCOM tag.
start_session "implementer" "" "maki" "Agents-implementer"
assert_silent "Read" "1"
fill_to_limit 40
assert_advisory "Edit"
assert_silent "Edit" "40"

# A team-labelled HCOM tag also uses the worker limit.
start_session "team-implementer" "" "maki" "Agents-dev-tools-implementer"
assert_silent "Read" "1"
fill_to_limit 40
assert_advisory "Edit"

start_session "scout" "" "rune" "Agents-scout"
assert_silent "Read" "1"
fill_to_limit 40
assert_advisory "Bash"

# Reviewer and orchestrator tags keep the default limit.
start_session "reviewer" "" "maki" "Agents-reviewer"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Bash"

start_session "orchestrator" "" "maki" "Agents-orchestrator"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Bash"

# An explicit override beats the role limit.
start_session "worker-override" "7" "maki" "Agents-dev-tools-implementer"
assert_silent "Read" "1"
fill_to_limit 7
assert_advisory "Edit"

printf '✓ tool-call checkpoint tests passed\n'
