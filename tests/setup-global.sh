#!/usr/bin/env bash

set -euo pipefail

# The directory containing this setup test script.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository root used by the setup command and its fixtures.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# The temporary root for isolated setup runs.
TEST_ROOT=$(mktemp -d)
# The real checkout. Skill cases point REPO_DIR at their own copy, which links back here.
SOURCE_REPO_DIR="$REPO_DIR"
# Temporary canonical skill group, set by each case that creates a skill.
ADDED_SKILL_GROUP=""
# Temporary canonical skill name.
ADDED_SKILL_NAME="setup-global-test-skill-$(basename "$TEST_ROOT")"
# Temporary canonical skill directory, set by each case that creates a skill.
ADDED_SKILL_DIR=""

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

# Stops any cases still running, then removes the temporary test folder.
cleanup_setup_global_test() {
	# A case process still running because the suite is exiting early.
	local child_pid

	# Each case runs in its own process group, so stopping the group also
	# stops the setup run it started, which could otherwise recreate files in
	# the test folder after cleanup removes it.
	for child_pid in $(jobs -pr); do
		kill -TERM -- "-$child_pid" 2>/dev/null || true
	done
	wait 2>/dev/null || true
	cleanup
}

trap cleanup_setup_global_test EXIT
# Turns Ctrl-C and termination into a normal exit, so the EXIT trap stops any
# cases still running.
trap 'exit 130' INT
trap 'exit 143' TERM

# Points the current case at its own repository copy, so the skill fixtures it
# creates never appear in the real skills folder. Sets REPO_DIR,
# ADDED_SKILL_GROUP and ADDED_SKILL_DIR for the rest of the case.
#
# @param  {string}  case_name
#     Name used for the case's temporary repository directory.
create_test_repo_copy() {
	# The case name that keeps this copy separate from other cases.
	local case_name="$1"
	# The temporary repository used by this case.
	local copy_dir="$TEST_ROOT/repo-$case_name"
	# A checkout entry or canonical skill collection to link into the copy.
	local entry

	mkdir -p "$copy_dir/skills"
	for entry in "$SOURCE_REPO_DIR"/*; do
		if [ "${entry##*/}" != skills ]; then
			ln -s "$entry" "$copy_dir/${entry##*/}"
		fi
	done
	for entry in "$SOURCE_REPO_DIR"/skills/*; do
		ln -s "$entry" "$copy_dir/skills/${entry##*/}"
	done

	REPO_DIR="$copy_dir"
	ADDED_SKILL_GROUP="$REPO_DIR/skills/setup-global-test-$(basename "$TEST_ROOT")"
	ADDED_SKILL_DIR="$ADDED_SKILL_GROUP/$ADDED_SKILL_NAME"
}

# Creates command stubs so setup-global can run against an isolated home
# without installing dependencies, synchronising output, or changing Git.
#
# @param  {string}  bin_dir
#     Directory that receives the test commands.
create_command_stubs() {
	# The directory that receives the stub commands.
	local bin_dir="$1"

	mkdir -p "$bin_dir"

cat > "$bin_dir/bash" <<'EOF'
#!/bin/sh
case "$1" in
	"$SETUP_GLOBAL_INSTALLER"|"$SETUP_GLOBAL_SYNC"|"$SETUP_GLOBAL_VALIDATE")
		printf '%s\n' "$1" >> "$SETUP_GLOBAL_CALL_LOG"
		exit 0
		;;
esac
exec /bin/bash "$@"
EOF

	cat > "$bin_dir/cli-style" <<'EOF'
#!/bin/sh
if [ "$1" = "adapter-path" ]; then
	printf '%s\n' "$SETUP_GLOBAL_TEST_ADAPTER"
	fi
EOF

	cat > "$bin_dir/cp" <<'EOF'
#!/bin/sh
if [ "$1" = "-R" ]; then
	mkdir -p "$3"
	exit 0
fi
exec /bin/cp "$@"
EOF

	cat > "$bin_dir/mv" <<'EOF'
#!/bin/sh
if [ "${SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE:-0}" = "1" ]; then
	printf 'backup move failed\n' >&2
	exit 1
fi
exec /bin/mv "$@"
EOF

	cat > "$bin_dir/git" <<'EOF'
#!/bin/sh
if [ "$3" = config ] && [ "$4" = --get ]; then
	if [ -f "$HOME/git-hooks-path" ]; then
		cat "$HOME/git-hooks-path"
	fi
	exit 0
fi
if [ "$3" = config ] && [ "$4" = core.hooksPath ]; then
	printf '%s\n' "$5" > "$HOME/git-hooks-path"
fi
exit 0
EOF

	cat > "$bin_dir/friction" <<'EOF'
#!/bin/sh
exit 0
EOF

	cat > "$bin_dir/team-send" <<'EOF'
#!/bin/sh
exit 0
EOF

	cat > "$bin_dir/doc-paths" <<'EOF'
#!/bin/sh
exit 0
EOF

	cat > "$bin_dir/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SETUP_GLOBAL_UV_LOG"
if [ "$1" != "tool" ] || [ "$2" != "install" ] || [ "$3" != "--from" ] || [ "$5" != "doc-paths" ]; then
	exit 1
fi

cat > "$(dirname "$0")/doc-paths" <<'COMMAND'
#!/bin/sh
exit 0
COMMAND
chmod +x "$(dirname "$0")/doc-paths"
EOF

	cat > "$bin_dir/hcom" <<'EOF'
#!/bin/sh
if [ "$1" != "config" ] || [ "$2" != "codex_args" ]; then
	exit 1
fi

if [ "$#" -eq 2 ]; then
	if [ -f "$HOME/hcom-fail-read" ]; then
		exit 1
	fi

	if [ -f "$HOME/hcom-codex-args" ]; then
		cat "$HOME/hcom-codex-args"
	fi
	exit 0
fi

if [ -f "$HOME/hcom-fail-write" ]; then
	exit 1
fi

printf '%s\n' "$3" > "$HOME/hcom-codex-args"
printf 'write\n' >> "$HOME/hcom-writes"
EOF

	cat > "$bin_dir/cli-style-adapter.sh" <<'EOF'
#!/bin/bash
# Stands in for the cli-style renderer and prints its input unchanged, trailing
# newlines included. Setup calls it once per output line, so it uses the read
# builtin rather than starting a cat process each time.
cli_style_render() {
	# The whole input, read up to end of file.
	local text

	# read reports failure when it reaches end of file, which is expected here.
	IFS= read -r -d '' text || :
	printf '%s' "$text"
}
EOF

	chmod +x "$bin_dir/bash" "$bin_dir/cli-style" "$bin_dir/cp" "$bin_dir/mv" "$bin_dir/git" "$bin_dir/friction" "$bin_dir/team-send" "$bin_dir/doc-paths" "$bin_dir/uv" "$bin_dir/hcom" "$bin_dir/cli-style-adapter.sh"
}

# Creates an fzf stand-in that reports SETUP_GLOBAL_FZF_VERSION (default:
# "0.74.5 (Homebrew)") for --version, otherwise records the arguments and skill list it
# receives, then prints a chosen set of skills.
#
# @param  {string}  bin_dir
#     Directory that receives the test-only fzf command.
create_fzf_stub() {
	# Directory that receives the test-only fzf command.
	local bin_dir="$1"

	mkdir -p "$bin_dir"

	cat > "$bin_dir/fzf" <<'EOF'
#!/bin/bash
if [ "${1:-}" = '--version' ]; then
	printf '%s\n' "${SETUP_GLOBAL_FZF_VERSION-0.74.5 (Homebrew)}"
	exit 0
fi
printf '%s\n' "$@" > "$SETUP_GLOBAL_FZF_ARGUMENTS"
cat > "$SETUP_GLOBAL_FZF_INPUT"
# Records what Tab on the first heading does with one, then both, of its skills ticked.
if [ -n "${SETUP_GLOBAL_FZF_ACTIONS:-}" ]; then
	# The Tab command received from setup, before fzf fills in its placeholders.
	tab_command=''
	for argument in "$@"; do
		case "$argument" in
			tab:transform\(*) tab_command="${argument#tab:transform(}"; tab_command="${tab_command%)}" ;;
		esac
	done
	[ -n "$tab_command" ] || exit 1
	# The row under the cursor, passed by fzf as {}.
	current_row=$(sed -n '1p' "$SETUP_GLOBAL_FZF_INPUT")
	sed -n '2p' "$SETUP_GLOBAL_FZF_INPUT" > "$SETUP_GLOBAL_FZF_ACTIONS.selected"
	# The ticked-rows file and current row wrapped in single quotes, as fzf passes them.
	# Kept in variables because Bash 3.2 keeps quotes written inside a replacement.
	quoted_selected="'$SETUP_GLOBAL_FZF_ACTIONS.selected'"
	quoted_row="'$current_row'"
	# Substitute the two placeholders as fzf does, then cross a clean shell boundary.
	action="${tab_command//\{+f\}/$quoted_selected}"
	action="${action//\{\}/$quoted_row}"
	env -i PATH="$PATH" sh -c "$action" > "$SETUP_GLOBAL_FZF_ACTIONS" || exit 1
	sed -n '2,3p' "$SETUP_GLOBAL_FZF_INPUT" > "$SETUP_GLOBAL_FZF_ACTIONS.selected"
	env -i PATH="$PATH" sh -c "$action" >> "$SETUP_GLOBAL_FZF_ACTIONS" || exit 1
fi
printf '%s\n' "${SETUP_GLOBAL_FZF_SELECTION:-}"
exit "${SETUP_GLOBAL_FZF_STATUS:-0}"
EOF

	chmod +x "$bin_dir/fzf"
}

# Checks that fzf opens with every skill ticked except the saved exclusion.
#
# @param  {string}  arguments_path
#     File containing the fzf command arguments.
# @param  {string}  input_path
#     File containing the ordered skill entries passed to fzf.
# @param  {string}  excluded_skill
#     Saved exclusion that fzf must leave unticked.
assert_fzf_start_selection() {
	# File containing the fzf command arguments.
	local arguments_path="$1"
	# File containing the ordered skill entries passed to fzf.
	local input_path="$2"
	# Saved exclusion that fzf must leave unticked.
	local excluded_skill="$3"
	# Start action sequence received by the fzf stand-in.
	local fzf_bind
	# Start actions that have not yet matched an input skill.
	local remaining_actions
	# Action expected for the current canonical skill.
	local expected_action
	# Action generated for the current canonical skill.
	local actual_action
	# Canonical skill currently being matched to a start action.
	local skill_name
	# Whether the input row is a heading or skill.
	local row_kind

	fzf_bind=$(grep '^load:' "$arguments_path")
	remaining_actions="${fzf_bind#load:}"

	while IFS=$'\t' read -r row_kind skill_name _; do
		if [ "$row_kind" = heading ] || [ "$skill_name" = "$excluded_skill" ]; then
			expected_action='down'
		else
			expected_action='toggle+down'
		fi

		actual_action="${remaining_actions:0:${#expected_action}}"
		assert_equals "$actual_action" "$expected_action"
		remaining_actions="${remaining_actions#"$actual_action"}"
		remaining_actions="${remaining_actions#+}"
	done < "$input_path"

	assert_equals "$remaining_actions" 'first'
}

