#!/usr/bin/env bash
# Checks that the doctor reports install problems without changing the home.

set -euo pipefail

# The folder containing this test.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The checkout under test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# An isolated root for the home and test snapshots.
TEST_ROOT=$(mktemp -d)
# The scratch home whose contents must not change during diagnosis.
TEST_HOME="$TEST_ROOT/home"
# The stand-in cli-style command that the doctor runs instead of the installed one.
CLI_STYLE_STUB="$TEST_ROOT/bin/cli-style"
# System command folders, which hold none of the helper commands.
SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
# The command search path for the doctor: the stand-in commands, then system commands.
TEST_PATH="$TEST_ROOT/bin:$SYSTEM_PATH"

# Removes the scratch home and snapshots when the test exits.
cleanup() {
	trash "$TEST_ROOT"
}
trap cleanup EXIT

# Runs the doctor and checks both its result and its output.
#
# @param  {string}  expected_status
#     The expected process exit status.
# @param  {string}  expected_text
#     Text that must appear in the report.
# @param  {string}  cli_style_bin
#     The cli-style command to use. Defaults to a missing path, which gives
#     plain output.
# @param  {string}  hooks_path
#     Git's configured hooks path, defaulting to the managed path.
# @param  {string}  command_path
#     The command search path, defaulting to the test-only path.
# @param  {string}  expected_summary
#     An optional exact summary fragment to check as well.
check_doctor() {
	# The expected process status and report text.
	local expected_status="$1" expected_text="$2"
	# The cli-style command to use, missing by default.
	local cli_style_bin="${3-$TEST_ROOT/missing-cli-style}"
	# The Git hook path used for this run.
	local hooks_path="${4-src/hooks/git}"
	# The command search path used for this run.
	local command_path="${5-$TEST_PATH}"
	# An optional second output assertion.
	local expected_summary="${6:-}"
	# The doctor's actual status and output.
	local actual_status=0 output
	# Snapshots of the scratch home before and after the run.
	local before="$TEST_ROOT/before.tar" after="$TEST_ROOT/after.tar"

	tar -cf "$before" -C "$TEST_HOME" .
	output=$(HOME="$TEST_HOME" CLI_STYLE_BIN="$cli_style_bin" PATH="$command_path" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$hooks_path" bash "$REPO_DIR/scripts/doctor.sh" 2>&1) || actual_status=$?
	tar -cf "$after" -C "$TEST_HOME" .
	if [ "$actual_status" -ne "$expected_status" ]; then
		printf 'Expected status %s, got %s.\n%s\n' "$expected_status" "$actual_status" "$output" >&2
		return 1
	fi
	if ! grep -F -q "$expected_text" <<< "$output"; then
		printf 'Missing report text: %s\n%s\n' "$expected_text" "$output" >&2
		return 1
	fi
	if [ -n "$expected_summary" ] && ! grep -F -q "$expected_summary" <<< "$output"; then
		printf 'Missing report summary: %s\n%s\n' "$expected_summary" "$output" >&2
		return 1
	fi
	if ! cmp -s "$before" "$after"; then
		printf 'The doctor changed the scratch home.\n' >&2
		return 1
	fi
}

# Proves that a single changed path accounts for exactly one required failure.
#
# @param  {string}  expected_text
#     The specific error row expected from the changed path.
check_single_problem() {
	check_doctor 1 "$1" "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" '1 required check(s) failed'
}

# Creates command stand-ins so the doctor test does not use installed helpers.
create_command_stubs() {
	# The test-only command directory.
	local bin_dir="$TEST_ROOT/bin"
	# A helper command installed in that directory.
	local command_name
	mkdir -p "$bin_dir"
	cat > "$bin_dir/cli-style" <<'SH'
#!/bin/sh
printf '%s\n' "$(dirname "$0")/cli-style-adapter.sh"
SH
	cat > "$bin_dir/cli-style-adapter.sh" <<'SH'
# Prints the status labels and details that the assertions inspect.
cli_style_render() {
	# A status row or divider encoded as JSON.
	local input
	# The label and detail extracted from that row.
	local label detail
	IFS= read -r input
	label=${input#*\"label\": \"}
	label=${label%%\"*}
	if [ "$1" = status ]; then
		detail=${input#*\"detail\": \"}
		detail=${detail%%\"*}
		printf '%s %s\n' "$label" "$detail"
	else
		printf '%s\n' "$label"
	fi
}
SH
	for command_name in friction team-send doc-paths; do
		printf '#!/bin/sh\nexit 0\n' > "$bin_dir/$command_name"
	done
	chmod +x "$bin_dir/cli-style" "$bin_dir/friction" "$bin_dir/team-send" "$bin_dir/doc-paths"
}

# Installs a complete Claude fixture so one changed path is the only failure.
install_claude_fixture() {
	# A core file, hook, rule, or skill linked into the scratch home.
	local file_path
	mkdir -p "$TEST_HOME/.claude/hooks" "$TEST_HOME/.claude/rules" "$TEST_HOME/.claude/skills"
	for file_path in CLAUDE.md .mcp.json settings.json statusline.sh; do
		ln -s "$REPO_DIR/dist/claude/$file_path" "$TEST_HOME/.claude/$file_path"
	done
	for file_path in "$REPO_DIR"/dist/claude/hooks/*; do
		[ -f "$file_path" ] || continue
		ln -s "$file_path" "$TEST_HOME/.claude/hooks/${file_path##*/}"
	done
	for file_path in "$REPO_DIR"/dist/claude/rules/*.md; do
		[ -f "$file_path" ] || continue
		ln -s "$file_path" "$TEST_HOME/.claude/rules/${file_path##*/}"
	done
	for file_path in "$REPO_DIR"/skills/*/*; do
		[ -d "$file_path" ] || continue
		ln -s "$file_path" "$TEST_HOME/.claude/skills/${file_path##*/}"
	done
}

# Checks excluded, conflicting, and stale skills against an editable repository list.
test_repository_skill_exclusions() {
	# The repository copy whose exclusion list this case changes.
	local copy_dir="$TEST_ROOT/repo-skill-exclusions"
	# A top-level repository file or folder, linked into the copy so that only
	# scripts/ is a real copy the case can edit.
	local entry

	mkdir -p "$copy_dir"
	for entry in "$REPO_DIR"/*; do
		ln -s "$entry" "$copy_dir/${entry##*/}"
	done
	trash "$copy_dir/scripts"
	/bin/cp -R "$REPO_DIR/scripts" "$copy_dir/scripts"
	# The repository the doctor checks for the rest of this case. Declared local so
	# later cases run against the real repository again.
	local REPO_DIR="$copy_dir"

	trash "$TEST_HOME"
	mkdir -p "$TEST_HOME"
	install_claude_fixture
	printf 'writing\nstale-doctor-test-skill\n' > "$REPO_DIR/scripts/skill-exclusions.txt"
	check_doctor 0 'excluded writing' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'link still present; run: scripts/setup.sh --claude'
	check_doctor 0 'stale exclusion stale-doctor-test-skill' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'remove it from scripts/skill-exclusions.txt'

	trash "$TEST_HOME/.claude/skills/writing"
	check_doctor 0 'excluded writing' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'listed in scripts/skill-exclusions.txt'
	printf 'other\n' > "$TEST_HOME/.claude/skills/writing"
	check_doctor 0 'conflicting writing' "$CLI_STYLE_STUB"
}

# Installs the Codex links and writes the config through setup's config builder.
# Runs in a subshell so the sourced setup files and their flags stay out of
# the test.
#
# @param  {string}  permissions
#     true to include the managed permission profile, false to leave it out.
install_codex_fixture() (
	# Whether the config builder includes the managed permission profile.
	local permissions="$1"
	# Where the config builder writes its output before it moves into the scratch home.
	local proposed="$TEST_ROOT/codex-config.toml"
	# A skill linked into the scratch Codex installation.
	local file_path

	mkdir -p "$TEST_HOME/.agents/skills" "$TEST_HOME/.codex"
	if [ ! -L "$TEST_HOME/.agents/AGENTS.md" ]; then
		ln -s "$REPO_DIR/dist/codex/AGENTS.md" "$TEST_HOME/.agents/AGENTS.md"
	fi
	if [ ! -L "$TEST_HOME/.codex/AGENTS.md" ]; then
		ln -s "$REPO_DIR/dist/codex/AGENTS.md" "$TEST_HOME/.codex/AGENTS.md"
	fi
	for file_path in "$REPO_DIR"/skills/*/*; do
		[ -d "$file_path" ] || continue
		if [ ! -L "$TEST_HOME/.agents/skills/${file_path##*/}" ]; then
			ln -s "$file_path" "$TEST_HOME/.agents/skills/${file_path##*/}"
		fi
	done

	# The shared builder reads the same feature flags and templates as setup.
	# shellcheck source=scripts/lib/setup-links.sh
	source "$REPO_DIR/scripts/lib/setup-links.sh"
	# shellcheck source=scripts/lib/setup-checks.sh
	source "$REPO_DIR/scripts/lib/setup-checks.sh"
	# The fixture installs no Codex hooks.
	setup_hooks=false
	# The builder adds the permission profile only when this is true.
	setup_permissions="$permissions"
	HOME="$TEST_HOME" prepare_codex_config "$TEST_HOME/.codex/config.toml" "$proposed"
	mv "$proposed" "$TEST_HOME/.codex/config.toml"
)

