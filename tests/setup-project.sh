#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

run_setup() {
	local target_dir="$1"
	shift
	(
		cd "$target_dir"
		"$REPO_DIR/scripts/setup-project.sh" "$@" >/dev/null </dev/null
	)
}

run_setup_output() {
	local target_dir="$1"
	shift
	(
		cd "$target_dir"
		"$REPO_DIR/scripts/setup-project.sh" "$@" </dev/null
	)
}

run_setup_input() {
	local target_dir="$1"
	local input="$2"
	shift 2
	(
		cd "$target_dir"
		printf '%b' "$input" | "$REPO_DIR/scripts/setup-project.sh" "$@" >/dev/null
	)
}

test_claude_setup() {
	local target_dir="$TEST_ROOT/claude"
	mkdir -p "$target_dir/src"

	run_setup "$target_dir" --claude

	assert_file "$target_dir/AGENTS.md"
	assert_file "$target_dir/CLAUDE.md"
	assert_contains "$target_dir/CLAUDE.md" "@AGENTS.md"
	assert_dir "$target_dir/.claude"
	assert_file "$target_dir/.claude/.claudeignore"
	assert_not_exists "$target_dir/.claude/templates"
	assert_contains "$target_dir/AGENTS.md" "Claude Code"
}

test_codex_setup() {
	local target_dir="$TEST_ROOT/codex"
	mkdir -p "$target_dir/src"

	run_setup "$target_dir" --codex

	assert_file "$target_dir/AGENTS.md"
	assert_not_exists "$target_dir/CLAUDE.md"
	assert_not_exists "$target_dir/.agents"
	assert_contains "$target_dir/AGENTS.md" "Codex"
}

test_both_setup() {
	local target_dir="$TEST_ROOT/both"
	mkdir -p "$target_dir/src"

	run_setup "$target_dir" --both

	assert_file "$target_dir/AGENTS.md"
	assert_file "$target_dir/CLAUDE.md"
	assert_contains "$target_dir/CLAUDE.md" "@AGENTS.md"
	assert_file "$target_dir/.claude/.claudeignore"
	assert_not_exists "$target_dir/.claude/templates"
	assert_not_exists "$target_dir/.agents"
	assert_contains "$target_dir/AGENTS.md" "Claude Code and Codex"
}

# Checks that each setup mode lists its files before creating them.
test_plan_lists_missing_files() {
	local mode target_dir output
	for mode in claude codex both; do
		target_dir="$TEST_ROOT/plan-$mode"
		output="$TEST_ROOT/plan-$mode.out"
		mkdir -p "$target_dir"

		run_setup_output "$target_dir" "--$mode" > "$output"

		assert_contains "$output" "Project setup plan"
		assert_contains "$output" "AGENTS.md"
		assert_contains "$output" "will create"
		assert_contains "$output" "Global tools"
		if [ "$mode" = codex ]; then
			assert_not_contains "$output" ".claude/.claudeignore"
		else
			assert_contains "$output" "CLAUDE.md"
			assert_contains "$output" ".claude/.claudeignore"
		fi
	done
}

# Confirms that the printed plan precedes the first project file write.
test_plan_precedes_project_files() {
	local target_dir="$TEST_ROOT/plan-before-write"
	local output="$TEST_ROOT/plan-before-write.out"
	local plan_line created_line
	mkdir -p "$target_dir"

	(
		cd "$target_dir"
		CLI_STYLE_VERBOSE=1 "$REPO_DIR/scripts/setup-project.sh" --codex > "$output" </dev/null
	)

	plan_line=$(grep -n -m1 'will create' "$output")
	created_line=$(grep -n -m1 'created' "$output")
	plan_line=${plan_line%%:*}
	created_line=${created_line%%:*}
	[ "$plan_line" -lt "$created_line" ] || fail "Expected the setup plan before the first created file"
}

