#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)
ADDED_SKILL_GROUP="$REPO_DIR/skills/setup-global-test-$(basename "$TEST_ROOT")"  # Temporary canonical skill group.
ADDED_SKILL_NAME="setup-global-test-skill-$(basename "$TEST_ROOT")"  # Temporary canonical skill name.
ADDED_SKILL_DIR="$ADDED_SKILL_GROUP/$ADDED_SKILL_NAME"  # Temporary canonical skill directory.

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

	cat > "$bin_dir/cli-style-adapter.sh" <<'EOF'
#!/bin/bash
# Stands in for the cli-style renderer and prints its input unchanged, trailing
# newlines included. Setup calls it once per output line, so it uses the read
# builtin rather than starting a cat process each time.
cli_style_render() {
	local text  # The whole input, read up to end of file.

	# read reports failure when it reaches end of file, which is expected here.
	IFS= read -r -d '' text || :
	printf '%s' "$text"
}
EOF

	chmod +x "$bin_dir/bash" "$bin_dir/cli-style" "$bin_dir/cp" "$bin_dir/mv" "$bin_dir/git" "$bin_dir/friction" "$bin_dir/cli-style-adapter.sh"
}

# Creates an fzf stand-in that records the arguments and skill list it
# receives, then prints a chosen set of skills.
#
# @param  {string}  bin_dir
#     Directory that receives the test-only fzf command.
create_fzf_stub() {
	local bin_dir="$1"  # Directory that receives the test-only fzf command.

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
	local arguments_path="$1"  # File containing the fzf command arguments.
	local input_path="$2"  # File containing the ordered canonical skill names passed to fzf.
	local excluded_skill="$3"  # Saved exclusion that fzf must leave unticked.
	local fzf_bind  # Start action sequence received by the fzf stand-in.
	local remaining_actions  # Start actions that have not yet matched an input skill.
	local expected_action  # Action expected for the current canonical skill.
	local actual_action  # Action generated for the current canonical skill.
	local skill_name  # Canonical skill currently being matched to a start action.

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
# @param  {string}  home_dir
#     Isolated home directory for the setup run.
# @param  {string}  target
#     Setup target option, or an empty string to exercise automatic targeting.
# @param  {string}  ...
#     Additional setup-global arguments.
run_setup_target() {
	local home_dir="$1"  # Isolated home directory for the setup run.
	local target="$2"  # Setup target option, or empty for automatic targeting.
	local bin_dir="$TEST_ROOT/bin"  # Directory containing test-only command stubs.
	local fail_backup_move="${SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE:-0}"  # Whether backup moves should fail.
	local setup_path="${SETUP_GLOBAL_TEST_PATH:-$bin_dir:$PATH}"  # Command path used by the setup process.
	local -a setup_command=("bash" "$REPO_DIR/scripts/setup-global.sh")  # Setup command, optionally wrapped in a terminal.
	shift 2

	mkdir -p "$home_dir"

	if [ "${SETUP_GLOBAL_TEST_TERMINAL:-false}" = true ]; then
		setup_command=("script" "-q" "/dev/null" "perl" "-e" "alarm 20; exec @ARGV" "bash" "$REPO_DIR/scripts/setup-global.sh")
	fi

	# An empty target expands to nothing so setup-global picks the target itself.
	HOME="$home_dir" \
	PATH="$setup_path" \
	CLI_STYLE_BIN="$bin_dir/cli-style" \
	SETUP_GLOBAL_INSTALLER="$REPO_DIR/scripts/install-cli-style.sh" \
	SETUP_GLOBAL_SYNC="$REPO_DIR/scripts/sync.sh" \
	SETUP_GLOBAL_VALIDATE="$REPO_DIR/scripts/validate.sh" \
	SETUP_GLOBAL_CALL_LOG="$home_dir/setup-global-calls.log" \
	SETUP_GLOBAL_TEST_ADAPTER="$bin_dir/cli-style-adapter.sh" \
	SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE="$fail_backup_move" \
	"${setup_command[@]}" ${target:+"$target"} --skip-external "$@"
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

test_refresh_runs_repository_sync() {
	local home_dir="$TEST_ROOT/refresh"
	local calls="$home_dir/setup-global-calls.log"

	create_existing_config "$home_dir"
	run_setup "$home_dir" --refresh > /dev/null

	assert_contains "$calls" "$REPO_DIR/scripts/sync.sh"
	assert_contains "$calls" "$REPO_DIR/scripts/validate.sh"
}

test_config_replacement_creates_timestamped_backup() {
	local home_dir="$TEST_ROOT/backup"

	create_existing_config "$home_dir"
	run_setup "$home_dir" > /dev/null

	assert_timestamped_backup "$home_dir"
	assert_contains "$home_dir/.codex/config.toml" 'approval_policy = "never"'
	assert_contains "$home_dir/.codex/config.toml" 'default_permissions = "project-edit"'
	assert_contains "$home_dir/.codex/config.toml" '[mcp_servers.codebase-memory-mcp]'
	assert_contains "$home_dir/.codex/config.toml" '[mcp_servers.serena]'
	assert_equals "$(grep -c '^default_tools_approval_mode = \"approve\"$' "$home_dir/.codex/config.toml")" "2"
	assert_contains "$home_dir/.codex/config.toml" '[features]'
	assert_contains "$home_dir/.codex/config.toml" 'hooks = true'
	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit]'
	assert_contains "$home_dir/.codex/config.toml" 'extends = ":workspace"'
	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit.workspace_roots]'
	assert_contains "$home_dir/.codex/config.toml" '"'"$home_dir"'/Dev/Configuration/Agents" = true'
	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit.filesystem.":workspace_roots"]'
	assert_contains "$home_dir/.codex/config.toml" '".git/config" = "write"'
	assert_contains "$home_dir/.codex/config.toml" '".git/config.lock" = "write"'
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

