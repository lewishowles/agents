#!/usr/bin/env bash
# Covers the shared guard that stops broad searches entering ignored or generated directories.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

TEST_STATUS=0

# Runs the search guard with one Bash tool payload.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  output_file
#     File that receives the hook's standard error.
run_guard() {
	local command="$1"
	local output_file="$2"

	set +e
	jq -n --arg command "$command" '{tool_name: "Bash", tool_input: {command: $command}}' \
		| bash "$REPO_DIR/src/hooks/shared/guard-search-boundaries.sh" 2> "$output_file"
	TEST_STATUS=$?
	set -e
}

# Asserts that a command is blocked.
#
# @param  {string}  command
#     Shell command expected to be denied.
assert_blocked() {
	local command="$1"
	local output_file="$TEST_ROOT/blocked.txt"

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "2"
}

# Asserts that a command passes without hook output.
#
# @param  {string}  command
#     Shell command expected to be allowed.
assert_allowed() {
	local command="$1"
	local output_file="$TEST_ROOT/allowed.txt"

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$output_file"
}

assert_blocked "rg --files --hidden --no-ignore-vcs"
assert_blocked "rg -uuu 'needle' ."
assert_blocked "rg --no-ignore 'needle' node_modules"
assert_blocked "grep -R 'needle' ."
assert_blocked "find . -type f"
assert_blocked "tree ."
assert_blocked "cd .cache/ms-playwright && rg 'needle'"

assert_allowed "rg -n 'needle' src"
assert_allowed "rg --hidden --no-ignore-vcs -n 'release:' .agent/tasks"
assert_allowed "rg --files --hidden --no-ignore-vcs .agent/tasks"
assert_allowed "find src -maxdepth 2 -type f"
assert_allowed "grep -R 'needle' src"
assert_allowed "tree src"
assert_allowed "rg -n 'node_modules' src"
assert_allowed "rg --hidden --no-ignore-vcs -n 'needle' src/cache"
assert_allowed "rg --hidden --no-ignore-vcs -n 'needle' src/caches"
assert_allowed "rg --hidden --no-ignore-vcs -n 'needle' project-skill-packs/macos/generators/http-cache"

printf '✓ search-boundary tests passed\n'
