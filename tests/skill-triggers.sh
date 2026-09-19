#!/usr/bin/env bash
# Tests hook fixtures for required and forbidden skill reminders.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
FIXTURE_DIR="$SCRIPT_DIR/fixtures"
TEST_ROOT=$(mktemp -d) # Temporary root for generated fixture skill folders.
FIXTURE_SKILLS_DIR="$TEST_ROOT/skills" # Temporary installed-skill fixture directory.

trap 'rm -rf "$TEST_ROOT"' EXIT

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

# Creates the installed skill folders used by every standard fixture.
#
# @param  {string}  list_file
#     Newline-delimited skill names to install in the temporary fixture.
prepare_fixture_skills() {
	local list_file="$1" # File containing the fixture skill names.
	local skill # Current skill name from the fixture list.
	local skills=() # Skill names read from the fixture list.

	mkdir -p "$FIXTURE_SKILLS_DIR"
	mapfile -t skills < <(read_skill_list "$list_file")

	for skill in "${skills[@]}"; do
		mkdir -p "$FIXTURE_SKILLS_DIR/$skill"
	done
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

# Runs one hook input fixture and checks required and forbidden skills.
#
# @param  {string}  hook_script
#     Hook script under test.
# @param  {string}  fixture_dir
#     Directory containing the input and expected skill lists.
# @param  {string}  case_name
#     Human-readable fixture name.
# @param  {string}  skills_dir
#     Installed skill directory for this fixture.
run_fixture() {
	local hook_script="$1"
	local fixture_dir="$2"
	local case_name="$3"
	local skills_dir="${4-$FIXTURE_SKILLS_DIR}" # Installed skill directory for this fixture.

	local input="$fixture_dir/input.json"
	local expected_file="$fixture_dir/expected-skills.txt"
	local forbidden_file="$fixture_dir/forbidden-skills.txt"
	local output

	# The hook reads the pattern list that ships beside it, so tests check the real list.
	output=$(
		SKILL_FILE_TRIGGER_SKILLS_DIR="$skills_dir" \
		bash "$hook_script" < "$input" 2>/dev/null || true
	)

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

# Runs one fixture through a symlink with no pattern file beside that symlink.
#
# @param  {string}  hook_script
#     Real hook script under test.
# @param  {string}  fixture_dir
#     Symlink fixture directory.
run_symlink_fixture() {
	local hook_script="$1"
	local fixture_dir="$2"
	local symlink_path="$TEST_ROOT/skill-file-trigger.sh" # Temporary symlink with no adjacent pattern file.

	ln -s "$hook_script" "$symlink_path"

	run_fixture "$symlink_path" "$fixture_dir" "symlink-pattern-resolution"
}

# Runs the missing-skill case again after installing the matched skill.
#
# @param  {string}  hook_script
#     Hook script under test.
# @param  {string}  fixture_dir
#     Fixture directory for the positive control case.
run_missing_skill_control() {
	local hook_script="$1"
	local fixture_dir="$2"
	local skills_dir="$TEST_ROOT/missing-skill-control" # Temporary skills directory for the positive control.

	mkdir -p "$skills_dir/boilersuit-generator-authoring"
	run_fixture "$hook_script" "$fixture_dir" "missing-skill-installed-control" "$skills_dir"
}

# Runs every fixture directory in a named fixture suite.
#
# @param  {string}  suite_name
#     Human-readable suite name.
# @param  {string}  hook_script
#     Hook script under test.
# @param  {string}  fixture_subdir
#     Fixture directory below tests/fixtures.
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

prepare_fixture_skills "$FIXTURE_DIR/skill-file-trigger/installed-skills.txt"

run_suite "skill-file-trigger" \
	"$REPO_DIR/dist/claude/hooks/skill-file-trigger.sh" \
	"skill-file-trigger"

run_symlink_fixture \
	"$REPO_DIR/dist/claude/hooks/skill-file-trigger.sh" \
	"$FIXTURE_DIR/skill-file-trigger-symlink-pattern-resolution"

run_missing_skill_control \
	"$REPO_DIR/dist/claude/hooks/skill-file-trigger.sh" \
	"$FIXTURE_DIR/skill-file-trigger-missing-skill-control"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