test_permission_profile_preserves_workspace_roots() {
	local home_dir="$TEST_ROOT/permission-profile"

	create_existing_config "$home_dir"
	printf '\n[sandbox_workspace_write]\nnetwork_access = false\nexclude_slash_tmp = true\nwritable_roots = ["/tmp/keep"]\n' >> "$home_dir/.codex/config.toml"
	printf '\n[permissions.project-edit.workspace_roots]\n"/tmp/already-added" = true\n' >> "$home_dir/.codex/config.toml"
	run_setup "$home_dir" > /dev/null

	assert_contains "$home_dir/.codex/config.toml" '[permissions.project-edit.network]'
	assert_contains "$home_dir/.codex/config.toml" 'enabled = true'
	assert_contains "$home_dir/.codex/config.toml" '"/tmp/keep" = true'
	assert_contains "$home_dir/.codex/config.toml" '"/tmp/already-added" = true'
	assert_not_contains "$home_dir/.codex/config.toml" 'sandbox_mode'
	assert_not_contains "$home_dir/.codex/config.toml" '[sandbox_workspace_write]'
}

test_skills_are_installed_and_editable() {
	local home_dir="$TEST_ROOT/skills-installed"  # Isolated home directory for the setup run.
	local marker_name="setup-global-test-marker-$(basename "$TEST_ROOT")"  # Temporary source marker name.
	local source_marker="$ADDED_SKILL_DIR/$marker_name"  # Marker path in the temporary canonical skill.

	create_added_skill
	run_setup "$home_dir" > /dev/null

	assert_dir_link "$home_dir/.agents/skills/$ADDED_SKILL_NAME"
	printf 'visible through the installed link\n' > "$home_dir/.agents/skills/$ADDED_SKILL_NAME/$marker_name"
	assert_contains "$source_marker" 'visible through the installed link'
	trash "$ADDED_SKILL_GROUP"
}

test_exclusions_persist_and_report() {
	local home_dir="$TEST_ROOT/skill-exclusions"  # Isolated home directory for the setup run.
	local output="$TEST_ROOT/skill-exclusions.txt"  # Output from the initial exclusion run.
	local rerun_output="$TEST_ROOT/skill-exclusions-rerun.txt"  # Output from the persisted exclusion run.
	local include_output="$TEST_ROOT/skill-exclusions-include.txt"  # Output after including one skill.
	local include_all_output="$TEST_ROOT/skill-exclusions-include-all.txt"  # Output after including all skills.
	local excluded_message='Excluded: accessibility, accessibility-audit (from ~/.agents/skill-exclusions; run with --include-all to restore)'  # Expected exclusion status line.

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
	local home_dir="$TEST_ROOT/new-skill"  # Isolated home directory for the setup run.

	run_setup "$home_dir" --exclude accessibility > /dev/null
	create_added_skill
	run_setup "$home_dir" > /dev/null

	assert_dir_link "$home_dir/.agents/skills/$ADDED_SKILL_NAME"
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	trash "$ADDED_SKILL_GROUP"
}

