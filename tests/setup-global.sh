#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)
# Temporary canonical skill group.
ADDED_SKILL_GROUP="$REPO_DIR/skills/setup-global-test-$(basename "$TEST_ROOT")"
# Temporary canonical skill name.
ADDED_SKILL_NAME="setup-global-test-skill-$(basename "$TEST_ROOT")"
# Temporary canonical skill directory.
ADDED_SKILL_DIR="$ADDED_SKILL_GROUP/$ADDED_SKILL_NAME"

# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

# Removes the temporary canonical skill and isolated test home.
cleanup_setup_global_test() {
	if [ -d "$ADDED_SKILL_GROUP" ]; then
		trash "$ADDED_SKILL_GROUP"
	fi
	cleanup
}

trap cleanup_setup_global_test EXIT

# Creates command stubs so setup-global can run against an isolated home
# without installing dependencies, synchronising output, or changing Git.
#
# @param  {string}  bin_dir
#     Directory that receives the test commands.
create_command_stubs() {
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

# Creates an fzf stand-in that records the arguments and skill list it
# receives, then prints a chosen set of skills.
#
# @param  {string}  bin_dir
#     Directory that receives the test-only fzf command.
create_fzf_stub() {
	# Directory that receives the test-only fzf command.
	local bin_dir="$1"

	mkdir -p "$bin_dir"

	cat > "$bin_dir/fzf" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$SETUP_GLOBAL_FZF_ARGUMENTS"
cat > "$SETUP_GLOBAL_FZF_INPUT"
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
#     File containing the ordered canonical skill names passed to fzf.
# @param  {string}  excluded_skill
#     Saved exclusion that fzf must leave unticked.
assert_fzf_start_selection() {
	# File containing the fzf command arguments.
	local arguments_path="$1"
	# File containing the ordered canonical skill names passed to fzf.
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

	fzf_bind=$(grep '^load:' "$arguments_path")
	remaining_actions="${fzf_bind#load:}"

	while IFS= read -r skill_name; do
		if [ "$skill_name" = "$excluded_skill" ]; then
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

# Creates a Codex configuration that setup-global must replace.
#
# @param  {string}  home_dir
#     Isolated home directory for one setup run.
create_existing_config() {
	local home_dir="$1"

	mkdir -p "$home_dir/.codex"
	printf 'custom_setting = "keep"\n' > "$home_dir/.codex/config.toml"
}

# Runs the global setup in a temporary home with test-only command stubs.
#
# @param  {string}  home_dir
#     Isolated home directory for the setup run.
# @param  {string}  ...
#     Additional setup-global arguments.
run_setup() {
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

	mkdir -p "$home_dir"

	(
		export HOME="$home_dir"
		export PATH="$setup_path"
		export CLI_STYLE_BIN="$bin_dir/cli-style"
		export SETUP_GLOBAL_INSTALLER="$REPO_DIR/scripts/install-cli-style.sh"
		export SETUP_GLOBAL_SYNC="$REPO_DIR/scripts/sync.sh"
		export SETUP_GLOBAL_VALIDATE="$REPO_DIR/scripts/validate.sh"
		export SETUP_GLOBAL_CALL_LOG="$home_dir/setup-global-calls.log"
		export SETUP_GLOBAL_UV_LOG="$home_dir/uv-calls.log"
		export SETUP_GLOBAL_TEST_ADAPTER="$bin_dir/cli-style-adapter.sh"
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
		-exact "Enter the numbers to leave out, separated by spaces (or q to cancel): " {}
		timeout { puts stderr "Picker prompt did not appear within 20 seconds"; exit 1 }
		eof { puts stderr "Picker prompt did not appear before setup exited"; exit 1 }
	}
	send -- $env(SETUP_GLOBAL_TEST_TERMINAL_INPUT)
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
	local home_dir="$1"
	local backups=("$home_dir/.codex/config.toml.bak."*)

	assert_file "${backups[0]}"
	assert_equals "$(cat "${backups[0]}")" 'custom_setting = "keep"'
}

test_help_hides_backup_bypass() {
	local output="$TEST_ROOT/help.txt"

	/bin/bash "$REPO_DIR/scripts/setup-global.sh" --help > "$output"

	assert_not_contains "$output" "--no-backup"
}

test_public_backup_bypass_is_rejected() {
	local home_dir="$TEST_ROOT/no-backup"
	local output="$TEST_ROOT/no-backup.txt"

	create_existing_config "$home_dir"
	if run_setup "$home_dir" --no-backup > "$output" 2>&1; then
		fail "Expected --no-backup to be rejected"
	fi

	assert_contains "$output" "Usage:"
	assert_equals "$(cat "$home_dir/.codex/config.toml")" 'custom_setting = "keep"'
}

test_default_setup_skips_repository_refresh() {
	local home_dir="$TEST_ROOT/default-setup"
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

# Checks that global setup installs a missing doc-paths command once for both targets.
test_missing_doc_paths_is_installed() {
	# Isolated home for the setup run.
	local home_dir="$TEST_ROOT/install-doc-paths"
	# Isolated command directory without doc-paths.
	local bin_dir="$TEST_ROOT/install-bin"

	/bin/cp -R "$TEST_ROOT/bin" "$bin_dir"
	mv "$bin_dir/doc-paths" "$bin_dir/doc-paths-disabled"
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
	SETUP_GLOBAL_TEST_PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" run_setup_target "$home_dir" "--codex" > /dev/null

	assert_equals "$(wc -l < "$home_dir/uv-calls.log" | tr -d ' ')" '1'
	assert_file "$bin_dir/doc-paths"
}

# Refresh runs the repository sync, which validates the output itself, so setup
# does not run validation a second time.
test_refresh_runs_repository_sync() {
	local home_dir="$TEST_ROOT/refresh"
	local calls="$home_dir/setup-global-calls.log"

	create_existing_config "$home_dir"
	run_setup "$home_dir" --refresh > /dev/null

	assert_contains "$calls" "$REPO_DIR/scripts/sync.sh"
	assert_not_contains "$calls" "$REPO_DIR/scripts/validate.sh"
}

# Setup removes the Serena server that older setups added to the Codex config.
test_setup_removes_retired_serena_server() {
	local home_dir="$TEST_ROOT/serena-removal"

	mkdir -p "$home_dir/.codex"
	printf '[mcp_servers.serena]\ncommand = "serena"\n' > "$home_dir/.codex/config.toml"
	run_setup "$home_dir" > /dev/null

	assert_not_contains "$home_dir/.codex/config.toml" '[mcp_servers.serena]'
	assert_contains "$home_dir/.codex/config.toml" '[mcp_servers.codebase-memory-mcp]'
}

# Setup backs up an existing Codex config with a timestamp before replacing it
# with the managed settings.
test_config_replacement_creates_timestamped_backup() {
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

test_hook_file_is_replaced_with_managed_link() {
	local home_dir="$TEST_ROOT/legacy-hooks"
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
		assert_equals "$(grep -Fc '"label": "Trash wrapper"' "$output")" '1'
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

	mkdir -p "$home_dir/.local" "$bin_dir"
	ln -s "$bin_dir" "$bin_link"

	run_setup_target "$home_dir" "--both" > /dev/null

	assert_dir_link "$bin_link"
	assert_equals "$(readlink "$bin_link")" "$bin_dir"
	backups=("$home_dir/.local/bin.bak."*)
	assert_not_exists "${backups[0]}"
	assert_link "$bin_dir/trash"
	assert_equals "$(readlink "$bin_dir/trash")" "$REPO_DIR/src/bin/trash"
}

# Setup keeps the workspace roots a user already has when it rewrites the Codex
# permission profile, and removes the .git/config write rule that older setups
# added, because that rule stops Codex running any command in a linked worktree.
test_permission_profile_keeps_roots_and_drops_git_config_rule() {
	local home_dir="$TEST_ROOT/permission-profile"

	create_existing_config "$home_dir"
	printf '\n[sandbox_workspace_write]\nnetwork_access = false\nexclude_slash_tmp = true\nwritable_roots = ["/tmp/keep"]\n' >> "$home_dir/.codex/config.toml"
	printf '\n[permissions.project-edit.workspace_roots]\n"/tmp/already-added" = true\n' >> "$home_dir/.codex/config.toml"
	printf '\n[permissions.project-edit.filesystem.":workspace_roots"]\n".git/config" = "write"\n".git/config.lock" = "write"\n' >> "$home_dir/.codex/config.toml"
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
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/skills-installed"
	# Temporary source marker name.
	local marker_name="setup-global-test-marker-$(basename "$TEST_ROOT")"
	# Marker path in the temporary canonical skill.
	local source_marker="$ADDED_SKILL_DIR/$marker_name"

	create_added_skill
	run_setup "$home_dir" > /dev/null

	assert_dir_link "$home_dir/.agents/skills/$ADDED_SKILL_NAME"
	printf 'visible through the installed link\n' > "$home_dir/.agents/skills/$ADDED_SKILL_NAME/$marker_name"
	assert_contains "$source_marker" 'visible through the installed link'
	trash "$ADDED_SKILL_GROUP"
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
	# Isolated home directory for the setup run.
	local home_dir="$TEST_ROOT/new-skill"

	run_setup "$home_dir" --exclude accessibility > /dev/null
	create_added_skill
	run_setup "$home_dir" > /dev/null

	assert_dir_link "$home_dir/.agents/skills/$ADDED_SKILL_NAME"
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	trash "$ADDED_SKILL_GROUP"
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

	mkdir -p "$home_dir/.agents/skills" "$home_dir/.claude/skills" "$(dirname "$excluded_skill")"
	printf 'code-style\n' > "$home_dir/.agents/skill-exclusions"
	printf 'keep this content\n' > "$excluded_skill"
	ln -s "$REPO_DIR/skills/accessibility/accessibility" "$installed_link"

	run_setup_target "$home_dir" "" --status > "$output"

	assert_contains "$output" 'Claude skills'
	assert_contains "$output" 'Codex skills'
	assert_equals "$(readlink "$installed_link")" "$REPO_DIR/skills/accessibility/accessibility"
	assert_equals "$(cat "$excluded_skill")" 'keep this content'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'code-style'
	assert_not_exists "$home_dir/.codex"
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

	SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'1 2\r' run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" '[x] 1. accessibility'
	assert_contains "$output" '[x] 2. accessibility-audit'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility-audit'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
	assert_dir_link "$home_dir/.agents/skills/bash"
	assert_dir_link "$home_dir/.claude/skills/bash"
}

# Ensures an empty numbered selection keeps every skill without failing on macOS Bash.
test_select_fallback_empty_selection_includes_every_skill() {
	# Isolated home directory for an empty numbered selection.
	local home_dir="$TEST_ROOT/select-fallback-empty"
	# Output from the empty numbered selection run.
	local output="$TEST_ROOT/select-fallback-empty.txt"
	# Command path without fzf.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"

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
	SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true SETUP_GLOBAL_TEST_TERMINAL_INPUT=$'q\r' run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures fzf is started with --multi and its chosen skills are saved.
test_select_fzf_updates_skill_exclusions() {
	# Isolated home directory for the fzf selection run.
	local home_dir="$TEST_ROOT/select-fzf"
	# Output from the fzf selection run.
	local output="$TEST_ROOT/select-fzf.txt"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/fzf-bin"
	# Arguments received by the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills displayed to the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"

	create_fzf_stub "$fzf_dir"
	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_SELECTION='accessibility' SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$fzf_arguments" '--multi'
	assert_contains "$fzf_arguments" '--layout=reverse'
	assert_contains "$fzf_arguments" '--header'
	assert_contains "$fzf_arguments" 'Tab toggles a skill, Enter confirms, Esc cancels. Ticked skills are installed.'
	assert_contains "$fzf_arguments" '--bind'
	assert_contains "$fzf_input" 'accessibility'
	assert_contains "$fzf_input" 'writing'
	assert_fzf_start_selection "$fzf_arguments" "$fzf_input" 'writing'
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.claude/skills/accessibility"
	assert_not_exists "$home_dir/.agents/skills/writing"
	assert_contains "$home_dir/.agents/skill-exclusions" 'writing'
}

# Ensures an empty fzf selection excludes every skill without failing on macOS Bash.
test_select_fzf_excludes_every_skill() {
	# Isolated home directory for an empty fzf selection.
	local home_dir="$TEST_ROOT/select-fzf-empty"
	# Output from the empty fzf selection run.
	local output="$TEST_ROOT/select-fzf-empty.txt"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/fzf-empty-bin"
	# Arguments received by the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills displayed to the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"

	create_fzf_stub "$fzf_dir"
	SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_SELECTION='' SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$fzf_arguments" '--multi'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'writing'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
}

# Ensures fzf cancellation leaves the saved exclusions and links untouched.
test_select_fzf_cancel_preserves_existing_state() {
	# Isolated home directory for the cancelled fzf selection.
	local home_dir="$TEST_ROOT/select-fzf-cancel"
	# Output from the cancelled fzf selection.
	local output="$TEST_ROOT/select-fzf-cancel.txt"
	# Directory containing the fzf stand-in.
	local fzf_dir="$TEST_ROOT/fzf-cancel-bin"
	# Arguments received by the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"
	# Skills displayed to the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"

	create_fzf_stub "$fzf_dir"
	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_STATUS=1 SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

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
	local home_dir="$TEST_ROOT/skip-backup-environment"

	create_existing_config "$home_dir"
	SKIP_BACKUP=1 run_setup "$home_dir" > /dev/null

	assert_timestamped_backup "$home_dir"
}

test_failed_backup_preserves_existing_config() {
	local home_dir="$TEST_ROOT/backup-failure"
	local output="$TEST_ROOT/backup-failure.txt"

	create_existing_config "$home_dir"
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

create_command_stubs "$TEST_ROOT/bin"

test_help_hides_backup_bypass
test_public_backup_bypass_is_rejected
test_default_setup_skips_repository_refresh
test_existing_doc_paths_is_preserved
test_missing_doc_paths_is_installed
test_codex_installs_missing_doc_paths
test_refresh_runs_repository_sync
test_config_replacement_creates_timestamped_backup
test_setup_removes_retired_serena_server
test_hook_file_is_replaced_with_managed_link
test_claude_themes_are_linked_in_each_config_dir
test_claude_setup_preserves_user_theme
test_claude_theme_replacement_uses_backups_directory
test_trash_wrapper_links_once_for_each_mode
test_trash_wrapper_backs_up_existing_file
test_trash_wrapper_preserves_symlinked_bin_directory
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
test_status_rejects_skill_options_without_changes
test_select_fallback_updates_skill_exclusions
test_select_fallback_empty_selection_includes_every_skill
test_select_fallback_cancel_preserves_existing_state
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

printf '✓ setup-global backup tests passed\n'