# Confirms that setup preserves existing project instructions without asking.
test_plan_skips_existing_project_instructions() {
	local target_dir="$TEST_ROOT/plan-existing"
	local output="$TEST_ROOT/plan-existing.out"
	mkdir -p "$target_dir"
	printf 'custom rules\n' > "$target_dir/AGENTS.md"
	printf 'custom Claude rules\n' > "$target_dir/CLAUDE.md"

	run_setup_output "$target_dir" --both > "$output"

	assert_contains "$output" "already exists (skip)"
	assert_not_contains "$output" "Overwrite with the default?"
	assert_equals "$(cat "$target_dir/AGENTS.md")" "custom rules"
	assert_equals "$(cat "$target_dir/CLAUDE.md")" "custom Claude rules"
}

# Checks the plan and overwrite choices for the managed Claude ignore file.
test_plan_reports_claudeignore_states() {
	local target_dir="$TEST_ROOT/plan-ignore"
	local output="$TEST_ROOT/plan-ignore.out"
	mkdir -p "$target_dir/.claude"
	cp "$REPO_DIR/templates/claude/.claudeignore" "$target_dir/.claude/.claudeignore"

	run_setup_output "$target_dir" --claude > "$output"
	assert_contains "$output" "already up to date (skip)"
	assert_not_contains "$output" "Overwrite with the default?"

	printf 'custom ignore\n' > "$target_dir/.claude/.claudeignore"
	(
		cd "$target_dir"
		printf 'n\n' | "$REPO_DIR/scripts/setup-project.sh" --claude > "$output"
	)
	assert_contains "$output" "differs (will ask before overwriting)"
	assert_contains "$output" "Overwrite with the default?"
	assert_equals "$(cat "$target_dir/.claude/.claudeignore")" "custom ignore"

	(
		cd "$target_dir"
		printf 'y\n' | "$REPO_DIR/scripts/setup-project.sh" --claude > "$output"
	)
	assert_contains "$output" "differs (will ask before overwriting)"
	cmp -s "$REPO_DIR/templates/claude/.claudeignore" "$target_dir/.claude/.claudeignore" || fail "Expected Claude ignore template after overwrite"
}

# Checks that explicit skill packs appear in the plan as links.
test_plan_lists_skill_links() {
	local target_dir="$TEST_ROOT/plan-skills"
	local output="$TEST_ROOT/plan-skills.out"
	mkdir -p "$target_dir"

	run_setup_output "$target_dir" --both --with-skill-pack macos > "$output"

	assert_contains "$output" ".agents/skills/swift"
	assert_contains "$output" ".claude/skills/swift"
	assert_contains "$output" "link to add"

	run_setup_output "$target_dir" --both --with-skill-pack macos > "$output"
	assert_contains "$output" "already linked"
}

# Checks that detected skills are offered before their confirmation prompt.
test_plan_offers_detected_skill_links() {
	local target_dir="$TEST_ROOT/plan-detected-skills"
	local output="$TEST_ROOT/plan-detected-skills.out"
	mkdir -p "$target_dir/Sources/App"
	printf '// swift package\n' > "$target_dir/Package.swift"
	printf 'struct App {}\n' > "$target_dir/Sources/App/App.swift"

	(
		cd "$target_dir"
		printf 'n\n' | "$REPO_DIR/scripts/setup-project.sh" --both > "$output"
	)

	assert_contains "$output" ".agents/skills/swift"
	assert_contains "$output" "offered (you will be asked)"
	assert_contains "$output" "Detected a macOS/Swift project. Install local macOS skills?"
	assert_not_exists "$target_dir/.agents"
}

