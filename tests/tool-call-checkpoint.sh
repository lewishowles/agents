#!/usr/bin/env bash
# Covers the shared tool-call checkpoint. Only sessions with an HCOM team tag
# count tool events, and the planning and insights review workflows skip the
# count. Claude counts one PostToolBatch per reply; Codex counts each
# PreModelRequest and sends its saved note on the next PreToolUse. Every five
# rounds the agent gets a note with its count, and at the limit it gets only the
# limit note. HCOM Scouts and Implementers get the larger worker limit from
# HCOM_TAG, and AGENT_TOOL_CALL_LIMIT overrides every other limit for a
# session. PreCompact returns the same handoff context with or without a team
# tag.

set -euo pipefail

# The folder containing this test and its shared helpers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the hook under test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# A temporary folder for hook state and captured output.
TEST_ROOT=$(mktemp -d)

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

# The hook whose checkpoint behaviour is under test.
HOOK="$REPO_DIR/src/hooks/shared/tool-call-checkpoint.sh"
# The session ID for the current scenario, set by start_session.
SESSION=""
# The counter file the hook writes for the current session.
STATE_FILE=""
# The tool-call limit passed to the hook; an empty value leaves it unset.
LIMIT_OVERRIDE=""
# The agent name passed to the hook; an empty value leaves it unset.
AGENT_NAME=""
# The agent tag passed to the hook; __UNSET__ removes it.
AGENT_TAG=""
# The flag marking a planning workflow for the hook.
PLANNING_WORKFLOW=""
# The flag marking an insights review workflow for the hook.
INSIGHTS_REVIEW_WORKFLOW=""
# Enables the hook's structural trace for a scenario.
TRACE_ENABLED=""

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
#     hook counts events; pass an empty string for an empty tag, or __UNSET__
#     to remove the variable.
start_session() {
	# The scenario name used to distinguish its session state.
	local name="$1"
	# The call limit supplied for this scenario.
	local limit_override="$2"
	# The agent name supplied for this scenario, when present.
	local agent_name="${3:-}"
	# The agent tag for this scenario; the default reviewer tag makes the hook count events.
	local agent_tag="${4-Agents-reviewer}"

	SESSION="checkpoint-test-$name-$$"
	STATE_FILE="$TEST_ROOT/agent-tool-call-checkpoints/claude-$SESSION"
	LIMIT_OVERRIDE="$limit_override"
	AGENT_NAME="$agent_name"
	AGENT_TAG="$agent_tag"
	PLANNING_WORKFLOW=""
	INSIGHTS_REVIEW_WORKFLOW=""
	TRACE_ENABLED=""
}

# Runs one Claude hook event with the observed live payload shape.
#
# @param  {string}  event_name
#     Event to send to the hook.
# @param  {string}  tool_name
#     Name included in a PreToolUse payload.
# @param  {number}  batch_count
#     Number of tool calls included in a PostToolBatch payload.
# @param  {string}  output_file
#     File that receives the hook's standard output.
run_hook_event() {
	# Hook event sent in the payload.
	local event_name="$1"
	# The tool name sent in the hook payload.
	local tool_name="$2"
	# Number of tools in the batch payload.
	local batch_count="$3"
	# The file receiving this hook run's standard output.
	local output_file="$4"

	jq -n --arg session "$SESSION" --arg tool "$tool_name" --arg event "$event_name" --argjson batch_count "$batch_count" \
		'if $event == "PostToolBatch" then {hook_event_name: $event, session_id: $session, tool_calls: [range(0; $batch_count) | {tool_name: $tool}]} else {hook_event_name: $event, session_id: $session, tool_name: $tool, tool_input: {}} end' \
		| run_scenario_hook claude "$output_file"
}

# Runs a Codex hook event with the observed payload shape.
#
# @param  {string}  event_name
#     Event to send to the hook.
# @param  {string}  output_file
#     File that receives the hook's standard output.
run_codex_event() {
	# Event sent in the Codex payload.
	local event_name="$1"
	# File receiving the hook output.
	local output_file="$2"

	jq -n --arg session "$SESSION" --arg event "$event_name" \
		'if $event == "PreToolUse" then {hook_event_name: $event, session_id: $session, tool_name: "Bash", tool_input: {}} else {hook_event_name: $event, session_id: $session} end' \
		| run_scenario_hook codex "$output_file"
}

