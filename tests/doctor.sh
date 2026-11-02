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
# The archive of the scratch home after the last doctor run. The next run
# starts from it instead of taking a new snapshot. Empty means take a new one.
DOCTOR_AFTER_ARCHIVE=

# Removes the scratch home and snapshots when the test exits.
cleanup() {
	trash "$TEST_ROOT"
}
trap cleanup EXIT

# Makes the next doctor run take a new snapshot of the scratch home.
# Call it before a test changes the home. A missed call makes the next run fail,
# because the old snapshot no longer matches the home.
discard_doctor_snapshot() {
	DOCTOR_AFTER_ARCHIVE=
}

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
# @param  {string}  ...
#     Any further fragments that must not appear in the report.
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
	# A report fragment that must be absent.
	local absent_text
	# The doctor's actual status and output.
	local actual_status=0 output
	# Snapshots of the scratch home before and after the run.
	local before="$TEST_ROOT/before.tar" after="$TEST_ROOT/after.tar"

	if [ -n "$DOCTOR_AFTER_ARCHIVE" ]; then
		before="$DOCTOR_AFTER_ARCHIVE"
		# Write the new snapshot to the other file so it cannot overwrite the old one.
		if [ "$before" = "$after" ]; then
			after="$TEST_ROOT/before.tar"
		fi
	else
		tar -cf "$before" -C "$TEST_HOME" .
	fi
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
	if [ "$#" -gt 6 ]; then
		shift 6
		for absent_text in "$@"; do
			if grep -F -q "$absent_text" <<< "$output"; then
				printf 'Unexpected report text: %s\n%s\n' "$absent_text" "$output" >&2
				return 1
			fi
		done
	fi
	if ! cmp -s "$before" "$after"; then
		printf 'The doctor changed the scratch home.\n' >&2
		return 1
	fi
	DOCTOR_AFTER_ARCHIVE="$after"
}

# Runs setup in the scratch home with the same command stand-ins as doctor.
run_scratch_setup() {
	discard_doctor_snapshot
	HOME="$TEST_HOME" CLI_STYLE_BIN="$CLI_STYLE_STUB" PATH="$TEST_PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=src/hooks/git bash "$REPO_DIR/scripts/setup.sh" --both > "$TEST_ROOT/setup-output.txt"
}

# Creates command stand-ins so the doctor test does not use installed helpers.
create_command_stubs() {
	# The test-only command directory.
	local bin_dir="$TEST_ROOT/bin"
	# A helper command installed in that directory.
	local command_name
	# A modern Bash kept inside the test path, so doctor does not add Homebrew
	# commands ahead of the stand-ins when it restarts.
	local bash_candidate
	mkdir -p "$bin_dir"
	for bash_candidate in /opt/homebrew/bin/bash /usr/local/bin/bash "$BASH"; do
		# The candidate expands its own version when this command runs.
		# shellcheck disable=SC2016
		if [ -x "$bash_candidate" ] && "$bash_candidate" -c 'test "${BASH_VERSINFO[0]}" -ge 4'; then
			ln -s "$bash_candidate" "$bin_dir/bash"
			break
		fi
	done
	if [ ! -L "$bin_dir/bash" ]; then
		printf 'The doctor test needs Bash 4 or newer.\n' >&2
		return 1
	fi
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
	cat > "$bin_dir/hcom" <<'SH'
#!/bin/sh
# Stores test Codex arguments under the scratch home for setup and doctor.
if [ "$1" != config ] || [ "$2" != codex_args ]; then
	exit 2
fi
if [ "$#" -eq 2 ]; then
	if [ -f "$HOME/.hcom/test-codex-args" ]; then
		cat "$HOME/.hcom/test-codex-args"
	fi
else
	mkdir -p "$HOME/.hcom"
	printf '%s\n' "$3" > "$HOME/.hcom/test-codex-args"
fi
SH
	for command_name in friction team-send doc-paths; do
		printf '#!/bin/sh\nexit 0\n' > "$bin_dir/$command_name"
	done
	chmod +x "$bin_dir/cli-style" "$bin_dir/hcom" "$bin_dir/friction" "$bin_dir/team-send" "$bin_dir/doc-paths"
}