# Checks the installed and missing labels for both global tools.
test_plan_reports_global_tool_states() {
	local output="$TEST_ROOT/plan-tools.out"
	(
		source "$REPO_DIR/scripts/lib/project-setup.sh"
		cli_group_begin() { :; }
		cli_group_end() { :; }
		cli_group_status() { printf '%s: %s\n' "$2" "$3"; }
		PATH=""
		plan_global_tools
	) > "$output"
	assert_contains "$output" "project-checks: missing (will install)"
	assert_contains "$output" "friction: missing (will install)"

	(
		source "$REPO_DIR/scripts/lib/project-setup.sh"
		cli_group_begin() { :; }
		cli_group_end() { :; }
		cli_group_status() { printf '%s: %s\n' "$2" "$3"; }
		project_checks_installed() { return 0; }
		friction() { :; }
		plan_global_tools
	) > "$output"
	assert_contains "$output" "project-checks: already installed"
	assert_contains "$output" "friction: already installed"
}

test_existing_files_are_skipped() {
	local target_dir="$TEST_ROOT/existing"
	local output="$TEST_ROOT/existing-second.out"
	mkdir -p "$target_dir"
	printf 'custom rules\n' > "$target_dir/AGENTS.md"

	run_setup "$target_dir" --both
	printf 'custom Claude rules\n' > "$target_dir/CLAUDE.md"
	run_setup_output "$target_dir" --both > "$output"

	assert_equals "$(cat "$target_dir/AGENTS.md")" "custom rules"
	assert_equals "$(cat "$target_dir/CLAUDE.md")" "custom Claude rules"
	assert_file "$target_dir/.claude/.claudeignore"
	assert_contains "$output" "Global tools"
	assert_contains "$output" "2 unchanged"
	assert_contains "$output" "Claude support files"
	assert_contains "$output" "2 unchanged"
}

test_help_lists_commands() {
	local output="$TEST_ROOT/help.txt"

	"$REPO_DIR/scripts/setup-project.sh" --help > "$output"

	assert_contains "$output" "Usage: setup-project.sh [command]"
	assert_contains "$output" "Project setup:"
	assert_contains "$output" "--both"
	assert_contains "$output" "Project skill packs:"
	assert_contains "$output" "--with-skill-pack"
	assert_contains "$output" "--no-skill-packs"
	assert_contains "$output" "--list-skill-packs"
	assert_contains "$output" "Diagnostics:"
	assert_contains "$output" "--status"
	assert_contains "$output" "Examples:"
}

test_list_skill_packs_reports_macos() {
	local output="$TEST_ROOT/skill-packs.txt"

	"$REPO_DIR/scripts/setup-project.sh" --list-skill-packs > "$output"

	assert_contains "$output" "macos"
	assert_not_contains "$output" "Project setup plan"
}

test_explicit_skill_pack_installs_local_links() {
	local target_dir="$TEST_ROOT/skill-pack-explicit"
	mkdir -p "$target_dir/src"

	run_setup "$target_dir" --both --with-skill-pack macos

	assert_dir_link "$target_dir/.agents/skills/swift"
	assert_dir_link "$target_dir/.agents/skills/macos"
	assert_dir_link "$target_dir/.claude/skills/swift"
	assert_dir_link "$target_dir/.claude/skills/macos"
	assert_equals "$(readlink "$target_dir/.agents/skills/swift")" "$REPO_DIR/project-skill-packs/macos/swift"
}

test_detected_skill_pack_installs_when_confirmed() {
	local target_dir="$TEST_ROOT/skill-pack-detected"
	mkdir -p "$target_dir/Sources/App"
	printf '// swift package\n' > "$target_dir/Package.swift"
	printf 'struct App {}\n' > "$target_dir/Sources/App/App.swift"

	run_setup_input "$target_dir" "y\n" --both

	assert_dir_link "$target_dir/.agents/skills/swift"
	assert_dir_link "$target_dir/.claude/skills/swift"
}

test_agent_docs_mentions_do_not_trigger_skill_pack_detection() {
	local target_dir="$TEST_ROOT/skill-pack-docs-mention"
	local output="$TEST_ROOT/skill-pack-docs-mention.out"
	mkdir -p "$target_dir/src"
	printf 'Use Swift skills when editing Swift files.\n' > "$target_dir/AGENTS.md"

	run_setup_output "$target_dir" --both > "$output" 2>&1

	assert_not_contains "$output" "Detected a macOS/Swift project"
	assert_not_exists "$target_dir/.agents"
}