test_claude_only_exclusion_creates_agents_directory() {
	local home_dir="$TEST_ROOT/claude-only-exclusion"  # Isolated home directory for the setup run.
	local output="$TEST_ROOT/claude-only-exclusion.txt"  # Output from the Claude-only exclusion run.

	run_setup_target "$home_dir" "--claude" --exclude accessibility > "$output"

	assert_dir "$home_dir/.agents"
	assert_file "$home_dir/.agents/skill-exclusions"
	assert_not_exists "$home_dir/.codex"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
	assert_contains "$output" 'Excluded: accessibility (from ~/.agents/skill-exclusions; run with --include-all to restore)'
}

test_unknown_skill_fails_without_changes() {
	local home_dir="$TEST_ROOT/unknown-skill"  # Isolated home directory for the setup run.
	local output="$TEST_ROOT/unknown-skill.txt"  # Output from the rejected setup run.

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
	local home_dir="$TEST_ROOT/removed-skill"  # Isolated home directory for the setup run.
	local removed_skill='removed-setup-global-skill'  # Saved exclusion with no canonical skill folder.

	mkdir -p "$home_dir/.agents"
	printf '%s\n' "$removed_skill" > "$home_dir/.agents/skill-exclusions"
	run_setup "$home_dir" --include-all --include "$removed_skill" > /dev/null

	assert_not_exists "$home_dir/.agents/skill-exclusions"
}

test_unmanaged_excluded_directory_survives() {
	local home_dir="$TEST_ROOT/unmanaged-excluded"  # Isolated home directory for the setup run.
	local marker="$home_dir/.agents/skills/accessibility/keep.txt"  # Content that an exclusion must preserve.

	run_setup "$home_dir" --exclude accessibility > /dev/null
	mkdir -p "$(dirname "$marker")"
	printf 'keep this directory\n' > "$marker"
	run_setup "$home_dir" > /dev/null

	assert_file "$marker"
}

test_unmanaged_included_skill_is_backed_up() {
	local home_dir="$TEST_ROOT/unmanaged-included"  # Isolated home directory for the setup run.
	local output="$TEST_ROOT/unmanaged-included.txt"  # Output from the setup run.
	local backups  # Timestamped backup directories created for the unmanaged skill path.

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
	local home_dir="$TEST_ROOT/status-installed"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-installed.txt"  # Output from the installed-skill report.

	mkdir -p "$home_dir/.claude/skills"
	ln -s "$REPO_DIR/skills/accessibility/accessibility" "$home_dir/.claude/skills/accessibility"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'installed accessibility'
}

test_status_reports_a_missing_skill() {
	local home_dir="$TEST_ROOT/status-missing"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-missing.txt"  # Output from the missing-skill report.

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'missing bash'
}

test_status_reports_an_excluded_skill() {
	local home_dir="$TEST_ROOT/status-excluded"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-excluded.txt"  # Output from the excluded-skill report.

	mkdir -p "$home_dir/.agents"
	printf 'accessibility-audit\n' > "$home_dir/.agents/skill-exclusions"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'excluded accessibility-audit'
}

test_status_reports_an_excluded_skill_with_a_lingering_link() {
	local home_dir="$TEST_ROOT/status-lingering-link"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-lingering-link.txt"  # Output from the lingering-link report.
	local lingering_link="$home_dir/.claude/skills/writing"  # Excluded repo-owned link that the report must not remove.

	mkdir -p "$home_dir/.agents" "$(dirname "$lingering_link")"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	ln -s "$REPO_DIR/skills/writing/writing" "$lingering_link"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'excluded writing'
	assert_contains "$output" 'link still present; run: scripts/setup-global.sh --claude --exclude writing'
	assert_equals "$(readlink "$lingering_link")" "$REPO_DIR/skills/writing/writing"
}

