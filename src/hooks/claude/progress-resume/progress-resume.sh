#!/usr/bin/env bash
#
# progress-resume — UserPromptSubmit hook
#
# Detects continue-intent phrases and injects current progress context
# so Claude can resume without the user restating the project state.

if ! command -v jq &>/dev/null; then
	exit 0
fi

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null)

if [[ -z "$prompt" ]]; then
	exit 0
fi

if ! printf '%s' "$prompt" | grep -qiE '\b(continue|carry on|pick up|resume|where were we|next step|where did we|what.s next)\b'; then
	exit 0
fi

ctx=""
if command -v progress &>/dev/null; then
	progress_output=$(progress next --json 2>/dev/null) || progress_output=""
	if [[ -n "$progress_output" ]] && printf '%s' "$progress_output" | jq -e 'type == "object"' >/dev/null 2>&1; then
		ctx="Current project progress from progress next --json:"$'\n\n'"$progress_output"
	fi
fi

if [[ -z "$ctx" ]]; then
	ctx="Project progress is unavailable. Inspect AGENTS.md, package scripts, ordinary docs, and agent-run list --json before continuing."
fi

jq -n --arg ctx "$ctx" \
	'{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