# Runs the hook on the payload from standard input with the current
# scenario's limit, agent name, tag, workflow flags and trace setting.
#
# @param  {string}  runtime
#     Runtime argument passed to the hook: claude or codex.
# @param  {string}  output_file
#     File that receives the hook's standard output.
run_scenario_hook() {
	# Runtime the hook formats its output for.
	local runtime="$1"
	# File receiving the hook output.
	local output_file="$2"
	# The env command that runs the hook with this scenario's settings, without HCOM_TAG unless set below.
	local -a hook_env=(env -u HCOM_TAG TMPDIR="$TEST_ROOT" AGENT_TOOL_CALL_LIMIT="$LIMIT_OVERRIDE" HCOM_NAME="$AGENT_NAME" HCOM_PLANNING_WORKFLOW="$PLANNING_WORKFLOW" HCOM_INSIGHTS_REVIEW_WORKFLOW="$INSIGHTS_REVIEW_WORKFLOW" AGENT_TOOL_CALL_CHECKPOINT_TRACE="$TRACE_ENABLED")

	if [[ "$AGENT_TAG" != "__UNSET__" ]]; then
		hook_env+=("HCOM_TAG=$AGENT_TAG")
	fi

	"${hook_env[@]}" bash "$HOOK" "$runtime" > "$output_file"
}

# Sends one tool use followed by its completed batch.
#
# @param  {string}  tool_name
#     Tool used in the reply.
# @param  {string}  output_file
#     File that receives the batch hook's standard output.
run_hook() {
	# Tool used in the reply.
	local tool_name="$1"
	# File that receives the batch result.
	local output_file="$2"
	# File that receives the pre-tool result.
	local pretool_output="$TEST_ROOT/pretool.txt"

	run_hook_event "PreToolUse" "$tool_name" 0 "$pretool_output"
	assert_empty "$pretool_output"
	run_hook_event "PostToolBatch" "$tool_name" 1 "$output_file"
}

# Asserts the hook produced no output and left the counter at the expected value.
#
# @param  {string}  tool_name
#     Tool name to send.
# @param  {string}  expected_count
#     Counter value expected afterwards.
assert_silent() {
	# The tool name sent to the hook.
	local tool_name="$1"
	# The counter value expected after the counted event.
	local expected_count="$2"
	# The file checked for unexpected hook output.
	local output_file="$TEST_ROOT/silent.txt"
	# The counter value read from the state file, or "missing" when no file exists.
	local actual_count="missing"

	run_hook "$tool_name" "$output_file"

	assert_empty "$output_file"
	if [[ -f "$STATE_FILE" ]]; then
		read -r actual_count _ < "$STATE_FILE"
	fi
	assert_equals "$actual_count" "$expected_count"
}

# Asserts the hook returned the advisory on this counted Claude event.
#
# @param  {string}  tool_name
#     Tool name to send.
assert_advisory() {
	# The tool name whose event should trigger the advisory.
	local tool_name="$1"
	# The file holding the advisory returned by the hook.
	local output_file="$TEST_ROOT/advisory.json"

	run_hook "$tool_name" "$output_file"

	assert_equals "$(jq -r '.hookSpecificOutput.hookEventName' "$output_file")" "PostToolBatch"
}

# Asserts that a Claude batch reports the current count and limit.
#
# @param  {string}  tool_name
#     Tool name sent in the batch.
# @param  {string}  expected_count
#     Count shown in the note.
# @param  {string}  expected_limit
#     Limit shown in the note.
assert_count_note() {
	# Tool name sent in the batch.
	local tool_name="$1"
	# Count expected in the note.
	local expected_count="$2"
	# Limit expected in the note.
	local expected_limit="$3"
	# File holding the hook output.
	local output_file="$TEST_ROOT/count-note.json"

	run_hook "$tool_name" "$output_file"
	assert_equals "$(jq -r '.hookSpecificOutput.hookEventName' "$output_file")" "PostToolBatch"
	assert_equals "$(jq -r '.hookSpecificOutput.additionalContext' "$output_file")" "Tool rounds so far: $expected_count of $expected_limit."
}