# Checks collection headings, counts and alphabetical skill order in a picker.
#
# @param  {string}  input_path
#     File containing picker rows.
# @param  {string}  picker_type
#     Whether the rows come from fzf or the numbered picker.
assert_picker_group_order() {
	# The picker output to inspect.
	local input_path="$1"
	# The row format to parse.
	local picker_type="$2"

	if ! python3 - "$input_path" "$picker_type" <<'PY'; then
import re
import sys

headings = []
current = None
skills = []

with open(sys.argv[1], encoding="utf-8") as picker_output:
	for line in picker_output:
		row = line.strip()
		if sys.argv[2] == "fzf":
			kind, name, display = row.split("\t", 2)
			heading = re.fullmatch(r"(\S+) \((\d+)\)", display) if kind == "heading" and name else None
			skill = re.match(r"^([^\s]+)", name) if kind == "skill" else None
		else:
			heading = re.fullmatch(r"(\S+) \((\d+)\)", row)
			skill = re.match(r"^\[[ x]\]\s+\d+\. ([^\s]+)", row)
		if heading:
			if current and len(skills) != current[1]:
				sys.exit(f"{current[0]}: expected {current[1]} skills, found {len(skills)}")
			current = (heading.group(1), int(heading.group(2)))
			headings.append(current[0])
			skills = []
		elif skill and current:
			skills.append(skill.group(1))
			if skills != sorted(skills):
				sys.exit(f"{current[0]}: skills out of order: {skills}")

if not headings or headings != sorted(headings):
	sys.exit(f"collection headings out of order: {headings}")
if len(skills) != current[1]:
	sys.exit(f"{current[0]}: expected {current[1]} skills, found {len(skills)}")
PY
		fail 'Expected alphabetical collections with sorted skills and correct counts'
	fi
}

# Creates a Codex configuration that setup-global must replace.
#
# @param  {string}  home_dir
#     Isolated home directory for one setup run.
create_existing_config() {
	# The isolated home where the existing Codex config is created.
	local home_dir="$1"

	mkdir -p "$home_dir/.codex"
	printf 'custom_setting = "keep"\n' > "$home_dir/.codex/config.toml"
}

# Creates the agent-tools package folders that setup installs missing commands
# from, inside an isolated home.
#
# @param  {string}  home_dir
#     Isolated home directory for one setup run.
create_agent_tools_checkout() {
	# The isolated home where the package checkout is created.
	local home_dir="$1"

	mkdir -p "$home_dir/Dev/Repositories/Packages/agent-tools/packages/"{friction,team-send,doc-paths}
}

# Runs the global setup in a temporary home with test-only command stubs.
#
# @param  {string}  home_dir
#     Isolated home directory for the setup run.
# @param  {string}  ...
#     Additional setup-global arguments.
run_setup() {
	# The isolated home passed to the Codex setup run.
	local home_dir="$1"
	shift
	run_setup_target "$home_dir" "--codex" "$@"
}

# Runs setup-global with a selected target or without an explicit target.
#
# When SETUP_GLOBAL_TEST_TERMINAL is true, setup runs in a terminal driven by
# expect. If SETUP_GLOBAL_TEST_TERMINAL_INPUT is set, its value is typed exactly
# as given once the numbered picker asks its question, so a test includes its
# own carriage return or Ctrl-D. Without it, nothing is typed. Either way the
# run waits for setup to exit and returns setup's exit status. The run fails if
# the question does not appear within 20 seconds, if setup does not exit within
# 20 seconds after that, or if setup is killed by a signal.
#
# @param  {string}  home_dir
#     Isolated home directory for the setup run.
# @param  {string}  target
#     Setup target option, or an empty string to exercise automatic targeting.
# @param  {string}  ...
#     Additional setup-global arguments.
run_setup_target() {
	# Isolated home directory for the setup run.
	local home_dir="$1"
	# Setup target option, or empty for automatic targeting.
	local target="$2"
	# Directory containing test-only command stubs.
	local bin_dir="$TEST_ROOT/bin"
	# Whether backup moves should fail.
	local fail_backup_move="${SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE:-0}"
	# Command path used by the setup process.
	local setup_path="${SETUP_GLOBAL_TEST_PATH:-$bin_dir:$PATH}"
	shift 2
	# Most cases accept the setup plan with --yes. The confirmation cases set
	# SETUP_GLOBAL_TEST_WITHOUT_YES so they can see the prompt or the refusal.
	if [ "${SETUP_GLOBAL_TEST_WITHOUT_YES:-false}" != true ]; then
		set -- "$@" --yes
	fi

	mkdir -p "$home_dir"

	(
		# The isolated home used by the setup process.
		export HOME="$home_dir"
		# The command path that makes the setup process use test stubs. It changes
		# only inside this subshell, so the stubs never reach later tests.
		# shellcheck disable=SC2030
		export PATH="$setup_path"
		# The cli-style stub that points setup at the test adapter. A test can set
		# SETUP_GLOBAL_TEST_CLI_STYLE_BIN to a missing path to run setup without it.
		export CLI_STYLE_BIN="${SETUP_GLOBAL_TEST_CLI_STYLE_BIN:-$bin_dir/cli-style}"
		# The cli-style installer path that the bash stub logs instead of running.
		export SETUP_GLOBAL_INSTALLER="$REPO_DIR/scripts/install-cli-style.sh"
		# The repository sync script path that the bash stub logs instead of running.
		export SETUP_GLOBAL_SYNC="$REPO_DIR/scripts/sync.sh"
		# The repository validation script path that the bash stub logs instead of running.
		export SETUP_GLOBAL_VALIDATE="$REPO_DIR/scripts/validate.sh"
		# The file where the bash stub records skipped installer, sync and validation runs.
		export SETUP_GLOBAL_CALL_LOG="$home_dir/setup-global-calls.log"
		# The file recording calls to the uv stub.
		export SETUP_GLOBAL_UV_LOG="$home_dir/uv-calls.log"
		# The adapter that prints setup output unchanged instead of styling it.
		export SETUP_GLOBAL_TEST_ADAPTER="$bin_dir/cli-style-adapter.sh"
		# Whether the backup move stub must fail.
		export SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE="$fail_backup_move"

		# An empty target expands to nothing so setup-global picks the target itself.
		if [ "${SETUP_GLOBAL_TEST_TERMINAL:-false}" = true ]; then
			# The expect script is read from standard input because expect 5.45
			# does not set argv for a script passed with -c.
			/usr/bin/expect -f - bash "$REPO_DIR/scripts/setup-global.sh" ${target:+"$target"} "$@" <<'EXPECT'
set timeout 20
spawn {*}$argv
if {[info exists env(SETUP_GLOBAL_TEST_TERMINAL_INPUT)]} {
	expect {
		-exact "Enter skill numbers or collection names to leave out, separated by spaces (or q to cancel): " {}
		timeout { puts stderr "Picker prompt did not appear within 20 seconds"; exit 1 }
		eof { puts stderr "Picker prompt did not appear before setup exited"; exit 1 }
	}
	send -- $env(SETUP_GLOBAL_TEST_TERMINAL_INPUT)
}
if {[info exists env(SETUP_GLOBAL_TEST_CONFIRMATION_INPUT)]} {
	expect {
		-exact "Apply these changes? \[y/N\] " {}
		timeout { puts stderr "Confirmation prompt did not appear within 20 seconds"; exit 1 }
		eof { puts stderr "Confirmation prompt did not appear before setup exited"; exit 1 }
	}
	send -- $env(SETUP_GLOBAL_TEST_CONFIRMATION_INPUT)
}
expect {
	eof {}
	timeout { puts stderr "Setup did not exit within 20 seconds"; exit 1 }
}
set status [wait]
if {[lindex $status 4] eq "CHILDKILLED"} {
	puts stderr "Setup was killed by [lindex $status 5]"
	exit 1
}
exit [lindex $status 3]
EXPECT
		else
			bash "$REPO_DIR/scripts/setup-global.sh" ${target:+"$target"} "$@"
		fi
	)
}

# Prints one line per path in a test directory, with a checksum for each file
# and the target of each link, so two runs can be compared.
#
# @param  {string}  directory
#     The directory to inspect.
snapshot_test_directory() {
	# The directory whose paths and contents are listed.
	local directory="$1"
	# The current path within the directory.
	local file_path

	while IFS= read -r file_path; do
		if [ -L "$file_path" ]; then
			printf 'link %s %s\n' "$file_path" "$(readlink "$file_path")"
		elif [ -f "$file_path" ]; then
			printf 'file %s %s\n' "$file_path" "$(shasum < "$file_path")"
		else
			printf 'directory %s\n' "$file_path"
		fi
	done < <(find "$directory" -print | LC_ALL=C sort)
}

# Creates a temporary canonical skill that the EXIT trap removes.
create_added_skill() {
	mkdir -p "$ADDED_SKILL_DIR"
	printf -- '---\nname: %s\ndescription: Temporary setup test skill.\n---\n' "$ADDED_SKILL_NAME" > "$ADDED_SKILL_DIR/SKILL.md"
}

# Asserts that setup-global preserved the old configuration in a timestamped backup.
#
# @param  {string}  home_dir
#     Isolated home directory inspected after setup.
assert_timestamped_backup() {
	# The isolated home whose Codex config backup is checked.
	local home_dir="$1"
	# The timestamped backups of the original Codex config.
	local backups=("$home_dir/.codex/config.toml.bak."*)

	assert_file "${backups[0]}"
	assert_equals "$(cat "${backups[0]}")" 'custom_setting = "keep"'
}

test_help_hides_backup_bypass() {
	# The file capturing the setup help text.
	local output="$TEST_ROOT/help.txt"

	/bin/bash "$REPO_DIR/scripts/setup-global.sh" --help > "$output"

	assert_not_contains "$output" "--no-backup"
}

test_public_backup_bypass_is_rejected() {
	# The isolated home for the rejected backup option.
	local home_dir="$TEST_ROOT/no-backup"
	# The output from the rejected backup option.
	local output="$TEST_ROOT/no-backup.txt"

	create_existing_config "$home_dir"
	if run_setup "$home_dir" --no-backup > "$output" 2>&1; then
		fail "Expected --no-backup to be rejected"
	fi

	assert_contains "$output" "Usage:"
	assert_equals "$(cat "$home_dir/.codex/config.toml")" 'custom_setting = "keep"'
}

