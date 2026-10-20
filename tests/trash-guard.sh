#!/usr/bin/env bash
# Checks that the trash wrapper refuses dangerous paths and passes every other
# call through. A fake trash command stands in for /usr/bin/trash, so no file
# is ever moved.

set -euo pipefail

# The folder that holds this test.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository that holds the wrapper.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# Temporary files, folders and the fake trash command.
TEST_ROOT=$(mktemp -d)
# The wrapper being tested.
WRAPPER="$REPO_DIR/src/bin/trash"
# The wrapper's output from the latest run.
STDOUT_FILE="$TEST_ROOT/stdout.txt"
# The wrapper's error output from the latest run.
STDERR_FILE="$TEST_ROOT/stderr.txt"
# The arguments the fake received, one per line; absent when it did not run.
ARGUMENTS_FILE="$TEST_ROOT/arguments.txt"
# The wrapper's exit status from the latest run.
TEST_STATUS=0

# shellcheck source=tests/lib/test-helpers.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

# The fake records every argument without moving any file.
cat > "$TEST_ROOT/fake-trash" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TRASH_GUARD_ARGUMENTS_FILE"
printf 'fake trash output\n'
printf 'fake trash error\n' >&2
exit "${TRASH_GUARD_FAKE_STATUS:-0}"
FAKE
chmod +x "$TEST_ROOT/fake-trash"

# The fake trash command the wrapper runs in place of the real one.
export TRASH_GUARD_TEST_BIN="$TEST_ROOT/fake-trash"
# The file where the fake trash command records the arguments it was given.
export TRASH_GUARD_ARGUMENTS_FILE="$ARGUMENTS_FILE"

mkdir -p "$TEST_ROOT/folder"
touch "$TEST_ROOT/file"
ln -s "$REPO_DIR" "$TEST_ROOT/repo-link"

# Runs the wrapper from the tests folder, so '..' names the repository root,
# and records its output, errors and exit status.
#
# @param  {string}  ...
#     The arguments to pass to the wrapper.
run_trash() {
	rm -f "$ARGUMENTS_FILE"

	set +e
	(cd "$SCRIPT_DIR" && "$WRAPPER" "$@") > "$STDOUT_FILE" 2> "$STDERR_FILE"
	TEST_STATUS=$?
	set -e
}

# Checks that the argument is refused even beside a safe file, and that the
# fake never runs, so nothing would have moved.
#
# @param  {string}  argument
#     The path the wrapper should refuse.
assert_refused() {
	# The path expected in the error message.
	local argument="$1"

	run_trash "$TEST_ROOT/file" "$argument"

	[[ "$TEST_STATUS" -ne 0 ]] || fail "Expected a refusal for: $argument"
	assert_not_file "$ARGUMENTS_FILE"
	assert_empty "$STDOUT_FILE"
	assert_contains "$STDERR_FILE" 'an empty argument usually means an unset variable'
	assert_contains "$STDERR_FILE" 'Name the file or folder explicitly'

	if [[ -z "$argument" ]]; then
		assert_contains "$STDERR_FILE" "argument ''"
	else
		assert_contains "$STDERR_FILE" "$argument"
	fi
}

assert_refused ''
assert_refused '.'
assert_refused '..'
assert_refused "$REPO_DIR"
assert_refused '../.'
assert_refused "$TEST_ROOT/repo-link"
assert_refused "$SCRIPT_DIR"
assert_refused "$REPO_DIR/.."
assert_refused "$HOME"
assert_refused '/'

# The home folder is refused on its own, from a current folder outside it.
mkdir -p "$TEST_ROOT/home"
rm -f "$ARGUMENTS_FILE"
set +e
(cd "$TEST_ROOT/folder" && HOME="$TEST_ROOT/home" "$WRAPPER" "$TEST_ROOT/home") > "$STDOUT_FILE" 2> "$STDERR_FILE"
TEST_STATUS=$?
set -e
[[ "$TEST_STATUS" -ne 0 ]] || fail 'Expected a refusal outside HOME'
assert_not_file "$ARGUMENTS_FILE"
assert_empty "$STDOUT_FILE"
assert_contains "$STDERR_FILE" 'Name the file or folder explicitly'