# Checks excluded skills using an editable repository exclusion list.
test_repository_skill_exclusions() {
	# The repository copy whose exclusion list this case changes.
	local copy_dir="$TEST_ROOT/repo-skill-exclusions"
	# A top-level repository entry linked into the copy.
	local entry
	mkdir -p "$copy_dir"
	for entry in "$REPO_DIR"/*; do
		ln -s "$entry" "$copy_dir/${entry##*/}"
	done
	trash "$copy_dir/scripts"
	/bin/cp -R "$REPO_DIR/scripts" "$copy_dir/scripts"
	# The doctor reads the copy's edited list and its matching skill links.
	local REPO_DIR="$copy_dir"
	trash "$TEST_HOME"
	mkdir -p "$TEST_HOME"
	run_scratch_setup
	printf 'writing\nstale-doctor-test-skill\n' > "$REPO_DIR/scripts/skill-exclusions.txt"
	check_doctor 1 'Remove excluded skill ~/.claude/skills/writing' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'excluded writing link still present'
	check_doctor 1 'Remove excluded skill ~/.agents/skills/writing' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'stale exclusion stale-doctor-test-skill'
	discard_doctor_snapshot
	trash "$TEST_HOME/.claude/skills/writing"
	check_doctor 1 'excluded writing listed in scripts/skill-exclusions.txt' "$CLI_STYLE_STUB"
	discard_doctor_snapshot
	printf 'other\n' > "$TEST_HOME/.claude/skills/writing"
	check_doctor 1 'conflicting writing run: trash ~/.claude/skills/writing' "$CLI_STYLE_STUB"
}

# Checks that a duplicate canonical skill name counts once and skips the plan.
#
# @param  {string}  copy_dir
#     The editable repository copy created by the exclusion test.
test_duplicate_skill_names() {
	# The repository copy whose skills are changed.
	local copy_dir="$1"
	# A source skill folder used to make the duplicate.
	local source_skills_dir="$REPO_DIR/skills"
	# A skill group linked into the repository copy.
	local entry
	# The doctor's repository must be the copy when it checks these links.
	local REPO_DIR="$copy_dir"
	# A duplicate canonical name already fails in the skill section, so the
	# setup plan must not count the same problem again.
	trash "$copy_dir/skills"
	mkdir -p "$copy_dir/skills/duplicate-doctor"
	for entry in "$source_skills_dir"/*; do
		[ -d "$entry" ] || continue
		ln -s "$entry" "$copy_dir/skills/${entry##*/}"
	done
	ln -s "$source_skills_dir/writing/writing" "$copy_dir/skills/duplicate-doctor/writing"
	check_doctor 1 'duplicate skill name' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" '1 required check(s) failed' 'Setup plan could not be built'
	check_doctor 1 'cli-style: missing' "$TEST_ROOT/missing-cli-style" src/hooks/git "$TEST_ROOT/manager-bin:$TEST_PATH" '2 required check(s) failed' 'Setup changes'
}