test_default_setup_skips_repository_refresh() {
	# The isolated home for the default setup run.
	local home_dir="$TEST_ROOT/default-setup"
	# The file recording any repository refresh calls.
	local calls="$home_dir/setup-global-calls.log"

	create_existing_config "$home_dir"
	run_setup "$home_dir" > /dev/null

	assert_not_contains "$calls" "$REPO_DIR/scripts/sync.sh"
	assert_not_contains "$calls" "$REPO_DIR/scripts/validate.sh"
}

# Checks that both targets leave an available doc-paths command untouched.
test_existing_doc_paths_is_preserved() {
	# Isolated home for the setup run.
	local home_dir="$TEST_ROOT/existing-doc-paths"

	run_setup_target "$home_dir" "--both" > /dev/null

	assert_not_exists "$home_dir/uv-calls.log"
}

# A missing installer must be reported for every command needed by both agents.
test_preflight_reports_missing_uv_without_changes() {
	# The isolated home for the rejected setup run.
	local home_dir="$TEST_ROOT/preflight-no-uv"
	# The stub directory with no installed agent-tools commands.
	local bin_dir="$TEST_ROOT/preflight-no-uv-bin"
	# The setup output containing each missing command and its fix.
	local output="$TEST_ROOT/preflight-no-uv.txt"
	# The home snapshot before setup starts.
	local before

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	trash "$bin_dir/friction" "$bin_dir/team-send" "$bin_dir/doc-paths" "$bin_dir/uv"
	mkdir -p "$home_dir/.agents"
	create_agent_tools_checkout "$home_dir"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	before=$(snapshot_test_directory "$home_dir")

	if SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--both" --exclude accessibility > "$output" 2>&1; then
		fail 'Expected setup to stop when uv is missing'
	fi

	assert_contains "$output" 'friction is not installed. Install uv so setup can install it.'
	assert_contains "$output" 'team-send is not installed. Install uv so setup can install it.'
	assert_contains "$output" 'doc-paths is not installed. Install uv so setup can install it.'
	assert_not_contains "$output" 'Clone agent-tools'
	assert_contains "$output" 'Setup stopped before changing anything.'
	assert_equals "$(snapshot_test_directory "$home_dir")" "$before"
	assert_not_exists "$home_dir/setup-global-calls.log"
}

# A missing package checkout must be reported before setup saves skill choices.
test_preflight_reports_missing_checkout_without_changes() {
	# The isolated home for the rejected setup run.
	local home_dir="$TEST_ROOT/preflight-no-checkout"
	# The stub directory with no installed agent-tools commands.
	local bin_dir="$TEST_ROOT/preflight-no-checkout-bin"
	# The setup output containing each missing command and its fix.
	local output="$TEST_ROOT/preflight-no-checkout.txt"
	# The expected checkout location, deliberately absent.
	local source_dir="$home_dir/Dev/Repositories/Packages/agent-tools"
	# The home snapshot before setup starts.
	local before

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	trash "$bin_dir/friction" "$bin_dir/team-send" "$bin_dir/doc-paths"
	mkdir -p "$home_dir"
	before=$(snapshot_test_directory "$home_dir")

	if SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--both" --include-all > "$output" 2>&1; then
		fail 'Expected setup to stop when the agent-tools checkout is missing'
	fi

	assert_contains "$output" "friction is not installed. Clone agent-tools to $source_dir so setup can install it."
	assert_contains "$output" "team-send is not installed. Clone agent-tools to $source_dir so setup can install it."
	assert_contains "$output" "doc-paths is not installed. Clone agent-tools to $source_dir so setup can install it."
	assert_contains "$output" 'Setup stopped before changing anything.'
	assert_equals "$(snapshot_test_directory "$home_dir")" "$before"
	assert_not_exists "$home_dir/.agents/skill-exclusions"
}

# Installed commands need neither uv nor the package checkout.
test_preflight_accepts_installed_commands_without_installer() {
	# The isolated home for a setup run with installed commands.
	local home_dir="$TEST_ROOT/preflight-installed"
	# The stub directory without uv.
	local bin_dir="$TEST_ROOT/preflight-installed-bin"

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	trash "$bin_dir/uv"
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--both" > /dev/null

	assert_not_exists "$home_dir/uv-calls.log"
	assert_link "$home_dir/.agents/AGENTS.md"
}

# Codex setup does not require friction when its other commands are installed.
test_preflight_checks_only_codex_commands() {
	# The isolated home for Codex setup.
	local home_dir="$TEST_ROOT/preflight-codex"
	# The stub directory without friction.
	local bin_dir="$TEST_ROOT/preflight-codex-bin"

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	trash "$bin_dir/friction" "$bin_dir/uv"
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--codex" > /dev/null

	assert_not_exists "$home_dir/uv-calls.log"
	assert_link "$home_dir/.agents/AGENTS.md"
}

# Status reports skill links without checking installation prerequisites.
test_status_skips_agent_tools_preflight() {
	# The isolated home for the status run.
	local home_dir="$TEST_ROOT/status-no-agent-tools"
	# The stub directory without agent-tools commands.
	local bin_dir="$TEST_ROOT/status-no-agent-tools-bin"
	# The status output.
	local output="$TEST_ROOT/status-no-agent-tools.txt"

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	trash "$bin_dir/friction" "$bin_dir/team-send" "$bin_dir/doc-paths" "$bin_dir/uv"
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--both" --status > "$output"

	assert_not_contains "$output" 'is not installed'
	assert_not_contains "$output" 'Setup stopped before changing anything.'
	assert_not_exists "$home_dir/setup-global-calls.log"
}

# Checks that global setup installs a missing doc-paths command once for both targets.
test_missing_doc_paths_is_installed() {
	# Isolated home for the setup run.
	local home_dir="$TEST_ROOT/install-doc-paths"
	# Isolated command directory without doc-paths.
	local bin_dir="$TEST_ROOT/install-bin"

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	mv "$bin_dir/doc-paths" "$bin_dir/doc-paths-disabled"
	create_agent_tools_checkout "$home_dir"
	# The stub command path used for this isolated setup run.
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--both" > /dev/null

	assert_contains "$home_dir/uv-calls.log" "tool install --from $home_dir/Dev/Repositories/Packages/agent-tools/packages/doc-paths doc-paths"
	assert_equals "$(wc -l < "$home_dir/uv-calls.log" | tr -d ' ')" '1'
	assert_file "$bin_dir/doc-paths"
}

# Checks that Codex setup on its own installs a missing doc-paths command.
test_codex_installs_missing_doc_paths() {
	# Isolated home for the setup run.
	local home_dir="$TEST_ROOT/codex-install-doc-paths"
	# Isolated command directory without doc-paths.
	local bin_dir="$TEST_ROOT/codex-install-bin"

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	mv "$bin_dir/doc-paths" "$bin_dir/doc-paths-disabled"
	create_agent_tools_checkout "$home_dir"
	# The stub command path used for this isolated setup run.
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--codex" > /dev/null

	assert_equals "$(wc -l < "$home_dir/uv-calls.log" | tr -d ' ')" '1'
	assert_file "$bin_dir/doc-paths"
}

# Refresh runs the repository sync, which validates the output itself, so setup
# does not run validation a second time.
test_refresh_runs_repository_sync() {
	# The isolated home for the refresh setup run.
	local home_dir="$TEST_ROOT/refresh"
	# The file recording repository refresh calls.
	local calls="$home_dir/setup-global-calls.log"

	create_existing_config "$home_dir"
	run_setup "$home_dir" --refresh > /dev/null

	assert_contains "$calls" "$REPO_DIR/scripts/sync.sh"
	assert_not_contains "$calls" "$REPO_DIR/scripts/validate.sh"
}

# A script without --yes sees the whole plan and leaves its home untouched.
test_non_terminal_plan_requires_yes() {
	# The isolated home and captured preview for this run.
	local home_dir="$TEST_ROOT/preview-without-yes" output="$TEST_ROOT/preview-without-yes.txt"
	# The home state before setup is offered.
	local before
	create_existing_config "$home_dir"
	before=$(snapshot_test_directory "$home_dir")
	if SETUP_GLOBAL_TEST_WITHOUT_YES=true run_setup_target "$home_dir" --codex --exclude accessibility > "$output" 2>&1; then
		fail 'Setup applied without --yes in a non-terminal'
	fi
	assert_contains "$output" 'Codex settings:'
	assert_contains "$output" 'Links:'
	assert_contains "$output" 'Selection:'
	assert_contains "$output" 'Setup needs --yes'
	assert_equals "$(snapshot_test_directory "$home_dir")" "$before"
	assert_not_exists "$home_dir/setup-global-calls.log"
}

# Declining at the final terminal question leaves the selection and links untouched.
test_terminal_decline_preserves_home() {
	# The isolated home and captured terminal output.
	local home_dir="$TEST_ROOT/preview-decline" output="$TEST_ROOT/preview-decline.txt"
	# The home state before the plan is printed.
	local before
	create_existing_config "$home_dir"
	before=$(snapshot_test_directory "$home_dir")
	SETUP_GLOBAL_TEST_WITHOUT_YES=true SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_CONFIRMATION_INPUT=$'n\r' run_setup_target "$home_dir" --codex --exclude accessibility > "$output"
	assert_contains "$output" 'Apply these changes?'
	assert_contains "$output" 'Setup cancelled. Nothing changed.'
	assert_equals "$(snapshot_test_directory "$home_dir")" "$before"
	assert_not_exists "$home_dir/setup-global-calls.log"
}

# Accepting the terminal confirmation creates the planned links.
test_terminal_accept_creates_links() {
	# The isolated home and captured terminal output.
	local home_dir="$TEST_ROOT/preview-accept" output="$TEST_ROOT/preview-accept.txt"

	SETUP_GLOBAL_TEST_WITHOUT_YES=true SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_CONFIRMATION_INPUT=$'y\r' run_setup_target "$home_dir" --codex > "$output"

	assert_contains "$output" 'Apply these changes?'
	assert_link "$home_dir/.agents/AGENTS.md"
	assert_link "$home_dir/.codex/hooks.json"
	assert_link "$home_dir/.local/bin/trash"
}

# A second run against a completed install exits cleanly without confirmation.
test_nothing_to_change_exits_without_yes() {
	# The isolated home and captured second-run output.
	local home_dir="$TEST_ROOT/preview-no-change" output="$TEST_ROOT/preview-no-change.txt"
	# The home state after the first setup run.
	local before
	run_setup "$home_dir" > /dev/null
	before=$(snapshot_test_directory "$home_dir")
	if ! SETUP_GLOBAL_TEST_WITHOUT_YES=true run_setup "$home_dir" > "$output"; then
		cat "$output"
		fail 'A completed setup still has a planned change'
	fi
	assert_contains "$output" 'Nothing to change.'
	assert_equals "$(snapshot_test_directory "$home_dir")" "$before"
}