# Sends counted events and checks each count note before the limit.
#
# @param  {string}  limit
#     Limit whose final counted event is left for the caller to send.
fill_to_limit() {
	# The event limit; the loop stops one event short so the caller reaches it.
	local limit="$1"
	# The counter value expected after each silent event.
	local count
	# The count already saved when the loop starts.
	local current_count

	read -r current_count _ < "$STATE_FILE"

	for count in $(seq "$(( current_count + 1 ))" "$(( limit - 1 ))"); do
		if (( count % 5 == 0 )); then
			assert_count_note "Write" "$count" "$limit"
		else
			assert_silent "Write" "$count"
		fi
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

start_session "agent-retrospective" "2" "maki" "Agents-reviewer"
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

# Clearing a Codex session discards a pending note along with its count.
start_session "codex-clear" "1"
run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
jq -n --arg session "$SESSION" '{hook_event_name: "SessionStart", source: "clear", session_id: $session}' \
	| run_scenario_hook codex "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
# The Codex counter for the current scenario's session.
codex_state_file="$TEST_ROOT/agent-tool-call-checkpoints/codex-$SESSION"
assert_equals "$(cat "$codex_state_file")" "0 1"
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"

# Default limit: replies with reads and edits count, the 20th batch fires, then the counter freezes.
start_session "default" ""
assert_silent "Read" "1"
assert_equals "$(cut -d ' ' -f 2 "$STATE_FILE")" "20"
assert_silent "mcp__codebase-memory-mcp__search_graph" "2"
assert_silent "Edit" "3"
assert_silent "Bash" "4"
fill_to_limit 20
assert_advisory "Write"
jq -r '.hookSpecificOutput.additionalContext' "$TEST_ROOT/advisory.json" > "$TEST_ROOT/advisory-context.txt"
assert_contains "$TEST_ROOT/advisory-context.txt" 'limit of 20 reached'
assert_not_contains "$TEST_ROOT/advisory-context.txt" 'TOOL_CALL_LIMIT'
# The advisory shows the option in Markdown backticks, so the shell must not run it as a command.
# shellcheck disable=SC2016
assert_contains "$TEST_ROOT/advisory-context.txt" 'After sending either report with `--intent inform`, stop making tool calls and end your turn: inform means the recipient will not reply.'
assert_contains "$TEST_ROOT/advisory-context.txt" 'begin with "State: stopped; decision required."'
assert_not_contains "$TEST_ROOT/advisory-context.txt" 'human decision required'
assert_contains "$TEST_ROOT/advisory-context.txt" 'After a complete report, wait for a new packet. After an incomplete checkpoint, wait for a continuation from the Orchestrator (directly or through your sender) or a decision from the human. Only the human may approve extra scope. The Orchestrator may reset a worker under its role rules; the human may also perform a reset.'
assert_not_contains "$TEST_ROOT/advisory-context.txt" 'Resets remain the human'
assert_not_contains "$TEST_ROOT/advisory-context.txt" 'Outside HCOM'
assert_silent "Write" "20"
assert_silent "Read" "20"

# Claude stays silent at four and six rounds, reports five, and sends only the
# limit note when a five-round boundary is also the limit.
start_session "claude-count" "10"
for count in 1 2 3 4; do
	assert_silent "Read" "$count"
done
assert_count_note "Read" "5" "10"
assert_silent "Read" "6"
fill_to_limit 10
assert_advisory "Read"
assert_equals "$(jq -r '.hookSpecificOutput.additionalContext | startswith("Tool rounds so far:")' "$TEST_ROOT/advisory.json")" "false"

# Two parallel tool uses leave the count unchanged until their one batch completes.
start_session "parallel" "2"
TRACE_ENABLED="1"
run_hook_event "PreToolUse" "Read" 0 "$TEST_ROOT/parallel-pretool.json"
assert_empty "$TEST_ROOT/parallel-pretool.json"
run_hook_event "PreToolUse" "Bash" 0 "$TEST_ROOT/parallel-pretool.json"
assert_empty "$TEST_ROOT/parallel-pretool.json"
if [[ -f "$STATE_FILE" ]]; then
	printf 'PreToolUse counted before PostToolBatch\n' >&2
	exit 1
fi
run_hook_event "PostToolBatch" "" 2 "$TEST_ROOT/parallel-batch.json"
assert_empty "$TEST_ROOT/parallel-batch.json"
assert_equals "$(cat "$STATE_FILE")" "1 2"
assert_equals "$(jq -r '.[0].eventName' -s "$STATE_FILE.trace.jsonl")" "PostToolBatch"
assert_equals "$(jq -r '.[0].toolCallCount' -s "$STATE_FILE.trace.jsonl")" "2"
assert_advisory "Write"
assert_equals "$(cat "$STATE_FILE")" "2 2"

# Codex counts model requests, then delivers its pending limit note once on a tool call.
start_session "codex" "2"
# The Codex counter lives beside the Claude counter for this scenario.
codex_state_file="$TEST_ROOT/agent-tool-call-checkpoints/codex-$SESSION"
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
if [[ -f "$codex_state_file" ]]; then
	printf 'Codex PreToolUse counted before PreModelRequest\n' >&2
	exit 1
fi
# The count the Codex counter should show after each model request.
for count in 1 2; do
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_equals "$(cut -d ' ' -f 1 "$codex_state_file")" "$count"
	assert_empty "$TEST_ROOT/codex.json"
done
assert_equals "$(cat "$codex_state_file")" "2 2"
run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
assert_equals "$(cat "$codex_state_file")" "2 2"
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_equals "$(jq -r '.hookSpecificOutput.hookEventName' "$TEST_ROOT/codex.json")" "PreToolUse"
jq -r '.hookSpecificOutput.additionalContext' "$TEST_ROOT/codex.json" > "$TEST_ROOT/codex-context.txt"
assert_contains "$TEST_ROOT/codex-context.txt" 'limit of 2 reached'
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
assert_equals "$(cat "$codex_state_file")" "2 2"

# Codex saves the five-round note, shows the count at delivery, and replaces
# an undelivered count note when it reaches the limit.
start_session "codex-count" "10"
codex_state_file="$TEST_ROOT/agent-tool-call-checkpoints/codex-$SESSION"
for count in 1 2 3 4; do
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
	assert_equals "$(cat "$codex_state_file")" "$count 10"
done
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
assert_equals "$(cat "$codex_state_file.pending-note")" "count"
run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_equals "$(jq -r '.hookSpecificOutput.additionalContext' "$TEST_ROOT/codex.json")" "Tool rounds so far: 6 of 10."
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"
for count in 7 8 9 10; do
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
done
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
jq -r '.hookSpecificOutput.additionalContext' "$TEST_ROOT/codex.json" > "$TEST_ROOT/codex-count-limit.txt"
assert_contains "$TEST_ROOT/codex-count-limit.txt" 'limit of 10 reached'
assert_not_contains "$TEST_ROOT/codex-count-limit.txt" 'Tool rounds so far:'
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_empty "$TEST_ROOT/codex.json"

# A count note saved at five rounds and still unsent at ten shows ten.
start_session "codex-replace-count" "15"
for count in $(seq 1 10); do
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
done
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
assert_equals "$(jq -r '.hookSpecificOutput.additionalContext' "$TEST_ROOT/codex.json")" "Tool rounds so far: 10 of 15."

# The limit note replaces a count note that has not reached Codex yet.
start_session "codex-replace-with-limit" "10"
for count in $(seq 1 10); do
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
done
run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
jq -r '.hookSpecificOutput.additionalContext' "$TEST_ROOT/codex.json" > "$TEST_ROOT/codex-replaced-limit.txt"
assert_contains "$TEST_ROOT/codex-replaced-limit.txt" 'limit of 10 reached'
assert_not_contains "$TEST_ROOT/codex-replaced-limit.txt" 'Tool rounds so far:'

# Planning and insights review workflows skip Codex counting and note delivery;
# a limit note saved outside the workflow waits until the workflow ends.
# The workflow that runs in this pass of the scenario.
for workflow in planning insights; do
	start_session "codex-$workflow" "1"
	if [[ "$workflow" == "planning" ]]; then
		PLANNING_WORKFLOW="1"
	else
		INSIGHTS_REVIEW_WORKFLOW="1"
	fi
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
	run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
	codex_state_file="$TEST_ROOT/agent-tool-call-checkpoints/codex-$SESSION"
	if [[ -f "$codex_state_file" ]]; then
		printf 'Skipped Codex workflow wrote a counter\n' >&2
		exit 1
	fi
	PLANNING_WORKFLOW=""
	INSIGHTS_REVIEW_WORKFLOW=""
	run_codex_event "PreModelRequest" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
	assert_equals "$(cat "$codex_state_file")" "1 1"
	if [[ "$workflow" == "planning" ]]; then
		PLANNING_WORKFLOW="1"
	else
		INSIGHTS_REVIEW_WORKFLOW="1"
	fi
	run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
	assert_empty "$TEST_ROOT/codex.json"
	PLANNING_WORKFLOW=""
	INSIGHTS_REVIEW_WORKFLOW=""
	run_codex_event "PreToolUse" "$TEST_ROOT/codex.json"
	assert_equals "$(jq -r '.hookSpecificOutput.hookEventName' "$TEST_ROOT/codex.json")" "PreToolUse"
done

# Clearing a session resets the count to 0, keeps the limit in the counter file,
# and lets the checkpoint fire again. This returns to the default scenario,
# whose counter stopped at its limit above.
start_session "default" ""
jq -n --arg session "$SESSION" '{hook_event_name: "SessionStart", source: "clear", session_id: $session}' \
	| env -u HCOM_TAG TMPDIR="$TEST_ROOT" AGENT_TOOL_CALL_LIMIT="$LIMIT_OVERRIDE" HCOM_NAME="$AGENT_NAME" HCOM_TAG="Agents-reviewer" \
		bash "$HOOK" claude > "$TEST_ROOT/clear.txt"
assert_empty "$TEST_ROOT/clear.txt"
assert_equals "$(cat "$STATE_FILE")" "0 20"
assert_silent "Read" "1"
fill_to_limit 20
assert_advisory "Write"

# Overridden limit: the advisory moves to the configured counted event.
start_session "override" "5"
assert_silent "Read" "1"
assert_equals "$(cut -d ' ' -f 2 "$STATE_FILE")" "5"
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
assert_equals "$(cut -d ' ' -f 2 "$STATE_FILE")" "40"
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
