#!/usr/bin/env bash
#
# tool-call-checkpoint — advisory work-cycle boundary for Claude and Codex.
#
# Counts Claude PostToolBatch and Codex PreModelRequest events per session in
# temporary storage. Every five rounds the agent gets a note with its count, and
# at the limit it gets the limit note instead. Claude gets each note as soon as
# the reply's tools finish. Codex gets it with its next tool call, because
# Codex can't send the agent text from PreModelRequest. PreCompact
# returns a context checkpoint without changing the counter. A cleared session
# resets its counter without touching project or HCOM state.
#
# Only HCOM team sessions, which have HCOM_TAG set, are counted, and the
# planning and insights review workflows skip the count. The pre-compaction
# checkpoint runs in every session.
#
# A Claude reply counts once when all of its tool calls have finished, however
# many it made in parallel. Read-only tools count the same as any other. Codex
# counts each model request, including retries and a final reply with no tool
# calls. The limit is 20 by default and 40 for HCOM Scouts and Implementers,
# recognised from the role suffix in HCOM_TAG. Setting AGENT_TOOL_CALL_LIMIT
# overrides both for a session.

set -euo pipefail

# Counted events before the advisory for an HCOM team without a
# role-specific limit.
readonly DEFAULT_TOOL_CALL_LIMIT=20
# Counted events before the advisory for HCOM Scouts and Implementers, whose
# startup reads need room before the first review point.
readonly WORKER_TOOL_CALL_LIMIT=40
# Advice shown before compaction, independent of the tool-call counter.
readonly COMPACTION_CONTEXT="CONTEXT CHECKPOINT: This session is about to compact. Before continuing, hand off or record the current scope, changed paths, verification, blockers and next decision. Do not expand scope or reset peers."
# Resolve managed hook symlinks so the companion remains beside the generated script.
# Path of this script or its current symlink target.
script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
	# Directory containing the current symlink, used for relative targets.
	script_directory="$(cd -P "$(dirname "$script_path")" && pwd)"
	script_path="$(readlink "$script_path")"
	if [[ "$script_path" != /* ]]; then
		script_path="$script_directory/$script_path"
	fi
done
# The folder that holds the real script, where its message file lives.
SCRIPT_DIR="$(cd -P "$(dirname "$script_path")" && pwd)"
readonly SCRIPT_DIR
# File containing the advice shown when the limit is reached.
readonly TOOL_CALL_CONTEXT_FILE="$SCRIPT_DIR/tool-call-checkpoint-message.md"
# Saved in place of a Codex count note's text, so the note shows the count when
# the agent receives it rather than when it was saved.
readonly PENDING_COUNT_NOTE="count"
# Number of rounds between count notes.
readonly ROUND_NOTE_INTERVAL=5

# Writes an opt-in, non-sensitive summary of the received hook event.
#
# @param  {string}  trace_file
#     Temporary file that receives one JSON object per traced event.
# @param  {string}  input
#     Hook input whose values must not be recorded.
trace_event_structure() {
	# Temporary trace file for the current session.
	local trace_file="$1"
	# Hook payload from which only structural fields are recorded.
	local input="$2"

	[[ "${AGENT_TOOL_CALL_CHECKPOINT_TRACE:-}" == "1" ]] || return 0

	printf '%s' "$input" | jq -c '
		{
			eventName: .hook_event_name,
			inputKeys: keys,
			toolInputKeys: ((.tool_input // {}) | if type == "object" then keys else [] end),
			toolName: (.tool_name // "unknown"),
			toolCallCount: ((.tool_calls // []) | if type == "array" then length else 0 end)
		}
	' >> "$trace_file" 2>/dev/null || true
}

# Prints the tool-call limit for this session: an explicit override, then a
# Scout or Implementer role from HCOM_TAG, then the default.
resolve_tool_call_limit() {
	if [[ "${AGENT_TOOL_CALL_LIMIT:-}" =~ ^[1-9][0-9]*$ ]]; then
		printf '%s\n' "$AGENT_TOOL_CALL_LIMIT"
		return 0
	fi

	case "${HCOM_TAG:-}" in
	scout|implementer|*-scout|*-implementer) printf '%s\n' "$WORKER_TOOL_CALL_LIMIT" ;;
	*) printf '%s\n' "$DEFAULT_TOOL_CALL_LIMIT" ;;
	esac
}

# Returns success when this event adds one to the session's count: a Claude
# PostToolBatch or a Codex PreModelRequest.
should_count() {
	[[ ( "$runtime" == "claude" && "$event_name" == "PostToolBatch" ) || ( "$runtime" == "codex" && "$event_name" == "PreModelRequest" ) ]]
}

# Returns success when this event can send a Codex agent its saved note:
# a Codex PreToolUse, the first event after the counting one that can reach the
# agent.
delivers_saved_note() {
	[[ "$runtime" == "codex" && "$event_name" == "PreToolUse" ]]
}

# Returns success in the planning and insights review workflows, which finish
# their packet without a mid-review stop, so they neither count nor get a note.
in_uninterrupted_workflow() {
	[[ "${HCOM_PLANNING_WORKFLOW:-}" == "1" || "${HCOM_INSIGHTS_REVIEW_WORKFLOW:-}" == "1" ]]
}

# Adds one to the session's stored count and sets count to the new value.
# Fails without changing the file once the count has reached the limit, so the
# limit note is sent only once.
update_stored_count() {
	# Number of events already counted for this session.
	count=0
	if [[ -f "$state_file" ]]; then
		# The stored limit is ignored because the current limit applies.
		read -r count _ < "$state_file" || true
		[[ "$count" =~ ^[0-9]+$ ]] || count=0
	fi

	(( count < TOOL_CALL_LIMIT )) || return 1
	count=$((count + 1))
	printf '%s %s\n' "$count" "$TOOL_CALL_LIMIT" > "$state_file"
}

# Returns success when this round needs a count or limit note.
should_send_round_note() {
	(( count == TOOL_CALL_LIMIT || count % ROUND_NOTE_INTERVAL == 0 ))
}

# Sets the note that tells the agent its round count and limit.
write_count_note_context() {
	checkpoint_context="Tool rounds so far: $count of $TOOL_CALL_LIMIT."
}

# Writes the context checkpoint in the format expected by the current runtime.
write_precompact_output() {
	if [[ "$runtime" == "claude" ]]; then
		jq -n \
			--arg context "$COMPACTION_CONTEXT" \
			'{hookSpecificOutput: {hookEventName: "PreCompact", additionalContext: $context}}'
	else
		jq -n --arg context "$COMPACTION_CONTEXT" '{systemMessage: $context}'
	fi
}

# Reads the limit note from its message file into checkpoint_context and fills
# in this session's limit. Fails when the message file is missing.
load_checkpoint_context() {
	[[ -f "$TOOL_CALL_CONTEXT_FILE" ]] || return 1
	checkpoint_context="$(<"$TOOL_CALL_CONTEXT_FILE")"
	checkpoint_context="${checkpoint_context//\{\{TOOL_CALL_LIMIT\}\}/$TOOL_CALL_LIMIT}"
}

# Writes the Claude note after the reply's tools have finished.
write_claude_posttoolbatch_output() {
	jq -n \
		--arg context "$checkpoint_context" \
		'{hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $context}}'
}

# Writes the pending Codex note before the next tool call.
write_codex_pretooluse_output() {
	jq -n \
		--arg context "$checkpoint_context" \
		'{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $context}}'
}

# Limit applied to this session's counter.
TOOL_CALL_LIMIT="$(resolve_tool_call_limit)"
readonly TOOL_CALL_LIMIT

# Agent that runs this hook, passed as the first argument by its hook settings.
runtime="${1:-}"
case "$runtime" in
claude|codex) ;;
*) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

# Hook payload for the current event.
input="$(cat)"
# Event type that selects compaction, reset, or counting.
event_name="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)" || exit 0

if [[ "$event_name" == "PreCompact" ]]; then
	write_precompact_output
	exit 0
fi

# The checkpoint advice is written for HCOM team roles, so sessions without a
# team tag skip the count. PreCompact is handled above and still runs.
[[ -n "${HCOM_TAG:-}" ]] || exit 0

# A cleared session resets its counter below. Every other event stops here
# unless it counts or can send a saved Codex note.
if [[ "$event_name" != "SessionStart" ]]; then
	if in_uninterrupted_workflow; then
		exit 0
	fi

	should_count || delivers_saved_note || exit 0
fi

# Session identifier used to keep counters separate.
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)" || exit 0

[[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || exit 0

# Temporary directory containing the session counters.
state_dir="${TMPDIR:-/tmp}/agent-tool-call-checkpoints"
mkdir -p "$state_dir" 2>/dev/null || exit 0

# Holds "<count> <limit>" on one line; the Claude status line reads it to show
# the count, so keep this format in step with statusline.sh.
state_file="$state_dir/$runtime-$session_id"
# Holds a Codex note until the next tool call sends it; empty otherwise.
pending_note_file="$state_file.pending-note"
# Trace of event shapes beside the session counter, written only when tracing is turned on.
trace_file="$state_file.trace.jsonl"
# Directory used as the counter's lock.
lock_dir="$state_file.lock"
# Whether this invocation acquired the counter lock.
locked=false

# Try to take the lock up to 20 times, 50 milliseconds apart.
for _ in {1..20}; do
	if mkdir "$lock_dir" 2>/dev/null; then
		locked=true
		break
	fi
	sleep 0.05
done

"$locked" || exit 0
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

if [[ "$event_name" == "SessionStart" ]]; then
	# How the session started; only /clear resets the counter.
	source="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)" || exit 0
	[[ "$source" == "clear" ]] || exit 0
	printf '0 %s\n' "$TOOL_CALL_LIMIT" > "$state_file"

	# A cleared Codex session also drops a note it has not yet sent.
	if [[ "$runtime" == "codex" ]]; then
		: > "$pending_note_file"
	fi

	exit 0
fi

trace_event_structure "$trace_file" "$input"

# Send a saved Codex note once, then empty the file so it isn't sent again.
if delivers_saved_note; then
	[[ -s "$pending_note_file" ]] || exit 0
	checkpoint_context="$(<"$pending_note_file")"
	if [[ "$checkpoint_context" == "$PENDING_COUNT_NOTE" ]]; then
		read -r count _ < "$state_file" || exit 0
		[[ "$count" =~ ^[0-9]+$ ]] || exit 0
		write_count_note_context
	fi
	write_codex_pretooluse_output
	: > "$pending_note_file"
	exit 0
fi

update_stored_count || exit 0

should_send_round_note || exit 0

if (( count == TOOL_CALL_LIMIT )); then
	load_checkpoint_context || exit 0
elif [[ "$event_name" == "PostToolBatch" ]]; then
	write_count_note_context
else
	checkpoint_context="$PENDING_COUNT_NOTE"
fi

# Claude sends the note now. Codex saves it until its next tool call.
if [[ "$event_name" == "PostToolBatch" ]]; then
	write_claude_posttoolbatch_output
else
	printf '%s\n' "$checkpoint_context" > "$pending_note_file"
fi