# Setup backs up an existing Codex config with a timestamp before replacing it
# with the managed settings.
test_config_replacement_creates_timestamped_backup() {
	# The isolated home with a Codex config to back up.
	local home_dir="$TEST_ROOT/backup"

	create_existing_config "$home_dir"
	run_setup "$home_dir" > /dev/null

	assert_timestamped_backup "$home_dir"
	assert_contains "$home_dir/.codex/config.toml" 'approval_policy = "never"'
	assert_contains "$home_dir/.codex/config.toml" 'default_permissions = "project-edit"'
	assert_contains "$home_dir/.codex/config.toml" 'suppress_unstable_features_warning = true'
	assert_contains "$home_dir/.codex/config.toml" '[mcp_servers.codebase-memory-mcp]'
	assert_equals "$(grep -c '^default_tools_approval_mode = \"approve\"$' "$home_dir/.codex/config.toml")" "1"
	assert_contains "$home_dir/.codex/config.toml" '[features]'
	assert_contains "$home_dir/.codex/config.toml" 'hooks = true'
	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit]'
	assert_contains "$home_dir/.codex/config.toml" 'extends = ":workspace"'
	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit.workspace_roots]'
	assert_contains "$home_dir/.codex/config.toml" '"'"$home_dir"'/Dev/Repositories/Configuration/Agents" = true'
	assert_not_contains "$home_dir/.codex/config.toml" 'sandbox_mode'
	assert_not_contains "$home_dir/.codex/config.toml" '[sandbox_workspace_write]'
	assert_not_contains "$home_dir/.codex/config.toml" '[[hooks.'
	assert_link "$home_dir/.codex/hooks.json"
	assert_link "$home_dir/.codex/hooks/tool-call-checkpoint.sh"
	assert_link "$home_dir/.codex/hooks/guard-hcom-ack.sh"
}

# A hand-edited Codex config is backed up and rewritten once, then setup finds nothing to change.
test_user_config_is_rewritten_once() {
	# The isolated home and output from setup's second run.
	local home_dir="$TEST_ROOT/user-config-once" output="$TEST_ROOT/user-config-once.txt"
	# The timestamped backup of the original config.
	local backups

	mkdir -p "$home_dir/.codex"
	cat > "$home_dir/.codex/config.toml" <<'CONFIG'
custom_setting = "keep"


[tui]
alternate_screen = "never"

[profiles.work]
model = "keep"

[mcp_servers.mdn]
command = "old-mdn"
CONFIG
	run_setup "$home_dir" > /dev/null

	backups=("$home_dir/.codex/config.toml.bak."*)
	assert_file "${backups[0]}"
	assert_contains "${backups[0]}" 'command = "old-mdn"'
	assert_contains "$home_dir/.codex/config.toml" 'custom_setting = "keep"'
	assert_contains "$home_dir/.codex/config.toml" '[profiles.work]'
	assert_contains "$home_dir/.codex/config.toml" 'model = "keep"'
	assert_not_contains "$home_dir/.codex/config.toml" 'command = "old-mdn"'
	if ! SETUP_GLOBAL_TEST_WITHOUT_YES=true run_setup "$home_dir" > "$output"; then
		cat "$output"
		fail 'The rewritten Codex config changed again on the second run'
	fi
	assert_contains "$output" 'Nothing to change.'
	assert_equals "$(printf '%s\n' "$home_dir/.codex/config.toml.bak."*)" "${backups[0]}"
}

test_hook_file_is_replaced_with_managed_link() {
	# The isolated home with an old hooks file.
	local home_dir="$TEST_ROOT/legacy-hooks"
	# The timestamped backups of the old hooks file.
	local backups

	create_existing_config "$home_dir"
	printf '{"hooks": {}}\n' > "$home_dir/.codex/hooks.json"
	run_setup "$home_dir" > /dev/null

	backups=("$home_dir/.codex/hooks.json.bak."*)
	assert_file "${backups[0]}"
	assert_link "$home_dir/.codex/hooks.json"
	assert_equals "$(readlink "$home_dir/.codex/hooks.json")" "$REPO_DIR/dist/codex/hooks.json"
	assert_not_contains "$home_dir/.codex/config.toml" '[[hooks.'
}

# Checks that setup links both generated themes into whichever Claude config
# directory it is given, covering both ~/.claude and ~/.claude-2.
test_claude_themes_are_linked_in_each_config_dir() {
	# Isolated home for both Claude setup runs.
	local home_dir="$TEST_ROOT/claude-themes"
	# Claude config directory currently being checked.
	local claude_dir
	# Generated Catppuccin theme currently being checked.
	local theme_name

	for claude_dir in "$home_dir/.claude" "$home_dir/.claude-2"; do
		run_setup_target "$home_dir" "--claude" --claude-dir "$claude_dir" > /dev/null

		for theme_name in catppuccin-mocha catppuccin-latte; do
			assert_link "$claude_dir/themes/$theme_name.json"
			assert_equals "$(readlink "$claude_dir/themes/$theme_name.json")" "$REPO_DIR/dist/claude/themes/$theme_name.json"
		done
	done
}

# Checks that setup leaves the user's own theme files and theme links unchanged.
test_claude_setup_preserves_user_theme() {
	# Isolated home with themes the user made.
	local home_dir="$TEST_ROOT/user-theme"
	# Theme that setup must preserve.
	local theme_path="$home_dir/.claude/themes/my-theme.json"
	# Theme link the user made, which setup must preserve.
	local linked_theme_path="$home_dir/.claude/themes/linked-theme.json"
	# File outside the themes folder that the user's link points to.
	local linked_theme_target="$home_dir/personal-theme.json"

	mkdir -p "$(dirname "$theme_path")"
	printf '{"name":"my-theme"}\n' > "$theme_path"
	printf '{"name":"personal-theme"}\n' > "$linked_theme_target"
	ln -s "$linked_theme_target" "$linked_theme_path"
	run_setup_target "$home_dir" "--claude" > /dev/null

	assert_file "$theme_path"
	assert_equals "$(cat "$theme_path")" '{"name":"my-theme"}'
	assert_link "$linked_theme_path"
	assert_equals "$(readlink "$linked_theme_path")" "$linked_theme_target"
}

# Checks that when setup replaces a plain theme file with a link, the old file
# goes to backups/themes and no backup is left in the themes folder.
test_claude_theme_replacement_uses_backups_directory() {
	# Isolated home with an existing theme file.
	local home_dir="$TEST_ROOT/replaced-theme"
	# Alternate Claude config directory under test.
	local claude_dir="$home_dir/.claude-2"
	# Theme replaced by the managed link.
	local theme_path="$claude_dir/themes/catppuccin-mocha.json"
	# Timestamped backups of the replaced theme.
	local backups

	mkdir -p "$(dirname "$theme_path")"
	printf '{"name":"old-theme"}\n' > "$theme_path"
	run_setup_target "$home_dir" "--claude" --claude-dir "$claude_dir" > /dev/null

	backups=("$claude_dir/backups/themes/catppuccin-mocha.json.bak."*)
	assert_file "${backups[0]}"
	assert_equals "$(cat "${backups[0]}")" '{"name":"old-theme"}'
	assert_link "$theme_path"
	assert_equals "$(readlink "$theme_path")" "$REPO_DIR/dist/claude/themes/catppuccin-mocha.json"

	if compgen -G "$claude_dir/themes/*.bak.*" > /dev/null; then
		fail "Expected no theme backup in $claude_dir/themes"
	fi
}

# Checks that each setup mode installs one shared trash link and leaves it alone on a rerun.
test_trash_wrapper_links_once_for_each_mode() {
	# Setup mode being checked in an isolated home.
	local target
	# Isolated home for the current setup mode.
	local home_dir
	# Setup output, which should report the trash wrapper once.
	local output
	# Installed trash wrapper link.
	local link
	# Any backup made during a rerun.
	local backups

	for target in claude codex both; do
		home_dir="$TEST_ROOT/trash-$target"
		output="$TEST_ROOT/trash-$target.txt"
		link="$home_dir/.local/bin/trash"

		run_setup_target "$home_dir" "--$target" > "$output"

		assert_link "$link"
		assert_equals "$(readlink "$link")" "$REPO_DIR/src/bin/trash"
		assert_equals "$(grep -Fc '"label": "Trash wrapper"' "$output")" '1'

		run_setup_target "$home_dir" "--$target" > "$output"

		assert_link "$link"
		assert_equals "$(readlink "$link")" "$REPO_DIR/src/bin/trash"
		assert_contains "$output" 'Nothing to change.'
		backups=("$home_dir/.local/bin/trash.bak."*)
		assert_not_exists "${backups[0]}"
	done
}

# Checks that a pre-existing trash command is preserved when setup installs the wrapper.
test_trash_wrapper_backs_up_existing_file() {
	# Isolated home with a pre-existing trash command.
	local home_dir="$TEST_ROOT/trash-existing"
	# Target path for the shared wrapper.
	local link="$home_dir/.local/bin/trash"
	# Setup output naming the backup.
	local output="$TEST_ROOT/trash-existing.txt"
	# Timestamped backups of the pre-existing command.
	local backups

	mkdir -p "$(dirname "$link")"
	printf 'keep my trash command\n' > "$link"

	run_setup_target "$home_dir" "--both" > "$output"

	backups=("$home_dir/.local/bin/trash.bak."*)
	assert_file "${backups[0]}"
	assert_equals "$(cat "${backups[0]}")" 'keep my trash command'
	assert_link "$link"
	assert_equals "$(readlink "$link")" "$REPO_DIR/src/bin/trash"
	assert_contains "$output" "backup at ~/.local/bin/$(basename "${backups[0]}")"
}

# Checks that setup adds the trash wrapper inside a symlinked ~/.local/bin, such as one managed by dotfiles, instead of replacing the folder.
test_trash_wrapper_preserves_symlinked_bin_directory() {
	# Isolated home with a dotfiles bin directory.
	local home_dir="$TEST_ROOT/trash-symlinked-bin"
	# Existing directory that the bin symlink points to.
	local bin_dir="$home_dir/dotfiles-bin"
	# Symlink that setup must leave in place.
	local bin_link="$home_dir/.local/bin"
	# Any backup of the bin directory made by setup.
	local backups
	# The setup preview printed before it applies the links.
	local output="$TEST_ROOT/trash-symlinked-bin.txt"

	mkdir -p "$home_dir/.local" "$bin_dir"
	ln -s "$bin_dir" "$bin_link"

	run_setup_target "$home_dir" "--both" > "$output"

	assert_not_contains "$output" 'Replace ~/.local/bin with a directory'
	assert_not_contains "$output" 'Save ~/.local/bin in'
	assert_not_contains "$output" 'Remove older backup ~/.local/bin.bak.'
	assert_dir_link "$bin_link"
	assert_equals "$(readlink "$bin_link")" "$bin_dir"
	backups=("$home_dir/.local/bin.bak."*)
	assert_not_exists "${backups[0]}"
	assert_link "$bin_dir/trash"
	assert_equals "$(readlink "$bin_dir/trash")" "$REPO_DIR/src/bin/trash"
}

