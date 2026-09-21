#!/usr/bin/env bash
# Wrapper for serena-hooks remind — nudges the agent to prefer Serena's
# symbolic tools over consecutive grep/read_file calls.
set -euo pipefail

# This repo is mostly Markdown skills and small hook folders (hook.json plus a
# shell script), so Serena's symbolic tools add nothing and the reminder is
# skipped.
if [[ "$PWD" == "$HOME/Dev/Configuration/Agents"* ]]; then
	exit 0
fi

set +e
output="$(serena-hooks remind --client=claude-code)"
status="$?"
set -e

if [[ "$output" == *"Too many consecutive"* ]]; then
	printf 'Serena reminder: too many consecutive source-inspection calls without symbolic tools. Next action should be a Serena symbolic lookup, diagnostics, or a single targeted read with a stated reason.\n' >&2
	exit 0
fi

if [[ -n "$output" ]]; then
	printf '%s\n' "$output"
fi

exit "$status"