# A script that leaves a variable unset passes trash an empty argument.
rm -f "$ARGUMENTS_FILE"
set +e
(cd "$SCRIPT_DIR" && bash -c 'unset missing_path; "$1" "$missing_path" "$2"' _ "$WRAPPER" "$TEST_ROOT/file") > "$STDOUT_FILE" 2> "$STDERR_FILE"
TEST_STATUS=$?
set -e
[[ "$TEST_STATUS" -ne 0 ]] || fail 'Expected a refusal for an unset variable'
assert_not_file "$ARGUMENTS_FILE"
assert_contains "$STDERR_FILE" "argument ''"

# Options and ordinary paths reach the real trash command unchanged.
run_trash -h --help -v --verbose -s -stopOnError -- "$TEST_ROOT/file" "$TEST_ROOT/folder"
assert_equals "$TEST_STATUS" '0'
assert_contains "$STDOUT_FILE" 'fake trash output'
assert_contains "$STDERR_FILE" 'fake trash error'
assert_equals "$(cat "$ARGUMENTS_FILE")" "$(printf '%s\n' -h --help -v --verbose -s -stopOnError -- "$TEST_ROOT/file" "$TEST_ROOT/folder")"

# A relative '-' reaches trash even when OLDPWD names the repository root.
rm -f "$ARGUMENTS_FILE"
set +e
(cd "$SCRIPT_DIR" && OLDPWD="$REPO_DIR" "$WRAPPER" -) > "$STDOUT_FILE" 2> "$STDERR_FILE"
TEST_STATUS=$?
set -e
assert_equals "$TEST_STATUS" '0'
assert_equals "$(cat "$ARGUMENTS_FILE")" '-'

# A folder of the same name on CDPATH does not hide a protected path in the
# current folder: 'up' links to a folder above the current one.
mkdir -p "$TEST_ROOT/cdpath/up"
ln -s "$TEST_ROOT" "$TEST_ROOT/folder/up"
rm -f "$ARGUMENTS_FILE"
set +e
(cd "$TEST_ROOT/folder" && CDPATH="$TEST_ROOT/cdpath" "$WRAPPER" up) > "$STDOUT_FILE" 2> "$STDERR_FILE"
TEST_STATUS=$?
set -e
[[ "$TEST_STATUS" -ne 0 ]] || fail 'Expected a refusal for a protected path shadowed on CDPATH'
assert_not_file "$ARGUMENTS_FILE"
assert_contains "$STDERR_FILE" 'Name the file or folder explicitly'

# CDPATH does not make a safe local folder look like a protected one.
mkdir -p "$TEST_ROOT/folder/safe"
ln -s "$TEST_ROOT" "$TEST_ROOT/cdpath/safe"
rm -f "$ARGUMENTS_FILE"
set +e
(cd "$TEST_ROOT/folder" && CDPATH="$TEST_ROOT/cdpath" "$WRAPPER" safe) > "$STDOUT_FILE" 2> "$STDERR_FILE"
TEST_STATUS=$?
set -e
assert_equals "$TEST_STATUS" '0'
assert_equals "$(cat "$ARGUMENTS_FILE")" 'safe'

# A deleted current folder stops before the real trash command runs.
mkdir "$TEST_ROOT/deleted"
rm -f "$ARGUMENTS_FILE"
set +e
(cd "$TEST_ROOT/deleted" && rmdir "$TEST_ROOT/deleted" && "$WRAPPER" "$TEST_ROOT/file") > "$STDOUT_FILE" 2> "$STDERR_FILE"
TEST_STATUS=$?
set -e
[[ "$TEST_STATUS" -ne 0 ]] || fail 'Expected a refusal from a deleted current folder'
assert_not_file "$ARGUMENTS_FILE"
assert_empty "$STDOUT_FILE"
assert_contains "$STDERR_FILE" 'trash: the current folder no longer exists; nothing was moved.'

# The real trash command's exit status passes through.
export TRASH_GUARD_FAKE_STATUS=37
run_trash "$TEST_ROOT/file"
assert_equals "$TEST_STATUS" '37'
assert_contains "$STDOUT_FILE" 'fake trash output'
assert_contains "$STDERR_FILE" 'fake trash error'

printf '✓ Trash guard tests passed\n'