# Runs the doctor against a fresh home, partial installs, Codex settings with
# and without the permission profile, and a complete Claude install with one
# fault at a time.
main() {
	mkdir -p "$TEST_HOME"
	create_command_stubs
	check_doctor 1 'Claude: not set up'
	check_doctor 1 'Codex: not set up'
	check_doctor 1 'cli-style: missing'
	check_doctor 1 'bun add -g @lewishowles/cli-style (or npm install -g @lewishowles/cli-style)'
	check_doctor 0 'No required problems found' "$CLI_STYLE_STUB"
	check_doctor 1 'Git core.hooksPath does not match src/hooks/git' "$CLI_STYLE_STUB" other/hooks
	check_doctor 1 '1 required check(s) failed' "$CLI_STYLE_STUB" other/hooks

	mkdir -p "$TEST_HOME/.claude"
	ln -s "$REPO_DIR/dist/claude/CLAUDE.md" "$TEST_HOME/.claude/CLAUDE.md"
	check_doctor 1 'Claude CLAUDE.md: correct'
	check_doctor 1 'Claude settings.json: not installed'
	check_doctor 1 'Claude hooks: not installed'
	check_doctor 1 'Claude themes: not installed'
	check_doctor 1 'trash wrapper: not installed'
	check_doctor 1 'missing writing: run: scripts/setup.sh --claude'

	mkdir -p "$TEST_HOME/.claude/hooks"
	ln -s "$REPO_DIR/dist/claude/hooks/guard-search-boundaries.sh" "$TEST_HOME/.claude/hooks/guard-search-boundaries.sh"
	check_doctor 1 'Claude settings.json: missing'
	trash "$TEST_HOME/.claude/hooks/guard-search-boundaries.sh"

	ln -s "$TEST_ROOT/absent" "$TEST_HOME/.claude/settings.json"
	check_doctor 1 'Claude settings.json: broken link to wrong target'

	trash "$TEST_HOME/.claude/settings.json"
	printf 'other\n' > "$TEST_ROOT/other-settings.json"
	ln -s "$TEST_ROOT/other-settings.json" "$TEST_HOME/.claude/settings.json"
	check_doctor 1 'Claude settings.json: wrong target'

	trash "$TEST_HOME/.claude/settings.json"
	printf 'conflict\n' > "$TEST_HOME/.claude/settings.json"
	check_doctor 1 'Claude settings.json: real file in the way'

	mkdir -p "$TEST_HOME/.agents/skills" "$TEST_HOME/.codex"
	ln -s "$REPO_DIR/dist/codex/AGENTS.md" "$TEST_HOME/.agents/AGENTS.md"
	printf 'custom = true\n' > "$TEST_HOME/.codex/config.toml"
	check_doctor 1 'Codex config.toml: differs from setup'
	mkdir -p "$TEST_ROOT/fail-bin"
	printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_ROOT/fail-bin/awk"
	chmod +x "$TEST_ROOT/fail-bin/awk"
	check_doctor 1 'Codex config.toml could not compare' "$CLI_STYLE_STUB" src/hooks/git "$TEST_ROOT/fail-bin:$TEST_PATH"

	trash "$TEST_HOME"
	mkdir -p "$TEST_HOME"
	install_codex_fixture false
	check_doctor 0 'Codex config.toml matches setup' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'Codex permission profile not installed'
	install_codex_fixture true
	check_doctor 0 'Codex config.toml matches setup' "$CLI_STYLE_STUB"
	trash "$TEST_HOME/.codex/config.toml"
	printf 'default_permissions = "custom"\n' > "$TEST_HOME/.codex/config.toml"
	install_codex_fixture false
	check_doctor 0 'Codex config.toml matches setup' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'Codex permission profile not installed'

	trash "$TEST_HOME"
	mkdir -p "$TEST_HOME/.agents/skills" "$TEST_HOME/.codex"
	ln -s "$REPO_DIR/dist/codex/AGENTS.md" "$TEST_HOME/.agents/AGENTS.md"
	printf 'custom = true\n' > "$TEST_HOME/.codex/config.toml"

	ln -s "$REPO_DIR/skills/writing/writing" "$TEST_HOME/.agents/skills/writing"
	check_doctor 1 'installed writing' "$CLI_STYLE_STUB"
	trash "$TEST_HOME/.agents/skills/writing"
	ln -s "$TEST_ROOT/absent" "$TEST_HOME/.agents/skills/writing"
	check_doctor 1 'skills/writing: broken link to wrong target'

	trash "$TEST_HOME"
	mkdir -p "$TEST_HOME"
	install_claude_fixture
	# The repository's Git status before the doctor runs, compared afterwards
	# because the doctor must not change the repository either.
	local repo_before
	repo_before=$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)
	check_doctor 0 'No required problems found' "$CLI_STYLE_STUB"
	if [ "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" != "$repo_before" ]; then
		printf 'The doctor changed the repository.\n' >&2
		return 1
	fi
	check_doctor 0 'installed mac-app' "$CLI_STYLE_STUB"
	trash "$TEST_HOME/.claude/skills/mac-app"
	check_single_problem 'missing mac-app run: scripts/setup.sh --claude'
	ln -s "$REPO_DIR/skills/apple/mac-app" "$TEST_HOME/.claude/skills/mac-app"

	trash "$TEST_HOME/.claude/skills/writing"
	check_single_problem 'missing writing run: scripts/setup.sh --claude'
	ln -s "$REPO_DIR/skills/writing/writing" "$TEST_HOME/.claude/skills/writing"

	trash "$TEST_HOME/.claude/skills/code-style"
	mkdir -p "$TEST_HOME/.claude/skills/code-style"
	printf 'keep this content\n' > "$TEST_HOME/.claude/skills/code-style/keep.txt"
	check_single_problem 'skills/code-style real file in the way'
	if [ "$(cat "$TEST_HOME/.claude/skills/code-style/keep.txt")" != 'keep this content' ]; then
		printf 'The doctor changed unmanaged skill content.\n' >&2
		return 1
	fi
	trash "$TEST_HOME/.claude/skills/code-style"
	ln -s "$REPO_DIR/skills/code/code-style" "$TEST_HOME/.claude/skills/code-style"
	check_doctor 0 'No required problems found' "$CLI_STYLE_STUB"
	/bin/cp -R "$TEST_ROOT/bin" "$TEST_ROOT/missing-helper-bin"
	trash "$TEST_ROOT/missing-helper-bin/team-send"
	check_doctor 0 'team-send not installed' "$CLI_STYLE_STUB" src/hooks/git "$TEST_ROOT/missing-helper-bin:$SYSTEM_PATH" 'No required problems found'

	trash "$TEST_HOME/.claude/.mcp.json"
	check_single_problem 'Claude .mcp.json missing'
	ln -s "$TEST_ROOT/absent" "$TEST_HOME/.claude/.mcp.json"
	check_single_problem 'Claude .mcp.json broken link to wrong target'
	trash "$TEST_HOME/.claude/.mcp.json"
	printf 'other\n' > "$TEST_ROOT/other-mcp.json"
	ln -s "$TEST_ROOT/other-mcp.json" "$TEST_HOME/.claude/.mcp.json"
	check_single_problem 'Claude .mcp.json wrong target'
	trash "$TEST_HOME/.claude/.mcp.json"
	printf 'conflict\n' > "$TEST_HOME/.claude/.mcp.json"
	check_single_problem 'Claude .mcp.json real file in the way'
	trash "$TEST_HOME/.claude/.mcp.json"
	ln -s "$REPO_DIR/dist/claude/.mcp.json" "$TEST_HOME/.claude/.mcp.json"

	trash "$TEST_HOME/.claude/skills/writing"
	check_single_problem 'missing writing run: scripts/setup.sh --claude'
	ln -s "$TEST_ROOT/other-mcp.json" "$TEST_HOME/.claude/skills/writing"
	check_single_problem 'skills/writing wrong target'
	trash "$TEST_HOME/.claude/skills/writing"
	ln -s "$REPO_DIR/skills/writing/writing" "$TEST_HOME/.claude/skills/writing"

	trash "$TEST_HOME/.claude/hooks/guard-search-boundaries.sh"
	check_single_problem 'Claude hooks/guard-search-boundaries.sh missing'
	test_repository_skill_exclusions

	printf 'doctor tests passed\n'
}

main "$@"