test_no_skill_packs_suppresses_detection() {
	local target_dir="$TEST_ROOT/skill-pack-suppressed"
	mkdir -p "$target_dir/Sources/App"
	printf '// swift package\n' > "$target_dir/Package.swift"
	printf 'struct App {}\n' > "$target_dir/Sources/App/App.swift"

	run_setup "$target_dir" --both --no-skill-packs

	assert_not_exists "$target_dir/.agents"
	assert_not_exists "$target_dir/.claude/skills"
}

test_status_reports_clean_project() {
	local target_dir="$TEST_ROOT/status-clean"
	local output="$TEST_ROOT/status-clean.out"
	mkdir -p "$target_dir/src"

	run_setup_output "$target_dir" --status > "$output" 2>&1

	assert_contains "$output" "No setup detected"
	assert_not_contains "$output" "Done."
	assert_not_contains "$output" "Project setup plan"
}

test_status_reports_configured_project() {
	local target_dir="$TEST_ROOT/status-configured"
	local output="$TEST_ROOT/status-configured.out"
	mkdir -p "$target_dir/src"

	run_setup "$target_dir" --both
	run_setup_output "$target_dir" --status > "$output" 2>&1

	assert_contains "$output" "Detected mode"
	assert_contains "$output" "both"
	assert_contains "$output" "Project rules"
}

test_status_reports_drifted_project() {
	local target_dir="$TEST_ROOT/status-drifted"
	local output="$TEST_ROOT/status-drifted.out"
	mkdir -p "$target_dir/src"

	run_setup "$target_dir" --both
	mv "$target_dir/.claude/.claudeignore" "$target_dir/.claude/.claudeignore.removed"

	run_setup_output "$target_dir" --status > "$output" 2>&1

	assert_contains "$output" ".claude/.claudeignore"
}

test_ensure_friction_installs_only_when_missing() {
	local command_dir="$TEST_ROOT/friction-commands"
	local install_log="$TEST_ROOT/friction-install.log"
	local setup_library="$REPO_DIR/scripts/lib/project-setup.sh"

	mkdir -p "$command_dir"

	(
		source "$setup_library"
		cli_group_status() { :; }
		PATH="$command_dir"
		# Defines the friction() shim as a side effect of the mocked install call, so
		# command -v friction resolves to it once ensure_friction runs the installer.
		# The empty PATH above only keeps a real friction or uv binary from
		# short-circuiting the earlier not-installed check.
		uv() {
			printf '%s\n' "$*" > "$install_log"
			friction() { :; }
		}

		ensure_friction
	)
	assert_equals "$(cat "$install_log")" "tool install --from $HOME/Dev/Repositories/Packages/dev-tools/packages/friction friction"

	(
		source "$setup_library"
		cli_group_status() { :; }
		friction() { :; }
		uv() { fail "Expected friction installation to be skipped"; }

		ensure_friction
	)
}

test_claude_setup
test_codex_setup
test_both_setup
test_plan_lists_missing_files
test_plan_precedes_project_files
test_plan_skips_existing_project_instructions
test_plan_reports_claudeignore_states
test_plan_lists_skill_links
test_plan_offers_detected_skill_links
test_plan_reports_global_tool_states
test_existing_files_are_skipped
test_help_lists_commands
test_list_skill_packs_reports_macos
test_explicit_skill_pack_installs_local_links
test_detected_skill_pack_installs_when_confirmed
test_agent_docs_mentions_do_not_trigger_skill_pack_detection
test_no_skill_packs_suppresses_detection
test_status_reports_clean_project
test_status_reports_configured_project
test_status_reports_drifted_project
test_ensure_friction_installs_only_when_missing

printf '✓ setup-project tests passed\n'