# Checks individual plan changes for backups, links, commands and settings.
test_plan_details() {
	# A skill link replaced with a real folder for the backup case.
	local skill_link
	# A Codex hook link replaced with a broken repository link.
	local hook_link
	# A real folder in the way is saved, and any old backup is removed.
	skill_link="$TEST_HOME/.claude/skills/code-style"
	discard_doctor_snapshot
	trash "$skill_link"
	mkdir -p "$skill_link" "$TEST_HOME/.claude/backups/skills"
	printf 'keep this content\n' > "$skill_link/keep.txt"
	printf 'old backup\n' > "$TEST_HOME/.claude/backups/skills/code-style.bak.20200101-000000"
	check_doctor 1 'Save ~/.claude/skills/code-style in ~/.claude/backups/skills with a timestamp' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'Remove older backup ~/.claude/backups/skills/code-style.bak.20200101-000000'
	check_doctor 1 'Link ~/.claude/skills/code-style to' "$CLI_STYLE_STUB"
	if [ "$(cat "$skill_link/keep.txt")" != 'keep this content' ]; then
		printf 'The doctor changed unmanaged skill content.\n' >&2
		return 1
	fi
	discard_doctor_snapshot
	trash "$skill_link"
	ln -s "$REPO_DIR/skills/code/code-style" "$skill_link"

	# Stale repository links are removed before relinking, with no backup.
	hook_link="$TEST_HOME/.codex/hooks/tool-call-checkpoint.sh"
	trash "$hook_link"
	ln -s "$REPO_DIR/dist/codex/hooks/missing-tool-call-checkpoint.sh" "$hook_link"
	check_doctor 1 'Remove ~/.codex/hooks/tool-call-checkpoint.sh' "$CLI_STYLE_STUB"
	check_doctor 1 'Link ~/.codex/hooks/tool-call-checkpoint.sh to' "$CLI_STYLE_STUB"
	discard_doctor_snapshot
	trash "$hook_link"
	ln -s "$REPO_DIR/dist/codex/hooks/tool-call-checkpoint.sh" "$hook_link"

	# Doctor also reports changes to hooks, settings, commands, and Git hooks.
	trash "$TEST_HOME/.claude/settings.json"
	check_doctor 1 'Link ~/.claude/settings.json to' "$CLI_STYLE_STUB"
	discard_doctor_snapshot
	ln -s "$REPO_DIR/dist/claude/settings.json" "$TEST_HOME/.claude/settings.json"
	trash "$TEST_HOME/.codex/hooks.json"
	check_doctor 1 'Link ~/.codex/hooks.json to' "$CLI_STYLE_STUB"
	discard_doctor_snapshot
	ln -s "$REPO_DIR/dist/codex/hooks.json" "$TEST_HOME/.codex/hooks.json"
	check_doctor 1 'Set core.hooksPath to src/hooks/git in this checkout' "$CLI_STYLE_STUB" other/hooks
	/bin/cp -R "$TEST_ROOT/bin" "$TEST_ROOT/missing-helper-bin"
	trash "$TEST_ROOT/missing-helper-bin/team-send"
	check_doctor 1 'Install team-send with uv from' "$CLI_STYLE_STUB" src/hooks/git "$TEST_ROOT/missing-helper-bin:$SYSTEM_PATH"

	mkdir -p "$TEST_ROOT/fail-bin"
	printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_ROOT/fail-bin/awk"
	chmod +x "$TEST_ROOT/fail-bin/awk"
	check_doctor 1 'Codex config.toml could not compare' "$CLI_STYLE_STUB" src/hooks/git "$TEST_ROOT/fail-bin:$TEST_PATH" '' 'Save ~/.codex/config.toml' 'Write ~/.codex/config.toml'
}

