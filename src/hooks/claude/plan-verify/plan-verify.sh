#!/usr/bin/env bash
#
# plan-verify — PostToolUse:ExitPlanMode hook
#
# Warns if the most recently modified plan file lacks a ## Validation section.
# Silent on pass, silent if no plan files exist.

# The folder where Claude stores plan files.
plans_dir="$HOME/.claude/plans"
[ -d "$plans_dir" ] || exit 0

# The most recently changed plan, which is the one being exited.
plan_file=""
# Each plan file in turn; the glob stays unexpanded when there are none.
for candidate in "$plans_dir"/*.md; do
	[ -f "$candidate" ] || continue
	if [ -z "$plan_file" ] || [ "$candidate" -nt "$plan_file" ]; then
		plan_file="$candidate"
	fi
done
[ -z "$plan_file" ] && exit 0

if ! grep -qi "^## Validation" "$plan_file"; then
	jq -n '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: "⚠️  Plan is missing a ## Validation section. Add one before exiting plan mode."}}'
fi