test_status_reports_conflicting_included_content() {
	local home_dir="$TEST_ROOT/status-included-conflict"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-included-conflict.txt"  # Output from the included-conflict report.
	local conflict_file="$home_dir/.claude/skills/code-style/keep.txt"  # Unmanaged included content that must remain conflicting.

	mkdir -p "$(dirname "$conflict_file")"
	printf 'keep this content\n' > "$conflict_file"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'conflicting code-style'
	assert_contains "$output" 'run: scripts/setup-global.sh --claude --include code-style'
	assert_equals "$(cat "$conflict_file")" 'keep this content'
}

test_status_reports_conflicting_excluded_content() {
	local home_dir="$TEST_ROOT/status-excluded-conflict"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-excluded-conflict.txt"  # Output from the excluded-conflict report.
	local conflict_file="$home_dir/.claude/skills/code-style/keep.txt"  # Unmanaged excluded content that must remain conflicting.

	mkdir -p "$home_dir/.agents" "$(dirname "$conflict_file")"
	printf 'code-style\n' > "$home_dir/.agents/skill-exclusions"
	printf 'keep this content\n' > "$conflict_file"

	run_setup_target "$home_dir" "--claude" --status > "$output"

	assert_contains "$output" 'conflicting code-style'
	assert_contains "$output" 'run: trash ~/.claude/skills/code-style'
	assert_equals "$(cat "$conflict_file")" 'keep this content'
}

test_status_does_not_change_files() {
	local home_dir="$TEST_ROOT/status-read-only"  # Isolated home directory for the status report.
	local output="$TEST_ROOT/status-read-only.txt"  # Output from the read-only status report.
	local installed_link="$home_dir/.claude/skills/accessibility"  # Repo-owned link that must remain installed.
	local excluded_skill="$home_dir/.agents/skills/code-style/keep.txt"  # Unmanaged excluded content that must remain conflicting.

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
	local home_dir="$TEST_ROOT/status-with-skill-options"  # Isolated home directory for the rejected status run.
	local output="$TEST_ROOT/status-with-skill-options.txt"  # Output from the rejected status run.

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
	local home_dir="$TEST_ROOT/select-fallback"  # Isolated home directory for the numbered selection run.
	local output="$TEST_ROOT/select-fallback.txt"  # Output from the numbered selection run.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"  # Command path without fzf.

	perl -e 'select undef, undef, undef, 0.1; print "1 2\n"' | SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

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
	local home_dir="$TEST_ROOT/select-fallback-empty"  # Isolated home directory for an empty numbered selection.
	local output="$TEST_ROOT/select-fallback-empty.txt"  # Output from the empty numbered selection run.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"  # Command path without fzf.

	perl -e 'select undef, undef, undef, 0.1; print "\n"' | SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_not_exists "$home_dir/.agents/skill-exclusions"
	assert_dir_link "$home_dir/.agents/skills/accessibility"
	assert_dir_link "$home_dir/.claude/skills/accessibility"
}

