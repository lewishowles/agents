#!/usr/bin/env bash
# Tests hook fixtures for required and forbidden skill reminders.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
FIXTURE_DIR="$SCRIPT_DIR/fixtures"

pass=0
fail=0

command -v jq &>/dev/null || { printf 'skill-triggers tests require jq\n' >&2; exit 1; }

# Reads a newline-delimited skill list, ignoring blank lines.
#
# @param  {string}  file
#     The skill list path.
read_skill_list() {
	local file="$1"
	local skills=()

	[[ -f "$file" ]] || return 0

	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -n "${line// }" ]] && skills+=("$line")
	done < "$file"

	if [[ ${#skills[@]} -gt 0 ]]; then
		printf '%s\n' "${skills[@]}"
	fi
}

# Returns 0 when the skill name appears as a complete skill token in context.
#
# @param  {string}  context
#     Hook context output.
# @param  {string}  skill
#     Skill name to find.
has_skill() {
	local context="$1"
	local skill="$2"

	printf '%s' "$context" | grep -qE "(^|[[:space:]])${skill}([[:space:]]|\.)"
}

run_fixture() {
	local hook_script="$1"
	local fixture_dir="$2"
	local case_name="$3"

	local input="$fixture_dir/input.json"
	local expected_file="$fixture_dir/expected-skills.txt"
	local forbidden_file="$fixture_dir/forbidden-skills.txt"
	local output

	output=$(bash "$hook_script" < "$input" 2>/dev/null || true)

	local expected_skills=()
	mapfile -t expected_skills < <(read_skill_list "$expected_file")

	local forbidden_skills=()
	mapfile -t forbidden_skills < <(read_skill_list "$forbidden_file")

	if [[ ${#expected_skills[@]} -eq 0 ]]; then
		if [[ -z "$output" ]]; then
			printf '  ✓ %s\n' "$case_name"
			pass=$((pass + 1))
		else
			printf '  ✗ %s: expected no output\n' "$case_name" >&2
			fail=$((fail + 1))
		fi
		return
	fi

	if [[ -z "$output" ]]; then
		printf '  ✗ %s: expected skills [%s] but got no output\n' \
			"$case_name" "${expected_skills[*]}" >&2
		fail=$((fail + 1))
		return
	fi

	local context
	context=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

	local case_pass=true

	for skill in "${expected_skills[@]}"; do
		if ! has_skill "$context" "$skill"; then
			printf '  ✗ %s: skill "%s" not found in output\n' "$case_name" "$skill" >&2
			case_pass=false
		fi
	done

	for skill in "${forbidden_skills[@]}"; do
		if has_skill "$context" "$skill"; then
			printf '  ✗ %s: forbidden skill "%s" found in output\n' "$case_name" "$skill" >&2
			case_pass=false
		fi
	done

	if [[ "$case_pass" == true ]]; then
		printf '  ✓ %s\n' "$case_name"
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
	fi
}

run_suite() {
	local suite_name="$1"
	local hook_script="$2"
	local fixture_subdir="$3"

	printf '%s:\n' "$suite_name"

	for fixture_dir in "$FIXTURE_DIR/$fixture_subdir/"/*/; do
		[[ -d "$fixture_dir" ]] || continue
		run_fixture "$hook_script" "$fixture_dir" "$(basename "$fixture_dir")"
	done
}

run_suite "skill-file-trigger" \
	"$REPO_DIR/dist/claude/hooks/skill-file-trigger.sh" \
	"skill-file-trigger"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
