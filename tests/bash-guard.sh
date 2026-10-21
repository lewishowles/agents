#!/usr/bin/env bash
# Checks that old Bash exits safely or restarts under a suitable interpreter.

set -euo pipefail

# The folder containing this test and its shared helpers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the Bash guard.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# A temporary folder for the probe script and captured output.
TEST_ROOT=$(mktemp -d)

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

# The Bash 4 or newer executable used to test a successful restart.
NEW_BASH="/opt/homebrew/bin/bash"
if [ ! -x "$NEW_BASH" ]; then
	NEW_BASH="/usr/local/bin/bash"
fi

if [ ! -x "$NEW_BASH" ]; then
	fail "The Bash guard test needs an installed Bash 4 or newer"
fi

# The installed Bash version expected after a successful restart.
# The candidate expands its own Bash version in this probe.
# shellcheck disable=SC2016
NEW_BASH_MAJOR=$("$NEW_BASH" -c 'printf "%s" "${BASH_VERSINFO[0]}"')
[ "$NEW_BASH_MAJOR" -ge 4 ] || fail "The Bash guard test needs Bash 4 or newer"
# The timeout executable is saved before the test puts the old Bash first on PATH.
TIMEOUT_BIN=$(command -v timeout || true)
[ -n "$TIMEOUT_BIN" ] || fail "The Bash guard test needs timeout; install it with brew install coreutils"

# The probe prints the interpreter version and the versions seen by child scripts.
cat > "$TEST_ROOT/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
source "$GUARD_HELPER"
printf 'parent=%s\n' "${BASH_VERSINFO[0]}"
bash -c 'printf "child=%s\n" "${BASH_VERSINFO[0]}"'
/bin/bash "$GUARD_CHILD"
PROBE

# The probe runs this child under old Bash after its own restart, to check that the guard can restart the child too.
cat > "$TEST_ROOT/guard-child.sh" <<'CHILD'
#!/bin/bash
set -euo pipefail
source "$GUARD_HELPER"
printf 'guarded=%s\n' "${BASH_VERSINFO[0]}"
CHILD

# The fake candidate passes the version probe but restarts under old Bash.
cat > "$TEST_ROOT/fake-bash" <<'FAKE'
#!/bin/sh
printf 'call\n' >> "$REEXEC_CALLS"
if [ "$1" = '-c' ]; then
	exit 0
fi
exec /bin/bash "$@"
FAKE
chmod +x "$TEST_ROOT/fake-bash"

# The exit status of a bounded run of the probe or a real entry script.
TEST_STATUS=0

# Runs a script with a strict timeout so a restart loop cannot hang the suite.
#
# @param  {string}  script
#     The script to start with macOS Bash.
# @param  {string}  candidates
#     The colon-separated candidate list to use.
# @param  {string}  output_file
#     The file that receives both output streams.
run_with_old_bash() {
	# The script that sources the version guard.
	local script="$1"
	# The replacement Bash candidates for this run.
	local candidates="$2"
	# The file used to inspect the outcome.
	local output_file="$3"

	set +e
	"$TIMEOUT_BIN" 8 env -u REQUIRE_BASH_REEXECUTED \
		PATH="/usr/bin:/bin" \
		GUARD_HELPER="$REPO_DIR/scripts/lib/require-bash.sh" \
		GUARD_CHILD="$TEST_ROOT/guard-child.sh" \
		REEXEC_CALLS="$TEST_ROOT/reexec-calls.txt" \
		REQUIRE_BASH_CANDIDATES="$candidates" \
		/bin/bash "$script" > "$output_file" 2>&1
	TEST_STATUS=$?
	set -e

	[ "$TEST_STATUS" -ne 124 ] || fail "The Bash guard timed out: $script"
}

run_with_old_bash "$TEST_ROOT/probe.sh" "$NEW_BASH" "$TEST_ROOT/supported.txt"
assert_equals "$TEST_STATUS" "0"
assert_contains "$TEST_ROOT/supported.txt" "parent=$NEW_BASH_MAJOR"
assert_contains "$TEST_ROOT/supported.txt" "child=$NEW_BASH_MAJOR"
assert_contains "$TEST_ROOT/supported.txt" "guarded=$NEW_BASH_MAJOR"

run_with_old_bash "$TEST_ROOT/probe.sh" "/bin/bash" "$TEST_ROOT/missing.txt"
[ "$TEST_STATUS" -ne 0 ] || fail "Old Bash unexpectedly passed without a candidate"
assert_contains "$TEST_ROOT/missing.txt" "brew install bash"

run_with_old_bash "$REPO_DIR/scripts/sync.sh" "/bin/bash" "$TEST_ROOT/sync-missing.txt"
[ "$TEST_STATUS" -ne 0 ] || fail "sync.sh unexpectedly passed without a candidate"
assert_contains "$TEST_ROOT/sync-missing.txt" "brew install bash"

run_with_old_bash "$REPO_DIR/scripts/validate.sh" "/bin/bash" "$TEST_ROOT/validate-missing.txt"
[ "$TEST_STATUS" -ne 0 ] || fail "validate.sh unexpectedly passed without a candidate"
assert_contains "$TEST_ROOT/validate-missing.txt" "brew install bash"

run_with_old_bash "$TEST_ROOT/probe.sh" "$TEST_ROOT/fake-bash" "$TEST_ROOT/reexec.txt"
[ "$TEST_STATUS" -ne 0 ] || fail "A failed restart unexpectedly passed"
assert_contains "$TEST_ROOT/reexec.txt" "brew install bash"
assert_equals "$(wc -l < "$TEST_ROOT/reexec-calls.txt" | tr -d ' ')" "2"

printf '✓ Bash guard tests passed\n'