# Ensures cancelling the numbered selector preserves the saved exclusions.
test_select_fallback_cancel_preserves_existing_state() {
	local home_dir="$TEST_ROOT/select-fallback-cancel"  # Isolated home directory for the cancelled numbered selection.
	local output="$TEST_ROOT/select-fallback-cancel.txt"  # Output from the cancelled numbered selection.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"  # Command path without fzf.

	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	perl -e 'select undef, undef, undef, 0.1; print "q\n"' | SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures fzf is started with --multi and its chosen skills are saved.
test_select_fzf_updates_skill_exclusions() {
	local home_dir="$TEST_ROOT/select-fzf"  # Isolated home directory for the fzf selection run.
	local output="$TEST_ROOT/select-fzf.txt"  # Output from the fzf selection run.
	local fzf_dir="$TEST_ROOT/fzf-bin"  # Directory containing the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"  # Arguments received by the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"  # Skills displayed to the fzf stand-in.

	create_fzf_stub "$fzf_dir"
	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	perl -e 'select undef, undef, undef, 0.1; print "\n"' | SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_SELECTION='accessibility' SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

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
	local home_dir="$TEST_ROOT/select-fzf-empty"  # Isolated home directory for an empty fzf selection.
	local output="$TEST_ROOT/select-fzf-empty.txt"  # Output from the empty fzf selection run.
	local fzf_dir="$TEST_ROOT/fzf-empty-bin"  # Directory containing the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"  # Arguments received by the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"  # Skills displayed to the fzf stand-in.

	create_fzf_stub "$fzf_dir"
	perl -e 'select undef, undef, undef, 0.1; print "\n"' | SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_SELECTION='' SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$fzf_arguments" '--multi'
	assert_contains "$home_dir/.agents/skill-exclusions" 'accessibility'
	assert_contains "$home_dir/.agents/skill-exclusions" 'writing'
	assert_not_exists "$home_dir/.agents/skills/accessibility"
	assert_not_exists "$home_dir/.claude/skills/accessibility"
}

# Ensures fzf cancellation leaves the saved exclusions and links untouched.
test_select_fzf_cancel_preserves_existing_state() {
	local home_dir="$TEST_ROOT/select-fzf-cancel"  # Isolated home directory for the cancelled fzf selection.
	local output="$TEST_ROOT/select-fzf-cancel.txt"  # Output from the cancelled fzf selection.
	local fzf_dir="$TEST_ROOT/fzf-cancel-bin"  # Directory containing the fzf stand-in.
	local fzf_arguments="$home_dir/fzf-arguments.txt"  # Arguments received by the fzf stand-in.
	local fzf_input="$home_dir/fzf-input.txt"  # Skills displayed to the fzf stand-in.

	create_fzf_stub "$fzf_dir"
	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	perl -e 'select undef, undef, undef, 0.1; print "\n"' | SETUP_GLOBAL_FZF_ARGUMENTS="$fzf_arguments" SETUP_GLOBAL_FZF_INPUT="$fzf_input" SETUP_GLOBAL_FZF_STATUS=1 SETUP_GLOBAL_TEST_PATH="$fzf_dir:$TEST_ROOT/bin:$PATH" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures end-of-input cancels the numbered selector without changing state.
test_select_fallback_end_of_input_preserves_existing_state() {
	local home_dir="$TEST_ROOT/select-fallback-end-of-input"  # Isolated home directory for the ended numbered selection.
	local output="$TEST_ROOT/select-fallback-end-of-input.txt"  # Output from the ended numbered selection.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"  # Command path without fzf.

	mkdir -p "$home_dir/.agents"
	printf 'writing\n' > "$home_dir/.agents/skill-exclusions"
	perl -e 'select undef, undef, undef, 0.1' | SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output"

	assert_contains "$output" 'Skill selection cancelled. Nothing changed.'
	assert_equals "$(cat "$home_dir/.agents/skill-exclusions")" 'writing'
	assert_not_exists "$home_dir/.claude"
	assert_not_exists "$home_dir/.codex"
}

# Ensures an invalid skill number fails without changing saved exclusions or links.
test_select_fallback_invalid_number_preserves_existing_state() {
	local home_dir="$TEST_ROOT/select-fallback-invalid"  # Isolated home directory for invalid numbered input.
	local output="$TEST_ROOT/select-fallback-invalid.txt"  # Output from the rejected numbered selection.
	local fallback_path="$TEST_ROOT/bin:/usr/bin:/bin"  # Command path without fzf.

	run_setup_target "$home_dir" "" --exclude writing > /dev/null
	if perl -e 'select undef, undef, undef, 0.1; print "9999\n"' | SETUP_GLOBAL_TEST_PATH="$fallback_path" SETUP_GLOBAL_TEST_TERMINAL=true run_setup_target "$home_dir" "" --select > "$output" 2>&1; then
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
	local home_dir="$TEST_ROOT/select-with-skill-options"  # Isolated home directory for rejected option combinations.
	local output="$TEST_ROOT/select-with-skill-options.txt"  # Output from each rejected setup run.
	local option  # Skill option currently combined with --select.
	local -a option_args=()  # Arguments for the current skill option.

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
	local home_dir="$TEST_ROOT/select-non-terminal"  # Isolated home directory for the rejected selection run.
	local output="$TEST_ROOT/select-non-terminal.txt"  # Output from the rejected selection run.

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

create_command_stubs "$TEST_ROOT/bin"

test_help_hides_backup_bypass
test_public_backup_bypass_is_rejected
test_default_setup_skips_repository_refresh
test_refresh_runs_repository_sync
test_config_replacement_creates_timestamped_backup
test_hook_file_is_replaced_with_managed_link
test_permission_profile_preserves_workspace_roots
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

printf '✓ setup-global backup tests passed\n'
