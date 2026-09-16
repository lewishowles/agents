#!/usr/bin/env bash
#
# tool-call-checkpoint — advisory work-cycle boundary for Claude and Codex.
#
# Counts PreToolUse events per runtime/session in temporary storage. The call
# that reaches the limit returns one advisory checkpoint; a pre-compaction event
# returns a context checkpoint without changing the counter. A clear-session
# start resets the same session's counter without touching project or HCOM state.
#
# Every tool call counts, including reads, because the limit bounds context
# growth. The limit is 20 by default and 40 for HCOM Scouts and Implementers,
# recognised from the agent name hcom exports as HCOM_NAME. Setting
# AGENT_TOOL_CALL_LIMIT overrides both for a session.

set -euo pipefail

readonly DEFAULT_TOOL_CALL_LIMIT=20  # Calls before the advisory for any session without a role-specific limit.
readonly WORKER_TOOL_CALL_LIMIT=40  # Calls before the advisory for HCOM Scouts and Implementers, whose startup reads need room before the first review point.
readonly COMPACTION_CONTEXT="CONTEXT CHECKPOINT: This session is about to compact. Before continuing, hand off or record the current scope, changed paths, verification, blockers and next decision. Do not expand scope or reset peers."
# Resolve managed hook symlinks so the companion remains beside the generated script.
script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
	script_directory="$(cd -P "$(dirname "$script_path")" && pwd)"
	script_path="$(readlink "$script_path")"
	if [[ "$script_path" != /* ]]; then
		script_path="$script_directory/$script_path"
	fi
done
readonly SCRIPT_DIR="$(cd -P "$(dirname "$script_path")" && pwd)"
readonly TOOL_CALL_CONTEXT_FILE="$SCRIPT_DIR/tool-call-checkpoint-message.md"

# Writes an opt-in, non-sensitive summary of the received hook event.
#
# @param  {string}  trace_file
#     Temporary file that receives one JSON object per traced event.
# @param  {string}  input
#     Hook input whose values must not be recorded.
trace_event_structure() {
	local trace_file="$1"
	local input="$2"

	[[ "${AGENT_TOOL_CALL_CHECKPOINT_TRACE:-}" == "1" ]] || return 0

	printf '%s' "$input" | jq -c '
		{
			eventName: .hook_event_name,
			inputKeys: keys,
			toolInputKeys: ((.tool_input // {}) | if type == "object" then keys else [] end),
			toolName: (.tool_name // "unknown")
		}
	' >> "$trace_file" 2>/dev/null || true
}

# Prints the tool-call limit for this session: an explicit override, then the
# HCOM role read from the exported agent name, then the default.
resolve_tool_call_limit() {
	if [[ "${AGENT_TOOL_CALL_LIMIT:-}" =~ ^[1-9][0-9]*$ ]]; then
		printf '%s\n' "$AGENT_TOOL_CALL_LIMIT"
		return 0
	fi

	case "${HCOM_NAME:-}" in
	*-scout-*|*-implementer-*) printf '%s\n' "$WORKER_TOOL_CALL_LIMIT" ;;
	*) printf '%s\n' "$DEFAULT_TOOL_CALL_LIMIT" ;;
	esac
}

readonly TOOL_CALL_LIMIT="$(resolve_tool_call_limit)"  # Limit applied to this session's counter.

runtime="${1:-}"
case "$runtime" in
claude|codex) ;;
*) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
event_name="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)" || exit 0

if [[ "$event_name" == "PreCompact" ]]; then
	if [[ "$runtime" == "claude" ]]; then
		jq -n \
			--arg context "$COMPACTION_CONTEXT" \
			'{hookSpecificOutput: {hookEventName: "PreCompact", additionalContext: $context}}'
	else
		jq -n --arg context "$COMPACTION_CONTEXT" '{systemMessage: $context}'
	fi
	exit 0
fi

# Planning peers finish their review packet without the mid-review call stop.
if [[ "$event_name" == "PreToolUse" && "${HCOM_PLANNING_WORKFLOW:-}" == "1" ]]; then
	exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)" || exit 0

[[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || exit 0

state_dir="${TMPDIR:-/tmp}/agent-tool-call-checkpoints"
mkdir -p "$state_dir" 2>/dev/null || exit 0

state_file="$state_dir/$runtime-$session_id"
trace_file="$state_file.trace.jsonl"
lock_dir="$state_file.lock"
locked=false

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
	source="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)" || exit 0
	[[ "$source" == "clear" ]] || exit 0
	printf '0\n' > "$state_file"
	exit 0
fi

[[ "$event_name" == "PreToolUse" ]] || exit 0

trace_event_structure "$trace_file" "$input"

count=0
if [[ -f "$state_file" ]]; then
	IFS= read -r count < "$state_file" || true
	[[ "$count" =~ ^[0-9]+$ ]] || count=0
fi

(( count < TOOL_CALL_LIMIT )) || exit 0

count=$((count + 1))
printf '%s\n' "$count" > "$state_file"

(( count == TOOL_CALL_LIMIT )) || exit 0

[[ -f "$TOOL_CALL_CONTEXT_FILE" ]] || exit 0

jq -n \
	--rawfile context "$TOOL_CALL_CONTEXT_FILE" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $context}}'