# Checks that link reports stay correct for broken links, names with spaces, targets with newlines and absent folders.
test_skill_link_targets() {
	# An installed skill link that the first case points at a missing skill.
	local broken_link="$TEST_HOME/.claude/skills/code-style"
	# A broken repository skill link whose name contains spaces.
	local spaced_link="$TEST_HOME/.claude/skills/old skill with spaces"
	# A broken repository skill link whose target contains a newline.
	local newline_link="$TEST_HOME/.claude/skills/old skill newline target"
	# The installed skills folder saved during the missing-folder case.
	local skills_backup="$TEST_ROOT/agents-skills-backup"

	discard_doctor_snapshot
	trash "$broken_link"
	ln -s "$REPO_DIR/skills/code/missing-code-style" "$broken_link"
	check_doctor 1 'conflicting code-style' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'Remove ~/.claude/skills/code-style'
	discard_doctor_snapshot
	trash "$broken_link"
	ln -s "$REPO_DIR/skills/code/code-style" "$broken_link"

	ln -s "$REPO_DIR/skills/code/missing-old-skill" "$spaced_link"
	check_doctor 1 'Remove ~/.claude/skills/old skill with spaces' "$CLI_STYLE_STUB"
	discard_doctor_snapshot
	trash "$spaced_link"

	ln -s "$REPO_DIR/skills/code/missing"$'\n'"skill" "$newline_link"
	check_doctor 1 'Remove ~/.claude/skills/old skill newline target' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" '' 'Remove ~/.claude/skills/code-style'
	discard_doctor_snapshot
	trash "$newline_link"

	mv "$TEST_HOME/.agents/skills" "$skills_backup"
	check_doctor 1 'missing code-style' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'Link ~/.agents/skills/code-style to'
	discard_doctor_snapshot
	mv "$skills_backup" "$TEST_HOME/.agents/skills"
}

# Checks that every Codex setting and section setup reads from memory matches
# what the old per-lookup parsers returned, including the multi-line status
# line and the {{HOME}} paths.
test_codex_config_cache() {
	# The home used when the managed sections expand {{HOME}}.
	local HOME="$TEST_HOME"
	# The config read by both parsers.
	local config="$REPO_DIR/src/adapters/codex/config.base.toml"
	# The file holding the old parser's answer for the current comparison.
	local expected="$TEST_ROOT/codex-config-expected"
	# The settings, as "section:key", that setup reads when it builds Codex config.
	local -a settings=(
		root:approval_policy root:default_permissions root:model_reasoning_effort
		root:model_verbosity root:model_reasoning_summary root:hide_agent_reasoning
		root:suppress_unstable_features_warning tui:alternate_screen
		tui:status_line tui:status_line_use_colors
	)
	# The sections that setup reads when it builds Codex config, plus the
	# workspace roots section. Setup reads that one separately, but it is the
	# only section that contains {{HOME}}.
	local -a sections=(
		features memories mcp_servers.codebase-memory-mcp mcp_servers.mdn
		mcp_servers.sketch mcp_servers.sketch.tools.run_code
		permissions.project-edit permissions.project-edit.network
		permissions.project-edit.workspace_roots
	)
	# One requested setting or section.
	local setting section key
	# The arrays that remember_codex_config fills, kept local to this test.
	# shellcheck disable=SC2034
	local -a remembered_codex_value_names=() remembered_codex_values=()
	# shellcheck disable=SC2034
	local -a remembered_codex_section_names=() remembered_codex_sections=()

	# Loads the lookups from this checkout so they read the same file as the
	# old parsers below.
	# shellcheck source=/dev/null
	source "$REPO_DIR/scripts/lib/setup-checks.sh"
	remember_codex_config

	for setting in "${settings[@]}"; do
		section="${setting%%:*}"
		key="${setting#*:}"
		read_old_codex_config_value "$config" "$section" "$key" > "$expected"

		# An empty old answer means the list names a setting the config no
		# longer has, so the comparison would no longer guard anything.
		if [ ! -s "$expected" ] || ! cmp -s "$expected" <(codex_config_value "$section" "$key"); then
			printf 'Codex setting changed: %s\n' "$setting" >&2
			return 1
		fi
	done

	for section in "${sections[@]}"; do
		read_old_codex_config_section "$config" "$section" > "$expected"

		if [ ! -s "$expected" ] || ! cmp -s "$expected" <(codex_config_section "$section"); then
			printf 'Codex section changed: %s\n' "$section" >&2
			return 1
		fi
	done

	rm "$expected"
}