# A broken repository link is removed before setup links its replacement, so the
# preview lists no backup for it.
test_stale_repo_link_has_no_backup_in_plan() {
	# The isolated home and captured setup preview.
	local home_dir="$TEST_ROOT/stale-link-plan" output="$TEST_ROOT/stale-link-plan.txt"
	# The managed hook path occupied by a broken repository link.
	local link="$home_dir/.codex/hooks/tool-call-checkpoint.sh"
	# Any backup of the broken link.
	local backups

	mkdir -p "$home_dir/.codex/hooks"
	ln -s "$REPO_DIR/dist/codex/hooks/missing-tool-call-checkpoint.sh" "$link"
	printf 'keep an older backup\n' > "$link.bak.20200101-000000"
	run_setup "$home_dir" > "$output"

	assert_contains "$output" 'Remove ~/.codex/hooks/tool-call-checkpoint.sh'
	assert_contains "$output" 'Link ~/.codex/hooks/tool-call-checkpoint.sh to'
	assert_not_contains "$output" 'Save ~/.codex/hooks/tool-call-checkpoint.sh in'
	assert_not_contains "$output" 'Remove older backup ~/.codex/hooks/tool-call-checkpoint.sh.bak.'
	assert_link "$link"
	assert_equals "$(readlink "$link")" "$REPO_DIR/dist/codex/hooks/tool-call-checkpoint.sh"
	backups=("$home_dir/.codex/hooks/tool-call-checkpoint.sh.bak."*)
	assert_equals "${backups[0]}" "$link.bak.20200101-000000"
	assert_equals "$(cat "${backups[0]}")" 'keep an older backup'
}

# Setup keeps the workspace roots a user already has when it rewrites the Codex
# permission profile, and removes the .git/config write rule that older setups
# added, because that rule stops Codex running any command in a linked worktree.
test_permission_profile_keeps_roots_and_drops_git_config_rule() {
	# The isolated home with an older Codex permission profile.
	local home_dir="$TEST_ROOT/permission-profile"

	create_existing_config "$home_dir"
	{
		printf '\n[sandbox_workspace_write]\nnetwork_access = false\nexclude_slash_tmp = true\nwritable_roots = ["/tmp/keep"]\n'
		printf '\n[permissions.project-edit.workspace_roots]\n"/tmp/already-added" = true\n'
		printf '\n[permissions.project-edit.filesystem.":workspace_roots"]\n".git/config" = "write"\n".git/config.lock" = "write"\n'
	} >> "$home_dir/.codex/config.toml"
	run_setup "$home_dir" > /dev/null

	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit.network]'
	assert_contains "$home_dir/.codex/config.toml" 'enabled = true'
	assert_contains "$home_dir/.codex/config.toml" '"/tmp/keep" = true'
	assert_contains "$home_dir/.codex/config.toml" '"/tmp/already-added" = true'
	assert_not_contains "$home_dir/.codex/config.toml" '[permissions.project-edit.filesystem.":workspace_roots"]'
	assert_not_contains "$home_dir/.codex/config.toml" '".git/config" = "write"'
	assert_not_contains "$home_dir/.codex/config.toml" '".git/config.lock" = "write"'
	assert_not_contains "$home_dir/.codex/config.toml" 'sandbox_mode'
	assert_not_contains "$home_dir/.codex/config.toml" '[sandbox_workspace_write]'
}

test_skills_are_installed_and_editable() {
	create_test_repo_copy test_skills_are_installed_and_editable

	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/skills-installed"
	# Temporary source marker name.
	local marker_name
	marker_name="setup-global-test-marker-$(basename "$TEST_ROOT")"
	# Marker path in the temporary canonical skill.
	local source_marker="$ADDED_SKILL_DIR/$marker_name"

	create_added_skill
	run_setup "$home_dir" > /dev/null

	assert_dir_link "$home_dir/.agents/skills/$ADDED_SKILL_NAME"
	printf 'visible through the installed link\n' > "$home_dir/.agents/skills/$ADDED_SKILL_NAME/$marker_name"
	assert_contains "$source_marker" 'visible through the installed link'
}

test_exclusions_persist_and_report() {
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/skill-exclusions"
	# Output from the initial exclusion run.
	local output="$TEST_ROOT/skill-exclusions.txt"
	# Output from the persisted exclusion run.
	local rerun_output="$TEST_ROOT/skill-exclusions-rerun.txt"
	# Output after including one skill.
	local include_output="$TEST_ROOT/skill-exclusions-include.txt"
	# Output after including all skills.
	local include_all_output="$TEST_ROOT/skill-exclusions-include-all.txt"
	# Expected exclusion status line.
	local excluded_message='Excluded: accessibility, accessibility-audit (from ~/.agents/skill-exclusions; run with --include-all to restore)'

	run_setup_target "$home_dir" "" --exclude accessibility,accessibility-audit > "$output"
	assert_contains "$output" "$excluded_message"
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility-audit'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.agents/skills/accessibility-audit"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility-audit"

	run_setup_target "$home_dir" "--both" > "$rerun_output"
	assert_contains "$rerun_output" "$excluded_message"
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility"

	run_setup_target "$home_dir" "" --include accessibility > "$include_output"
	assert_contains "$include_output" 'Excluded: accessibility-audit (from ~/.agents/skill-exclusions; run with --include-all to restore)'
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.claude/skills/accessibility"
	assert_not_exists "$home_dir/.agents/skills/accessibility-audit"

	run_setup_target "$home_dir" "" --include-all > "$include_all_output"
	assert_not_contains "$include_all_output" 'Excluded:'
	assert_dir_link "$home_dir/.agents/skills/accessibility-audit"
	assert_dir_link "$home_dir/.claude/skills/accessibility-audit"
	assert_not_exists "$home_dir/.agents/skill-exclusions"
}

test_new_skill_installs_after_exclusion() {
	create_test_repo_copy test_new_skill_installs_after_exclusion

	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/new-skill"

	run_setup "$home_dir" --exclude accessibility > /dev/null
	create_added_skill
	run_setup "$home_dir" > /dev/null

	assert_dir_link "$home_dir/.agents/skills/$ADDED_SKILL_NAME"
	assert_not_exists "$home_dir/.agents/skills/accessibility"
}

test_claude_only_exclusion_creates_agents_directory() {
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/claude-only-exclusion"
	# Output from the Claude-only exclusion run.
	local output="$TEST_ROOT/claude-only-exclusion.txt"

	run_setup_target "$home_dir" "--claude" --exclude accessibility > "$output"

	assert_dir "$home_dir/.agents"
	assert_file "$home_dir/.agents/skill-exclusions"
	assert_not_exists "$home_dir/.codex"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
	assert_contains "$output" 'Excluded: accessibility (from ~/.agents/skill-exclusions; run with --include-all to restore)'
}

test_unknown_skill_fails_without_changes() {
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/unknown-skill"
	# Output from the rejected setup run.
	local output="$TEST_ROOT/unknown-skill.txt"

	mkdir -p "$home_dir/.agents"
	printf 'accessibility\n' > "$home_dir/.agents/skill-exclusions"
	if run_setup "$home_dir" --exclude missing-setup-global-skill > "$output" 2>&1; then
		fail 'Expected an unknown skill to be rejected'
	fi

	assert_contains "$output" 'Unknown skill: missing-setup-global-skill'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'accessibility'
	assert_not_exists "$home_dir/.codex"
	assert_not_exists "$home_dir/.claude"
}

test_removed_skill_can_be_included() {
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/removed-skill"
	# Saved exclusion with no canonical skill folder.
	local removed_skill='removed-setup-global-skill'

	mkdir -p "$home_dir/.agents"
	printf '%s\n' "$removed_skill" > "$home_dir/.agents/skill-exclusions"
	run_setup "$home_dir" --include-all --include "$removed_skill" > /dev/null

	assert_not_exists "$home_dir/.agents/skill-exclusions"
}

test_unmanaged_excluded_directory_survives() {
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/unmanaged-excluded"
	# Content that an exclusion must preserve.
	local marker="$home_dir/.agents/skills/accessibility/keep.txt"

	run_setup "$home_dir" --exclude accessibility > /dev/null
	mkdir -p "$(dirname "$marker")"
	printf 'keep this directory\n' > "$marker"
	run_setup "$home_dir" > /dev/null

	assert_file "$marker"
}

test_unmanaged_included_skill_is_backed_up() {
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/unmanaged-included"
	# Output from the setup run.
	local output="$TEST_ROOT/unmanaged-included.txt"
	# Timestamped backup directories created for the unmanaged skill path.
	local backups

	mkdir -p "$home_dir/.agents/skills/accessibility"
	printf 'keep this content\n' > "$home_dir/.agents/skills/accessibility/keep.txt"
	run_setup "$home_dir" > "$output"

	backups=("$home_dir/.agents/backups/skills/accessibility.bak."*)
	assert_dir "${backups[0]}"
	assert_file "${backups[0]}/keep.txt"
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_contains "$output" 'backup at ~/.agents/backups/skills/accessibility.bak.'
}

test_status_reports_an_installed_skill() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-installed"
	# Output from the installed-skill report.
	local output="$TEST_ROOT/status-installed.txt"

	mkdir -p "$home_dir/.claude/skills"
	ln -s "$REPO_DIR/skills/accessibility/accessibility" "$home_dir/.claude/skills/accessibility"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'installed accessibility'
}

test_status_reports_a_missing_skill() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-missing"
	# Output from the missing-skill report.
	local output="$TEST_ROOT/status-missing.txt"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'missing bash'
}

test_status_reports_an_excluded_skill() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-excluded"
	# Output from the excluded-skill report.
	local output="$TEST_ROOT/status-excluded.txt"

	mkdir -p "$home_dir/.agents"
	printf 'accessibility-audit\n' > "$home_dir/.agents/skill-exclusions"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'excluded accessibility-audit'
}

test_status_reports_an_excluded_skill_with_a_lingering_link() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-lingering-link"
	# Output from the lingering-link report.
	local output="$TEST_ROOT/status-lingering-link.txt"
	# Excluded repo-owned link that the report must not remove.
	local lingering_link="$home_dir/.claude/skills/writing"

	mkdir -p "$home_dir/.agents" "$(dirname "$lingering_link")"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	ln -s "$REPO_DIR/skills/writing/writing" "$lingering_link"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'excluded writing'
	assert_contains "$output" 'link still present; run: scripts/setup-global.sh --claude --exclude writing'
	assert_equals "$(readlink "$lingering_link")" "$REPO_DIR/skills/writing/writing"
}

