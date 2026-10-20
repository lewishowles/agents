#!/usr/bin/env bash

set -euo pipefail

# The folder containing this test and its shared helpers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the hook under test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# A temporary folder for each test's project and database.
TEST_ROOT=$(mktemp -d)

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

run_tool_failure_hook() {
	# The project folder used as the hook's working directory.
	local project_dir="$1"
	# The database that receives the logged tool failure.
	local database_path="$2"
	# The tool failure payload sent to the hook.
	local payload="$3"

	(
		cd "$project_dir"
		FRICTION_DATABASE="$database_path" bash "$REPO_DIR/dist/claude/hooks/tool-failure-log.sh" <<< "$payload"
	)
}

test_tool_failures_are_logged() {
	# The project folder whose path should appear in the logged entry.
	local project_dir="$TEST_ROOT/tool-failure-project"
	# The database used to inspect the logged entry.
	local database_path="$TEST_ROOT/tool-failure.db"
	# The file holding the entries returned by the friction command.
	local entries_file="$TEST_ROOT/tool-failure-entries.json"
	# A failed Bash call for the hook to record.
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
	# The project folder for the malformed-input and missing-command cases.
	local project_dir="$TEST_ROOT/tool-failure-non-blocking-project"
	# The isolated database for the non-blocking cases.
	local database_path="$TEST_ROOT/tool-failure-non-blocking.db"
	# A failed Read call used when the friction command is unavailable.
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
