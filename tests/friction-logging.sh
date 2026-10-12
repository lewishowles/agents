#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

run_tool_failure_hook() {
	local project_dir="$1"
	local database_path="$2"
	local payload="$3"

	(
		cd "$project_dir"
		FRICTION_DATABASE="$database_path" bash "$REPO_DIR/dist/claude/hooks/tool-failure-log.sh" <<< "$payload"
	)
}

test_tool_failures_are_logged() {
	local project_dir="$TEST_ROOT/tool-failure-project"
	local database_path="$TEST_ROOT/tool-failure.db"
	local entries_file="$TEST_ROOT/tool-failure-entries.json"
	local payload='{"tool_name":"Bash","tool_input":{"command":"cat missing.txt"},"error":"cat: missing.txt: No such file or directory","is_interrupt":false,"duration_ms":12,"session_id":"test-session","cwd":"/ignored/by/log/schema"}'

	mkdir -p "$project_dir"
	run_tool_failure_hook "$project_dir" "$database_path" "$payload"
	FRICTION_DATABASE="$database_path" friction list --include-tool-errors --json > "$entries_file"

	assert_equals "$(jq '.data | length' "$entries_file")" "1"
	assert_contains "$entries_file" '"category": "tool-error"'
	assert_contains "$entries_file" "$project_dir"
	assert_contains "$entries_file" "Bash: cat missing.txt"
	assert_contains "$entries_file" "cat: missing.txt: No such file or directory"
}

test_tool_failure_hook_is_non_blocking() {
	local project_dir="$TEST_ROOT/tool-failure-non-blocking-project"
	local database_path="$TEST_ROOT/tool-failure-non-blocking.db"
	local payload='{"tool_name":"Read","tool_input":{"file_path":"missing.md"},"error":"File does not exist","is_interrupt":false,"duration_ms":8,"session_id":"test-session","cwd":"/ignored/by/log/schema"}'

	mkdir -p "$project_dir"

	(
		cd "$project_dir"
		FRICTION_DATABASE="$database_path" bash "$REPO_DIR/dist/claude/hooks/tool-failure-log.sh" <<< "not JSON"
	) || fail "Tool-failure hook exited non-zero for malformed input"

	(
		cd "$project_dir"
		PATH="/usr/bin:/bin" /bin/bash "$REPO_DIR/dist/claude/hooks/tool-failure-log.sh" <<< "$payload"
	) || fail "Tool-failure hook exited non-zero without friction"
}

test_tool_failures_are_logged
test_tool_failure_hook_is_non_blocking

printf '✓ friction logging tests passed\n'