test_status_reports_conflicting_included_content() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-included-conflict"
	# Output from the included-conflict report.
	local output="$TEST_ROOT/status-included-conflict.txt"
	# Unmanaged included content that must remain conflicting.
	local conflict_file="$home_dir/.claude/skills/code-style/keep.txt"

	mkdir -p "$(dirname "$conflict_file")"
	printf 'keep this content\n' > "$conflict_file"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'conflicting code-style'
	assert_contains "$output" 'run: scripts/setup-global.sh --claude --include code-style'
	assert_equals "$(cat "$conflict_file")" 'keep this content'
}

test_status_reports_conflicting_excluded_content() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-excluded-conflict"
	# Output from the excluded-conflict report.
	local output="$TEST_ROOT/status-excluded-conflict.txt"
	# Unmanaged excluded content that must remain conflicting.
	local conflict_file="$home_dir/.claude/skills/code-style/keep.txt"

	mkdir -p "$home_dir/.agents" "$(dirname "$conflict_file")"
	printf 'code-style\n' > "$home_dir/.agents/skill-exclusions"
	printf 'keep this content\n' > "$conflict_file"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'conflicting code-style'
	assert_contains "$output" 'run: trash ~/.claude/skills/code-style'
	assert_equals "$(cat "$conflict_file")" 'keep this content'
}

test_status_does_not_change_files() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-read-only"
	# Output from the read-only status report.
	local output="$TEST_ROOT/status-read-only.txt"
	# Repo-owned link that must remain installed.
	local installed_link="$home_dir/.claude/skills/accessibility"
	# Unmanaged excluded content that must remain conflicting.
	local excluded_skill="$home_dir/.agents/skills/code-style/keep.txt"
	# The home contents before the status report.
	local home_before
	# The repository file state before the status report.
	local repo_before

	mkdir -p "$home_dir/.agents/skills" "$home_dir/.claude/skills" "$(dirname "$excluded_skill")"
	printf 'code-style\n' > "$home_dir/.agents/skill-exclusions"
	printf 'keep this content\n' > "$excluded_skill"
	ln -s "$REPO_DIR/skills/accessibility/accessibility" "$installed_link"
	home_before=$(snapshot_test_directory "$home_dir")
	repo_before=$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)

	run_setup_target "$home_dir" "" --status > "$output"

	assert_not_exists "$home_dir/setup-global-calls.log"
	assert_equals "$(snapshot_test_directory "$home_dir")" "$home_before"
	assert_equals "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" "$repo_before"
	assert_contains "$output" 'Claude skills'
	assert_contains "$output" 'Codex skills'
	assert_equals "$(readlink "$installed_link")" "$REPO_DIR/skills/accessibility/accessibility"
	assert_equals "$(cat "$excluded_skill")" 'keep this content'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'code-style'
	assert_not_exists "$home_dir/.codex"
}

# Checks that status stops with an install hint when cli-style is missing.
test_status_requires_cli_style_without_changes() {
	# Isolated home directory for the status report.
	local home_dir="$TEST_ROOT/status-without-cli-style"
	# Output from the rejected status report.
	local output="$TEST_ROOT/status-without-cli-style.txt"
	# The home contents before the status report.
	local home_before
	# The repository file state before the status report.
	local repo_before

	mkdir -p "$home_dir"
	home_before=$(snapshot_test_directory "$home_dir")
	repo_before=$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)

	if SETUP_GLOBAL_TEST_CLI_STYLE_BIN="$TEST_ROOT/missing-cli-style" run_setup_target "$home_dir" "--claude" --status > "$output" 2>&1; then
		fail '--status succeeded without cli-style'
	fi

	assert_contains "$output" 'cli-style is not installed. Run: scripts/install-cli-style.sh'
	assert_not_exists "$home_dir/setup-global-calls.log"
	assert_equals "$(snapshot_test_directory "$home_dir")" "$home_before"
	assert_equals "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" "$repo_before"
}

test_status_rejects_skill_options_without_changes() {
	# Isolated home directory for the rejected status run.
	local home_dir="$TEST_ROOT/status-with-skill-options"
	# Output from the rejected status run.
	local output="$TEST_ROOT/status-with-skill-options.txt"

	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	if run_setup_target "$home_dir" "--claude" --status --exclude accessibility > "$output" 2>&1; then
		fail 'Expected --status with --exclude to be rejected'
	fi

	assert_contains "$output" '--status cannot be combined with --select, --exclude, --include, or --include-all.'
	assert_contains "$output" 'Usage:'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
	assert_not_exists "$home_dir/setup-global-calls.log"
}

# Ensures the numbered selector defaults to both agents and saves its changes.
test_select_fallback_updates_skill_exclusions() {
	# Isolated home directory for the numbered selection run.
	local home_dir="$TEST_ROOT/select-fallback"
	# Output from the numbered selection run.
	local output="$TEST_ROOT/select-fallback.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

	# The stub command path and terminal input for this picker run.
	NO_COLOR=1 COLUMNS=80 SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'1 2\r' run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" '[x]  1. accessibility'
	assert_contains "$output" '[x]  2. accessibility-audit'
	assert_contains "$output" 'accessibility (2)'
	assert_contains "$output" '…'
	assert_not_contains "$output" 'Use this skill when editing HTML'
	assert_not_contains "$output" $'\033[2m'
	# Python counts UTF-8 characters even when the test shell uses a byte locale.
	if ! python3 - "$output" <<'PY'; then
import sys

with open(sys.argv[1], encoding="utf-8") as picker_output:
	for line in picker_output:
		row = line.rstrip("\r\n")
		if row.startswith(("[x]", "[ ]")) and len(row) > 80:
			sys.exit(1)
PY
		fail 'Expected numbered skill rows to fit within 80 columns'
	fi
	assert_picker_group_order "$output" numbered
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility-audit'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
	assert_dir_link "$home_dir/.agents/skills/bash"
	assert_dir_link "$home_dir/.claude/skills/bash"
}

# Ensures a collection name and skill number can be left out together.
test_select_fallback_excludes_collection_and_skill() {
	# Isolated home directory for the grouped numbered picker.
	local home_dir="$TEST_ROOT/select-fallback-collection"
	# Output from the grouped numbered picker.
	local output="$TEST_ROOT/select-fallback-collection.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

	SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'accessibility 3\r' run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility-audit'
	assert_contains "$home_dir/.agents/skill-exclusions" 'codex-insights'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.agents/skills/bash"
}

# Ensures an empty numbered selection keeps every skill without failing on macOS Bash.
test_select_fallback_empty_selection_includes_every_skill() {
	# Isolated home directory for an empty numbered selection.
	local home_dir="$TEST_ROOT/select-fallback-empty"
	# Output from the empty numbered selection run.
	local output="$TEST_ROOT/select-fallback-empty.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

	# The stub command path and terminal input for this picker run.
	SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'\r' run_setup_target "$home_dir" "" --select > "$output"

	assert_not_exists "$home_dir/.agents/skill-exclusions"
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.claude/skills/accessibility"
}