# Prints one Codex setting the way setup read it before it kept the config in
# memory. Keep this a separate copy of the old parser: calling the new loader
# here would make the test compare the loader with itself.
#
# @param  {string}  config
#     The Codex base config file to read.
# @param  {string}  section
#     TOML section name, or root for a root-level setting.
# @param  {string}  key
#     Setting name to read.
read_old_codex_config_value() {
	# The config file, section and setting to read.
	local config="$1" section="$2" key="$3"

	awk -v section="$section" -v key="$key" '
		BEGIN { in_section = section == "root" }
		/^\[/ {
			if (section == "root") exit
			in_section = $0 == "[" section "]"
			next
		}
		in_section && $0 ~ "^" key "[[:space:]]*=" {
			sub("^[^=]*=[[:space:]]*", "")
			value = $0
			while (value ~ /^\[/ && value !~ /\][[:space:]]*$/ && (getline line) > 0) {
				sub("^[[:space:]]+", "", line)
				value = value (value ~ /\[$/ ? "" : " ") line
			}
			sub(/,[[:space:]]*\]$/, "]", value)
			print value
			exit
		}
	' "$config"
}

# Prints one Codex section with {{HOME}} filled in, the way setup read it
# before it kept the config in memory. Keep this a separate copy of the old
# parser for the same reason as read_old_codex_config_value.
#
# @param  {string}  config
#     The Codex base config file to read.
# @param  {string}  section
#     TOML section name to read.
read_old_codex_config_section() {
	# The config file and section to read.
	local config="$1" section="$2"

	sed "s|{{HOME}}|$HOME|g" "$config" | awk -v section="$section" '
		$0 == "[" section "]" { in_section = 1 }
		/^\[/ && in_section && $0 != "[" section "]" { exit }
		in_section { print }
	'
}

# Checks setup-plan details and confirms that doctor never changes the home.
main() {
	# The repository state before doctor runs, which must stay unchanged.
	local repo_before
	mkdir -p "$TEST_HOME"
	create_command_stubs
	mkdir -p "$TEST_ROOT/manager-bin"
	printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/manager-bin/bun"
	chmod +x "$TEST_ROOT/manager-bin/bun"
	check_doctor 1 'cli-style: missing' "$TEST_ROOT/missing-cli-style" src/hooks/git "$TEST_PATH" '1 required check(s) failed' 'Setup changes'
	check_doctor 1 'cli-style: missing' "$TEST_ROOT/missing-cli-style" src/hooks/git "$TEST_ROOT/manager-bin:$TEST_PATH" '1 required check(s) failed' 'Setup changes'
	check_doctor 0 'No required problems found' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" '' 'Setup changes'
	repo_before=$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)
	run_scratch_setup
	check_doctor 0 'Nothing to change.' "$CLI_STYLE_STUB" src/hooks/git "$TEST_PATH" 'No required problems found'
	# cli-style is counted by the plan when a package manager can install it.
	check_doctor 1 'Run bun add -g @lewishowles/cli-style' "$TEST_ROOT/missing-cli-style" src/hooks/git "$TEST_ROOT/manager-bin:$TEST_PATH" '1 required check(s) failed'
	check_doctor 1 'cannot list changes until cli-style is installed' "$TEST_ROOT/missing-cli-style" src/hooks/git "$TEST_PATH" '1 required check(s) failed'
	# A failed HCOM read leaves its plan changes unlisted.
	mkdir -p "$TEST_ROOT/hcom-fail-bin"
	printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/hcom-fail-bin/hcom"
	chmod +x "$TEST_ROOT/hcom-fail-bin/hcom"
	check_doctor 0 'HCOM arguments could not be read, so HCOM changes are not listed.' "$CLI_STYLE_STUB" src/hooks/git "$TEST_ROOT/hcom-fail-bin:$TEST_PATH" 'No required problems found'
	if [ "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" != "$repo_before" ]; then
		printf 'The doctor changed the repository.\n' >&2
		return 1
	fi

	test_plan_details
	test_skill_link_targets
	test_codex_config_cache
	test_repository_skill_exclusions
	test_duplicate_skill_names "$TEST_ROOT/repo-skill-exclusions"
	printf 'doctor tests passed\n'
}

main "$@"
