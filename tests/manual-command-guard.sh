#!/usr/bin/env bash
# Covers the hook that blocks browser runners and manual-only agent-run commands.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)  # Directory holding this test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)  # Repository root, used to find the hook.
TEST_ROOT=$(mktemp -d)  # Throwaway directory used as the session working directory.
STUB_BIN="$TEST_ROOT/bin"  # Holds the fake agent-run placed first on PATH.
AGENT_RUN_CALLS="$TEST_ROOT/agent-run-calls.txt"  # Each call to the fake agent-run, so tests can prove it was skipped.
ORIGINAL_PATH="$PATH"  # PATH before the fake agent-run is added, for the agent-run-missing case.

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

mkdir -p "$STUB_BIN"
: > "$AGENT_RUN_CALLS"

cat > "$STUB_BIN/agent-run" <<'EOF'
#!/usr/bin/env bash
# Returns the registry response selected by the test and records each lookup.

set -euo pipefail

printf '%s|agent-run %s\n' "$PWD" "$*" >> "$AGENT_RUN_CALLS"

case "${AGENT_RUN_MODE:-empty}" in
	manual)
		printf '%s\n' '{"ok":true,"data":{"commands":[{"name":"test","working_directory":".","capability":"none","manual":true,"timeout_seconds":30,"argv":["npm","test"]}]}}'
		;;
	non_manual)
		printf '%s\n' '{"ok":true,"data":{"commands":[{"name":"test","working_directory":".","capability":"none","manual":false,"timeout_seconds":30,"argv":["npm","test"]}]}}'
		;;
	failing)
		printf '%s\n' '{"ok":false,"error":{"code":"environment","message":"registry unavailable"}}'
		;;
	malformed)
		printf '%s\n' 'not json'
		;;
	*)
		printf '%s\n' '{"ok":true,"data":{"commands":[]}}'
		;;
esac
EOF
chmod +x "$STUB_BIN/agent-run"

TEST_STATUS=0  # Exit status of the last hook run.

# Runs the manual-command guard with one Bash tool payload.
#
# @param  {string}  command
#     Shell command presented to the hook.
# @param  {string}  output_file
#     File that receives the hook's standard error.
# @param  {string}  path_value
#     PATH used while the hook checks for agent-run.
run_guard() {
	local command="$1"  # Shell command presented to the hook.
	local output_file="$2"  # File that receives the hook's standard error.
	local path_value="${3:-$STUB_BIN:$ORIGINAL_PATH}"  # PATH used by the hook.

	set +e
	jq -n --arg command "$command" --arg cwd "$TEST_ROOT" \
			'{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}' \
		| PATH="$path_value" AGENT_RUN_CALLS="$AGENT_RUN_CALLS" AGENT_RUN_MODE="${AGENT_RUN_MODE:-empty}" \
			bash "$REPO_DIR/src/hooks/claude/guard-manual-commands/guard-manual-commands.sh" 2> "$output_file"
	TEST_STATUS=$?
	set -e
}

# Asserts that a command is blocked.
#
# @param  {string}  command
#     Shell command expected to be denied.
assert_blocked() {
	local command="$1"  # Shell command expected to be denied.
	local output_file="$TEST_ROOT/blocked.txt"  # Captured hook error output.

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "2"
}

# Asserts that a command passes without hook output.
#
# @param  {string}  command
#     Shell command expected to be allowed.
assert_allowed() {
	local command="$1"  # Shell command expected to be allowed.
	local output_file="$TEST_ROOT/allowed.txt"  # Captured hook error output.

	run_guard "$command" "$output_file"

	assert_equals "$TEST_STATUS" "0"
	assert_empty "$output_file"
}

AGENT_RUN_MODE=manual assert_blocked "npm test"
assert_contains "$TEST_ROOT/blocked.txt" "cd $TEST_ROOT && npm test"