# Ensures cancelling the numbered selector preserves the saved exclusions.
test_select_fallback_cancel_preserves_existing_state() {
	# Isolated home directory for the cancelled numbered selection.
	local home_dir="$TEST_ROOT/select-fallback-cancel"
	# Output from the cancelled numbered selection.
	local output="$TEST_ROOT/select-fallback-cancel.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	# The stub command path and terminal input for this picker run.
	SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'q\r' run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures an older fzf uses the numbered selector and explains why.
test_select_old_fzf_uses_numbered_list() {
	assert_fzf_version_uses_numbered_list '0.60.0' 'select-old-fzf' 'fzf 0.60.0 cannot run this picker (it needs 0.74 or newer), so using the numbered list.'
}

# Checks that a supported fzf version opens the interactive picker.
#
# @param  {string}  version
#     The version reported by the fzf stand-in.
# @param  {string}  case_name
#     Unique name for the isolated test files.
assert_fzf_version_opens_picker() {
	# The version reported by the fzf stand-in.
	local version="$1"
	# Unique name for the isolated test files.
	local case_name="$2"
	# Isolated home directory for this version.
	local home_dir="$TEST_ROOT/$case_name"
	# Output from the picker.
	local output="$TEST_ROOT/$case_name.txt"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/$case_name-bin"
	# Arguments captured when fzf opens.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills passed to fzf.
	local fzf_input="$home_dir/fzf-input.txt"

	create_fzf_stub "$fzf_dir"
	# PATH here is this test's own value; ShellCheck confuses it with the copy run_setup_target changes in its subshell.
	# shellcheck disable=SC2031
	SETUP_GLOBAL_FZF_VERSION="$version" SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_STATUS=1 SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output" 2>&1

	assert_contains "$fzf_arguments" '--multi'
	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_not_contains "$output" 'Enter skill numbers or collection names to leave out'
}

# Checks that an unsupported or unreadable fzf version uses the numbered list.
#
# @param  {string}  version
#     The version reported by the fzf stand-in.
# @param  {string}  case_name
#     Unique name for the isolated test files.
# @param  {string}  notice
#     The explanation printed before the numbered list.
assert_fzf_version_uses_numbered_list() {
	# The version reported by the fzf stand-in.
	local version="$1"
	# Unique name for the isolated test files.
	local case_name="$2"
	# The explanation printed before the numbered list.
	local notice="$3"
	# Isolated home directory for this version.
	local home_dir="$TEST_ROOT/$case_name"
	# Output from the numbered list.
	local output="$TEST_ROOT/$case_name.txt"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/$case_name-bin"
	# Arguments that would be captured if fzf opened.
	local fzf_arguments="$home_dir/fzf-arguments.txt"

	create_fzf_stub "$fzf_dir"
	# PATH here is this test's own value; ShellCheck confuses it with the copy run_setup_target changes in its subshell.
	# shellcheck disable=SC2031
	SETUP_GLOBAL_FZF_VERSION="$version" SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'q\r' run_setup_target "$home_dir" "" --select > "$output" 2>&1

	assert_contains "$output" "$notice"
	assert_contains "$output" 'Enter skill numbers or collection names to leave out'
	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_not_exists "$fzf_arguments"
	assert_not_exists "$home_dir/.agents/skill-exclusions"
}

# Checks that the first supported fzf release opens the picker.
test_select_fzf_minimum_version_opens_picker() {
	assert_fzf_version_opens_picker '0.74.0' 'select-fzf-minimum'
}

# Checks that the release just below the minimum uses the numbered list.
test_select_fzf_below_minimum_uses_numbered_list() {
	assert_fzf_version_uses_numbered_list '0.73.9' 'select-fzf-below-minimum' 'fzf 0.73.9 cannot run this picker (it needs 0.74 or newer), so using the numbered list.'
}

# Checks that a newer major version opens the picker.
test_select_fzf_new_major_opens_picker() {
	assert_fzf_version_opens_picker '1.0.0' 'select-fzf-new-major'
}

# Checks that empty version output uses the numbered list.
test_select_fzf_empty_version_uses_numbered_list() {
	assert_fzf_version_uses_numbered_list '' 'select-fzf-empty-version' 'fzf version could not be read, so using the numbered list.'
}

# Ensures fzf is started with --multi and its chosen skills are saved.
test_select_fzf_updates_skill_exclusions() {
	create_test_repo_copy test_select_fzf_updates_skill_exclusions

	# Isolated home directory for the fzf selection run.
	local home_dir="$TEST_ROOT/select-fzf"
	# Output from the fzf selection run.
	local output="$TEST_ROOT/select-fzf.txt"
	# The empty temporary directory for the picker's Tab files, which must be empty again after setup.
	local temp_dir="$TEST_ROOT/select-fzf-temp"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/fzf-bin"
	# Arguments received by the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills displayed to the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"
	# Actions returned when Tab is pressed on a partly or fully ticked heading.
	local fzf_actions="$home_dir/fzf-actions.txt"
	# A skill fixture with a folded two-line description.
	local folded_skill="$ADDED_SKILL_GROUP/folded-picker"
	# A skill fixture with a quoted single-line description.
	local single_line_skill="$ADDED_SKILL_GROUP/single-picker"
	# A skill fixture with no description in its frontmatter.
	local no_description_skill="$ADDED_SKILL_GROUP/setup-global-no-description"

	create_fzf_stub "$fzf_dir"
	mkdir -p "$temp_dir"
	mkdir -p "$folded_skill"
	cat > "$folded_skill/SKILL.md" <<'EOF'
---
name: folded-picker
description: >
  Use this skill to inspect a folded description that spans
  two lines in the skill picker.
---
EOF
	mkdir -p "$single_line_skill"
	printf -- '---\nname: single-picker\ndescription: "Use this skill when reading a single-line description."\n---\n' > "$single_line_skill/SKILL.md"
	mkdir -p "$no_description_skill"
	printf -- '---\nname: setup-global-no-description\n---\n' > "$no_description_skill/SKILL.md"
	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	(
		# This test checks dimming, so clear an inherited NO_COLOR for this run.
		unset NO_COLOR
		# A narrow COLUMNS value proves fzf receives full rows and handles its own truncation.
		# The fzf capture files, chosen skills, command path, and terminal setting for this picker run.
		# PATH here is this test's own value; ShellCheck confuses it with the copy run_setup_target changes in its subshell.
		# shellcheck disable=SC2031
		COLUMNS=48 TMPDIR="$temp_dir" SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_ACTIONS="$fzf_actions" SETUP_GLOBAL_FZF_SELECTION=$'skill\taccessibility\t  accessibility  When editing HTML' SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"
	)

	assert_equals "$(ls -A "$temp_dir")" ''
	assert_contains "$fzf_arguments" '--ansi'
	assert_contains "$fzf_arguments" '--multi'
	assert_contains "$fzf_arguments" '--layout=reverse'
	assert_contains "$fzf_arguments" '--header'
	assert_contains "$fzf_arguments" 'Tab toggles a skill or collection, Enter confirms, Esc cancels. Ticked skills are installed.'
	assert_contains "$fzf_arguments" '--bind'
	assert_contains "$fzf_arguments" $'--delimiter=\t'
	assert_contains "$fzf_arguments" '--with-nth=3'
	assert_contains "$fzf_arguments" 'tab:transform('
	assert_contains "$fzf_arguments" '{} {+f}'
	assert_contains "$fzf_input" $'heading\taccessibility\taccessibility (2)'
	assert_contains "$fzf_actions" 'clear-query+wait+pos(2)+select+pos(3)+select+pos(1)'
	assert_contains "$fzf_actions" 'clear-query+wait+pos(2)+deselect+pos(3)+deselect+pos(1)'
	assert_contains "$fzf_input" $'skill\taccessibility\t  accessibility'
	assert_contains "$fzf_input" $'\033[2mWhen editing HTML'
	assert_contains "$fzf_input" $'\033[2mTo inspect a folded description that spans two lines in the skill picker.'
	assert_contains "$fzf_input" $'\033[2mWhen reading a single-line description.'
	if ! grep -Fxq $'skill\tsetup-global-no-description\t  setup-global-no-description' "$fzf_input"; then
		fail 'Expected a skill without a description to show its name alone'
	fi
	assert_not_contains "$fzf_input" 'Use this skill to inspect'
	assert_not_contains "$fzf_input" '…'
	assert_contains "$fzf_input" $'skill\twriting\t  writing'
	assert_picker_group_order "$fzf_input" fzf
	assert_fzf_start_selection "$fzf_arguments" "$fzf_input" 'writing'
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.claude/skills/accessibility"
	assert_not_exists "$home_dir/.agents/skills/writing"
	assert_contains "$home_dir/.agents/skill-exclusions" 'writing'
}

# Ensures a returned collection heading is never saved as a skill, so returning
# only a heading excludes every skill without failing on macOS Bash.
test_select_fzf_excludes_every_skill() {
	# Isolated home directory for a selection holding only a heading.
	local home_dir="$TEST_ROOT/select-fzf-empty"
	# Output from the fzf run that returns only a heading.
	local output="$TEST_ROOT/select-fzf-empty.txt"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/fzf-empty-bin"
	# Arguments received by the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills displayed to the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"

	create_fzf_stub "$fzf_dir"
	# The fzf capture files, chosen skills, command path, and terminal setting for this picker run.
	# PATH here is this test's own value; ShellCheck confuses it with the copy run_setup_target changes in its subshell.
	# shellcheck disable=SC2031
	SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_SELECTION=$'heading\taccessibility\taccessibility (2)' SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$fzf_arguments" '--multi'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'writing'
	assert_not_contains "$home_dir/.agents/skill-exclusions" 'heading'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
}

# Ensures fzf cancellation leaves the saved exclusions and links untouched.
test_select_fzf_cancel_preserves_existing_state() {
	# Isolated home directory for the cancelled fzf selection.
	local home_dir="$TEST_ROOT/select-fzf-cancel"
	# Output from the cancelled fzf selection.
	local output="$TEST_ROOT/select-fzf-cancel.txt"
	# The empty temporary directory for the picker's Tab files, which must be empty again after a cancel.
	local temp_dir="$TEST_ROOT/select-fzf-cancel-temp"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/fzf-cancel-bin"
	# Arguments received by the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills displayed to the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"

	create_fzf_stub "$fzf_dir"
	mkdir -p "$temp_dir"
	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	# The fzf capture files, cancelled picker status, command path, and terminal setting for this picker run.
	# PATH here is this test's own value; ShellCheck confuses it with the copy run_setup_target changes in its subshell.
	# shellcheck disable=SC2031
	TMPDIR="$temp_dir" SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_STATUS=1 SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_equals "$(ls -A "$temp_dir")" ''
	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures end-of-input cancels the numbered selector without changing state.
test_select_fallback_end_of_input_preserves_existing_state() {
	# Isolated home directory for the ended numbered selection.
	local home_dir="$TEST_ROOT/select-fallback-end-of-input"
	# Output from the ended numbered selection.
	local output="$TEST_ROOT/select-fallback-end-of-input.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	# The stub command path and terminal input for this picker run.
	SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'\004' run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures an invalid skill number fails without changing saved exclusions or links.
test_select_fallback_invalid_number_preserves_existing_state() {
	# Isolated home directory for invalid numbered input.
	local home_dir="$TEST_ROOT/select-fallback-invalid"
	# Output from the rejected numbered selection.
	local output="$TEST_ROOT/select-fallback-invalid.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

	run_setup_target "$home_dir" "" --exclude writing > /dev/null
	# The stub command path and terminal input for the invalid skill number.
	if SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'9999\r' run_setup_target "$home_dir" "" --select > "$output" 2>&1; then
		fail 'Expected an invalid skill number to fail'
	fi

	assert_contains "$output" 'Invalid skill number: 9999'
	assert_not_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.claude/skills/accessibility"
	assert_not_exists "$home_dir/.agents/skills/writing"
	assert_not_exists "$home_dir/.claude/skills/writing"
}

# Ensures --select rejects other skill options without changing saved exclusions or links.
test_select_rejects_other_skill_options_without_changes() {
	# Isolated home directory for rejected option combinations.
	local home_dir="$TEST_ROOT/select-with-skill-options"
	# Output from each rejected setup run.
	local output="$TEST_ROOT/select-with-skill-options.txt"
	# Skill option currently combined with --select.
	local option
	# Arguments for the current skill option.
	local -a option_args=()

	run_setup_target "$home_dir" "" --exclude writing > /dev/null
	for option in --exclude --include --include-all; do
		case "$option" in
			--exclude) option_args=(--exclude accessibility) ;;
			--include) option_args=(--include writing) ;;
			--include-all) option_args=(--include-all) ;;
		esac

		if run_setup_target "$home_dir" "" --select "${option_args[@]}" > "$output" 2>&1; then
			fail "Expected --select with $option to be rejected"
		fi

		assert_contains "$output" '--select cannot be combined with --exclude, --include, or --include-all.'
		assert_contains "$output" 'Usage:'
		assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
		assert_dir_link "$home_dir/.agents/skills/accessibility"
		assert_dir_link "$home_dir/.claude/skills/accessibility"
		assert_not_exists "$home_dir/.agents/skills/writing"
		assert_not_exists "$home_dir/.claude/skills/writing"
	done
}

