#!/usr/bin/env bash
# Gives Claude Code's Read tool a halved copy of a Retina image file, so the
# agent spends fewer tokens on it.
#
# Every failure exits silently with no output, so the agent reads the original
# file.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v retina-shrink >/dev/null 2>&1 || exit 0

# The Read tool call that Claude Code sends as JSON.
input="$(cat 2>/dev/null)" || exit 0
# The file the agent asked to read.
source_path="$(printf '%s' "$input" | jq -er '.tool_input.file_path | select(type == "string" and length > 0)' 2>/dev/null)" || exit 0

shopt -s nocasematch
case "$source_path" in
*.png|*.jpg|*.jpeg|*.webp) ;;
*) exit 0 ;;
esac
shopt -u nocasematch

[[ -f "$source_path" ]] || exit 0

# The halved copy, or the original path when halving would not help.
read_path="$(retina-shrink "$source_path" 2>/dev/null)" || exit 0
[[ "$read_path" != "$source_path" ]] || exit 0

printf '%s' "$input" | jq -c --arg path "$read_path" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .file_path = $path)}}' 2>/dev/null || exit 0