AGENT_RUN_MODE=manual assert_blocked "FEATURE=1 npm test -- --run"
AGENT_RUN_MODE=manual assert_blocked "cd $TEST_ROOT && npm test"
AGENT_RUN_MODE=manual assert_blocked "git status --short && npm test"
: > "$AGENT_RUN_CALLS"
AGENT_RUN_MODE=manual assert_blocked "npm test && npm other"
CALL_COUNT="$(wc -l < "$AGENT_RUN_CALLS" | tr -d '[:space:]')"  # Number of registry lookups for one chained command.
assert_equals "$CALL_COUNT" "1"
assert_contains "$AGENT_RUN_CALLS" "$TEST_ROOT|agent-run list --json"
AGENT_RUN_MODE=manual assert_allowed "npm other"

AGENT_RUN_MODE=non_manual assert_allowed "npm test"

: > "$AGENT_RUN_CALLS"
for command in "git status --short" "rg -n pattern src" "ls -la"; do
	AGENT_RUN_MODE=manual assert_allowed "$command"
done
assert_empty "$AGENT_RUN_CALLS"

AGENT_RUN_MODE=empty assert_allowed "echo ready 2>&1"
assert_empty "$AGENT_RUN_CALLS"

: > "$AGENT_RUN_CALLS"
for command in \
	"playwright test" \
	"cypress run" \
	"npx playwright test" \
	"npx cypress run" \
	"pnpm exec playwright test" \
	"pnpm exec cypress run" \
	"pnpm dlx playwright test" \
	"pnpm dlx cypress run" \
	"yarn playwright test" \
	"yarn cypress run" \
	"bunx playwright test" \
	"bunx cypress run" \
	"uv run playwright test" \
	"uv run cypress run" \
	"npm exec playwright test" \
	"npm exec cypress run"; do
	AGENT_RUN_MODE=empty assert_blocked "$command"
done
AGENT_RUN_MODE=empty assert_blocked "git status --short && npx playwright test"
AGENT_RUN_MODE=empty assert_blocked $'git status --short\nnpx playwright test'
AGENT_RUN_MODE=empty assert_blocked "echo ready;cypress run"
AGENT_RUN_MODE=empty assert_blocked "./node_modules/.bin/playwright test"
AGENT_RUN_MODE=empty assert_blocked "(npx cypress run)"
AGENT_RUN_MODE=empty assert_blocked "pnpm playwright test"
AGENT_RUN_MODE=empty assert_blocked "pnpm cypress run"
AGENT_RUN_MODE=empty assert_blocked "yarn exec playwright test"
AGENT_RUN_MODE=empty assert_blocked "npx -p @playwright/test playwright test"
AGENT_RUN_MODE=empty assert_blocked "npx --package @cypress/cypress cypress run"
AGENT_RUN_MODE=empty assert_blocked "bunx --bun playwright test"
assert_empty "$AGENT_RUN_CALLS"

AGENT_RUN_MODE=empty assert_blocked "playwright test"
assert_empty "$AGENT_RUN_CALLS"

NO_AGENT_RUN_PATH="$(dirname "$(command -v jq)"):/usr/bin:/bin"  # Only jq and system tools, so no agent-run is found.
AGENT_RUN_MODE=empty run_guard "cypress run" "$TEST_ROOT/absent.txt" "$NO_AGENT_RUN_PATH"
assert_equals "$TEST_STATUS" "2"
assert_contains "$TEST_ROOT/absent.txt" "cd $TEST_ROOT && cypress run"

: > "$AGENT_RUN_CALLS"
AGENT_RUN_MODE=failing assert_allowed "npm test"
assert_contains "$AGENT_RUN_CALLS" "agent-run list --json"
: > "$AGENT_RUN_CALLS"
AGENT_RUN_MODE=malformed assert_allowed "npm test"
assert_contains "$AGENT_RUN_CALLS" "agent-run list --json"
: > "$AGENT_RUN_CALLS"
AGENT_RUN_MODE=failing assert_blocked "cypress run"
assert_empty "$AGENT_RUN_CALLS"

printf '✓ manual-command guard tests passed\n'