# Ensures --select fails safely when standard input is not a terminal.
test_select_rejects_non_terminal_input() {
	# Isolated home directory for the rejected selection run.
	local home_dir="$TEST_ROOT/select-non-terminal"
	# Output from the rejected selection run.
	local output="$TEST_ROOT/select-non-terminal.txt"

	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	if run_setup_target "$home_dir" "" --select < /dev/null > "$output" 2>&1; then
		fail 'Expected --select without a terminal to be rejected'
	fi

	assert_contains "$output" '--select requires a terminal. Use --exclude or --include when standard input is not a terminal.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

test_skip_backup_environment_does_not_bypass_backup() {
	# The isolated home for the backup bypass check.
	local home_dir="$TEST_ROOT/skip-backup-environment"

	create_existing_config "$home_dir"
	# The legacy backup bypass setting that setup must ignore.
	SKIP_BACKUP=1 run_setup "$home_dir" > /dev/null

	assert_timestamped_backup "$home_dir"
}

test_failed_backup_preserves_existing_config() {
	# The isolated home for the failed backup check.
	local home_dir="$TEST_ROOT/backup-failure"
	# The output from the setup run with a failed backup.
	local output="$TEST_ROOT/backup-failure.txt"

	create_existing_config "$home_dir"
	# Makes the mv stub fail the config backup move.
	if SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE=1 run_setup "$home_dir" > "$output" 2>&1; then
		fail "Expected a failed backup to abort setup"
	fi

	assert_contains "$output" "backup move failed"
	assert_equals "$(cat "$home_dir/.codex/config.toml")" 'custom_setting = "keep"'
}

# Checks that setup keeps the user's HCOM options, adds the required folders that
# exist and are not listed yet, and changes nothing on a second run.
test_hcom_adds_missing_codex_folders() {
	# Isolated home with every required folder present.
	local home_dir="$TEST_ROOT/hcom-folders"
	# Setup status output.
	local output="$TEST_ROOT/hcom-folders.txt"
	# User options and an existing required folder, with uneven spacing that setup must keep.
	local existing_args="--model codex  --add-dir ~/Dev/Repositories/Configuration/zsh   --add-dir $REPO_DIR"
	# Original arguments followed by the missing required folders.
	local expected_args

	mkdir -p "$home_dir/.Trash" "$home_dir/Library/Caches/org.swift.swiftpm" "$home_dir/Library/org.swift.swiftpm"
	printf '%s\n' "$existing_args" > "$home_dir/hcom-codex-args"
	run_setup "$home_dir" > "$output"

	expected_args="$existing_args --add-dir $home_dir/.agents --add-dir $home_dir/.Trash --add-dir $home_dir/Library/Caches/org.swift.swiftpm --add-dir $home_dir/Library/org.swift.swiftpm"
	assert_equals "$(cat "$home_dir/hcom-codex-args")" "$expected_args"
	assert_equals "$(cat "$home_dir/hcom-writes")" 'write'
	assert_contains "$output" 'relaunch from a fresh terminal'

	run_setup "$home_dir" > "$output"

	assert_equals "$(cat "$home_dir/hcom-codex-args")" "$expected_args"
	assert_equals "$(cat "$home_dir/hcom-writes")" 'write'
	assert_not_contains "$output" 'relaunch from a fresh terminal'
}

# Checks that a tilde path counts as an existing home folder grant.
test_hcom_recognises_tilde_folder() {
	# Isolated home with an existing tilde-form grant.
	local home_dir="$TEST_ROOT/hcom-tilde"
	# HCOM argument using a literal tilde.
	local existing_args='--add-dir ~/.Trash'

	mkdir -p "$home_dir/.Trash"
	printf '%s\n' "$existing_args" > "$home_dir/hcom-codex-args"
	run_setup "$home_dir" > /dev/null

	assert_equals "$(cat "$home_dir/hcom-codex-args")" "$existing_args --add-dir $REPO_DIR --add-dir $home_dir/.agents"
}

# Checks that setup does not add folders absent from the current home.
test_hcom_skips_missing_folders() {
	# Isolated home without the Trash or SwiftPM folders.
	local home_dir="$TEST_ROOT/hcom-missing"

	run_setup "$home_dir" > /dev/null

	assert_equals "$(cat "$home_dir/hcom-codex-args")" "--add-dir $REPO_DIR --add-dir $home_dir/.agents"
}

# Checks that Codex setup reports a missing HCOM command without changing its settings.
test_hcom_absence_skips_codex_folders() {
	# Isolated home for a setup run without HCOM.
	local home_dir="$TEST_ROOT/hcom-absent"
	# Test commands excluding the HCOM stand-in.
	local bin_dir="$TEST_ROOT/no-hcom-bin"
	# Setup status output.
	local output="$TEST_ROOT/hcom-absent.txt"
	# Stub linked into the HCOM-free command directory.
	local command_path

	mkdir -p "$bin_dir"
	for command_path in "$TEST_ROOT/bin/"*; do
		if [ "$(basename "$command_path")" = hcom ]; then
			continue
		fi

		ln -s "$command_path" "$bin_dir/$(basename "$command_path")"
	done

	# The stub command path used for this isolated setup run.
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin" run_setup "$home_dir" > "$output"

	assert_contains "$output" '"label": "HCOM", "detail": "not installed"'
	assert_not_exists "$home_dir/hcom-codex-args"
}

# Checks that an HCOM read failure is reported while the rest of setup finishes.
test_hcom_read_failure_does_not_stop_setup() {
	# Isolated home with a failing HCOM read.
	local home_dir="$TEST_ROOT/hcom-read-failure"
	# Setup output containing the warning and completion row.
	local output="$TEST_ROOT/hcom-read-failure.txt"

	mkdir -p "$home_dir"
	: > "$home_dir/hcom-fail-read"
	run_setup "$home_dir" > "$output"

	assert_contains "$output" 'could not read Codex arguments'
	assert_contains "$output" '"label": "Done."'
	assert_not_exists "$home_dir/hcom-writes"
}

# Checks that an HCOM write failure is reported while the rest of setup finishes.
test_hcom_write_failure_does_not_stop_setup() {
	# Isolated home with a failing HCOM write.
	local home_dir="$TEST_ROOT/hcom-write-failure"
	# Setup output containing the warning and completion row.
	local output="$TEST_ROOT/hcom-write-failure.txt"

	mkdir -p "$home_dir"
	: > "$home_dir/hcom-fail-write"
	run_setup "$home_dir" > "$output"

	assert_contains "$output" 'could not update Codex arguments'
	assert_contains "$output" '"label": "Done."'
	assert_not_exists "$home_dir/hcom-codex-args"
}

# Runs the cases side by side, up to one per CPU core, then prints each result
# in call order with the logs of any failed case. Returns 1 if any case failed.
run_setup_cases() {
	# The cases, in the order that their results are reported.
	local -a cases=(
		test_help_hides_backup_bypass
		test_public_backup_bypass_is_rejected
		test_default_setup_skips_repository_refresh
		test_existing_doc_paths_is_preserved
		test_preflight_reports_missing_uv_without_changes
		test_preflight_reports_missing_checkout_without_changes
		test_preflight_accepts_installed_commands_without_installer
		test_preflight_checks_only_codex_commands
		test_status_skips_agent_tools_preflight
		test_missing_doc_paths_is_installed
		test_codex_installs_missing_doc_paths
		test_refresh_runs_repository_sync
		test_non_terminal_plan_requires_yes
		test_terminal_decline_preserves_home
		test_terminal_accept_creates_links
		test_nothing_to_change_exits_without_yes
		test_config_replacement_creates_timestamped_backup
		test_user_config_is_rewritten_once
		test_hook_file_is_replaced_with_managed_link
		test_claude_themes_are_linked_in_each_config_dir
		test_claude_setup_preserves_user_theme
		test_claude_theme_replacement_uses_backups_directory
		test_trash_wrapper_links_once_for_each_mode
		test_trash_wrapper_backs_up_existing_file
		test_trash_wrapper_preserves_symlinked_bin_directory
		test_stale_repo_link_has_no_backup_in_plan
		test_permission_profile_keeps_roots_and_drops_git_config_rule
		test_skills_are_installed_and_editable
		test_exclusions_persist_and_report
		test_new_skill_installs_after_exclusion
		test_claude_only_exclusion_creates_agents_directory
		test_unknown_skill_fails_without_changes
		test_removed_skill_can_be_included
		test_unmanaged_excluded_directory_survives
		test_unmanaged_included_skill_is_backed_up
		test_status_reports_an_installed_skill
		test_status_reports_a_missing_skill
		test_status_reports_an_excluded_skill
		test_status_reports_an_excluded_skill_with_a_lingering_link
		test_status_reports_conflicting_included_content
		test_status_reports_conflicting_excluded_content
		test_status_does_not_change_files
		test_status_requires_cli_style_without_changes
		test_status_rejects_skill_options_without_changes
		test_select_fallback_updates_skill_exclusions
		test_select_fallback_excludes_collection_and_skill
		test_select_fallback_empty_selection_includes_every_skill
		test_select_fallback_cancel_preserves_existing_state
		test_select_old_fzf_uses_numbered_list
		test_select_fzf_minimum_version_opens_picker
		test_select_fzf_below_minimum_uses_numbered_list
		test_select_fzf_new_major_opens_picker
		test_select_fzf_empty_version_uses_numbered_list
		test_select_fzf_updates_skill_exclusions
		test_select_fzf_excludes_every_skill
		test_select_fzf_cancel_preserves_existing_state
		test_select_fallback_end_of_input_preserves_existing_state
		test_select_fallback_invalid_number_preserves_existing_state
		test_select_rejects_other_skill_options_without_changes
		test_select_rejects_non_terminal_input
		test_skip_backup_environment_does_not_bypass_backup
		test_failed_backup_preserves_existing_config
		test_hcom_adds_missing_codex_folders
		test_hcom_recognises_tilde_folder
		test_hcom_skips_missing_folders
		test_hcom_absence_skips_codex_folders
		test_hcom_read_failure_does_not_stop_setup
		test_hcom_write_failure_does_not_stop_setup
	)
	# The process ID and result for each case, indexed in call order.
	local -a case_pids=() case_status=()
	# The number of cases allowed to run at once.
	local max_running_cases
	# The current case and the case whose slot must be freed.
	local index finished_index
	# Whether any case failed.
	local failed=0

	max_running_cases=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
	# Some sandboxes hide the CPU count. The limit only affects speed, so a
	# modest default keeps the suite runnable there.
	if ! [[ "$max_running_cases" =~ ^[1-9][0-9]*$ ]]; then
		max_running_cases=4
	fi
	if (( max_running_cases > ${#cases[@]} )); then
		max_running_cases=${#cases[@]}
	fi

	mkdir -p "$TEST_ROOT/case-logs"
	create_command_stubs "$TEST_ROOT/bin"
	# Start each case in its own process group so cleanup can stop everything
	# the case started.
	set -m
	for index in "${!cases[@]}"; do
		if (( index >= max_running_cases )); then
			finished_index=$((index - max_running_cases))
			if wait "${case_pids[finished_index]}"; then
				case_status[finished_index]=0
			else
				case_status[finished_index]=1
			fi
		fi

		# With process groups on, Bash no longer gives background cases empty
		# input, so a case that read the terminal would stop and hang the suite.
		("${cases[index]}") < /dev/null > "$TEST_ROOT/case-logs/${cases[index]}.log" 2>&1 &
		case_pids[index]=$!
	done

	for (( index = ${#cases[@]} - max_running_cases; index < ${#cases[@]}; index++ )); do
		if wait "${case_pids[index]}"; then
			case_status[index]=0
		else
			case_status[index]=1
		fi
	done

	for index in "${!cases[@]}"; do
		if [ "${case_status[index]}" -eq 0 ]; then
			printf '✓ %s\n' "${cases[index]}"
		else
			printf '✗ %s\n' "${cases[index]}"
			cat "$TEST_ROOT/case-logs/${cases[index]}.log"
			failed=1
		fi
	done

	if [ "$failed" -eq 0 ]; then
		printf '✓ setup-global backup tests passed\n'
	fi
	return "$failed"
}

run_setup_cases
