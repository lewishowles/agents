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
cli_style_render() {
	cat
}
EOF

	chmod +x "$bin_dir/bash" "$bin_dir/cli-style" "$bin_dir/cp" "$bin_dir/mv" "$bin_dir/git" "$bin_dir/friction" "$bin_dir/cli-style-adapter.sh"
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
	shift 2

	mkdir -p "$home_dir"

	# An empty target expands to nothing so setup-global picks the target itself.
	HOME="$home_dir" \
	PATH="$bin_dir:$PATH" \
	CLI_STYLE_BIN="$bin_dir/cli-style" \
	SETUP_GLOBAL_INSTALLER="$REPO_DIR/scripts/install-cli-style.sh" \
	SETUP_GLOBAL_SYNC="$REPO_DIR/scripts/sync.sh" \
	SETUP_GLOBAL_VALIDATE="$REPO_DIR/scripts/validate.sh" \
	SETUP_GLOBAL_CALL_LOG="$home_dir/setup-global-calls.log" \
	SETUP_GLOBAL_TEST_ADAPTER="$bin_dir/cli-style-adapter.sh" \
	SETUP_GLOBAL_TEST_FAIL_BACKUP_MOVE="$fail_backup_move" \
	bash "$REPO_DIR/scripts/setup-global.sh" ${target:+"$target"} --skip-external "$@"
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
test_skip_backup_environment_does_not_bypass_backup
test_failed_backup_preserves_existing_config

printf '✓ setup-global backup tests passed\n'
