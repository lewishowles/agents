#!/usr/bin/env bash
# Read-only checks shared by setup and the doctor: the commands setup needs
# and the Codex config.toml setup would write.
# None of these functions change the install.
#
# Before sourcing this file, a script sets REPO_DIR. It must also set the
# values each check reads:
#   - Tool checks: AGENT_TOOLS_DIR.
#   - Codex config: setup_hooks and setup_permissions. Pass a temporary file
#     as the output path, because the builder writes the new config there.
# choose_cli_style_install_command stores its answer in
# cli_style_install_command for the script to read.
#
# The script that sources this file sets and reads these values, so the
# linter cannot see them from here.
# shellcheck disable=SC2034,SC2154

# Returns success when setup must install cli-style: CLI_STYLE_BIN is set but
# cannot run, or it is unset and no cli-style is on PATH. Sync and validate find
# cli-style the same way.
cli_style_install_needed() {
	if [ -n "${CLI_STYLE_BIN:-}" ]; then
		[ ! -x "$CLI_STYLE_BIN" ]
	else
		if command -v cli-style >/dev/null 2>&1; then
			return 1
		fi
		return 0
	fi
}

# Picks the command that installs cli-style globally, preferring Bun over npm,
# and stores it in cli_style_install_command. Returns 1 with install guidance
# when neither package manager is available.
choose_cli_style_install_command() {
	if command -v bun >/dev/null 2>&1; then
		cli_style_install_command=(bun add -g @lewishowles/cli-style)
	elif command -v npm >/dev/null 2>&1; then
		cli_style_install_command=(npm install -g @lewishowles/cli-style)
	else
		printf 'cli-style is not installed. Run: bun add -g @lewishowles/cli-style (or npm install -g @lewishowles/cli-style)\n' >&2
		return 1
	fi
}

# Prints the helper commands that setup installs for the selected agents.
#
# @param  {string}  target
#     The agent setup target: claude, codex or both. Empty prints nothing.
required_agent_tools() {
	# The agent setup target that decides whether friction is required.
	local target="$1"
	if [ -z "$target" ]; then
		return 0
	fi
	if [ "$target" = claude ] || [ "$target" = both ]; then
		printf '%s\n' friction
	fi
	printf '%s\n' team-send doc-paths
}

# Checks that setup can provide every agent-tools command the chosen target
# needs, before setup writes anything. A command passes when it is already
# installed, or when uv and its package in the agent-tools checkout are both
# present. Returns 1 after listing each missing command with its fix.
#
# Messages are plain text because cli-style may not be installed yet.
#
# @param  {string}  target
#     The agent setup target: claude, codex or both.
preflight_agent_tools() {
	# The agent setup target that decides which commands are needed.
	local target="$1"
	# The commands the chosen target needs.
	local -a required_commands=()
	# The command being checked.
	local command_name
	# Whether any command can be neither found nor installed.
	local missing=false
	# Whether uv is available to install missing commands.
	local uv_available=true

	while IFS= read -r command_name; do
		required_commands+=("$command_name")
	done < <(required_agent_tools "$target")

	if ! command -v uv >/dev/null 2>&1; then
		uv_available=false
	fi

	for command_name in "${required_commands[@]}"; do
		if command -v "$command_name" >/dev/null 2>&1; then
			continue
		fi

		if [ "$uv_available" = false ]; then
			printf '%s is not installed. Install uv so setup can install it.\n' "$command_name" >&2
			missing=true
		fi

		if [ ! -d "$AGENT_TOOLS_DIR/packages/$command_name" ]; then
			printf '%s is not installed. Clone agent-tools to %s so setup can install it.\n' "$command_name" "$AGENT_TOOLS_DIR" >&2
			missing=true
		fi
	done

	if [ "$missing" = true ]; then
		printf 'Setup stopped before changing anything.\n' >&2
		return 1
	fi
}

# Writes the Codex config that setup would install to a separate file, leaving
# the user's file unchanged, so setup's plan, the installer and doctor compare
# the same result. Unrelated settings in the existing config are kept.
#
# @param  {string}  config
#     The existing Codex configuration, or a missing path on first setup.
# @param  {string}  output
#     The file that receives the managed configuration.
# ShellCheck cannot tell that the remembered Codex config is filled and read
# inside this one subshell.
# shellcheck disable=SC2030
prepare_codex_config() (
	# The existing Codex configuration.
	local config="$1"
	# The file that receives the managed configuration.
	local output="$2"
	# The file read as the starting point: the user's config, or an empty file
	# on first setup.
	local source="$config"
	# The starting config with the managed root defaults applied.
	local defaults_temp=""
	# The working copy that collects the managed sections, MCP servers,
	# permissions and TUI settings.
	local temp=""
	# The temporary config with legacy inline hooks removed, when needed.
	local hooks_temp=""
	# The managed settings, each named "section:key", and their values in the same order.
	local -a remembered_codex_value_names=() remembered_codex_values=()
	# The managed section names and the text of each section in the same order.
	local -a remembered_codex_section_names=() remembered_codex_sections=()
	# Deletes the temporary files however the function ends. The function body
	# runs in a subshell so this trap does not replace the caller's EXIT trap.
	trap 'rm -f "$defaults_temp" "$temp" "$hooks_temp"' EXIT

	if [ ! -f "$source" ]; then
		source=/dev/null
	fi
	remember_codex_config
	defaults_temp=$(mktemp)
	temp=$(mktemp)
	ensure_codex_defaults "$source" "$defaults_temp" || return 1

	# Apply managed feature flags and memory settings. Leave the user's hooks
	# flag alone when hooks are off. Retire codex_hooks when hooks are chosen.
	# This runs before the managed sections below are moved to the end, so a
	# newly added section keeps its place on later runs.
	if [ "$setup_hooks" = true ]; then
		ensure_codex_section_settings "$defaults_temp" "features" "" "codex_hooks" || return 1
	else
		ensure_codex_section_settings "$defaults_temp" "features" "hooks" || return 1
	fi
	ensure_codex_section_settings "$defaults_temp" "memories" "" || return 1

	# Strip managed MCP server sections before re-appending them,
	# so re-running setup never creates duplicate entries.
	awk '
		/^\[mcp_servers\.codebase-memory-mcp(\.|\])/{ skip = 1; next }
		/^\[mcp_servers\.mdn(\.|\])/{ skip = 1; next }
		/^\[mcp_servers\.sketch(\.|\])/{ skip = 1; next }
		/^\[/{ skip = 0 }
		!skip && /^[[:space:]]*$/ { blanks++; next }
		!skip {
			while (blanks > 0) { print ""; blanks-- }
			print
		}
	' "$defaults_temp" > "$temp" || return 1
	rm "$defaults_temp"
	ensure_codex_tui_settings "$temp" || return 1

	# Re-add repository-managed MCP server configuration.
	for section in "mcp_servers.codebase-memory-mcp" "mcp_servers.mdn" "mcp_servers.sketch" "mcp_servers.sketch.tools.run_code"; do
		printf '\n' >> "$temp"
		codex_config_section "$section" >> "$temp" || return 1
	done
	if [ "$setup_permissions" = true ]; then
		ensure_codex_permission_settings "$temp" || return 1
	fi

	if [ "$setup_hooks" = true ]; then
		hooks_temp=$(mktemp)
		remove_inline_codex_hooks "$temp" "$hooks_temp" || return 1
		mv "$hooks_temp" "$temp" || return 1
	fi

	mv "$temp" "$output"
)

# Sets the root-level Codex defaults while preserving unrelated configuration.
#
# @param  {string}  source
#     Existing Codex config file to read.
# @param  {string}  destination
#     Temporary file that receives the updated configuration.
ensure_codex_defaults() {
	# The current configuration and the file receiving managed root settings.
	local source="$1" destination="$2"
	# The managed root values that replace matching settings in the current config.
	local approval_policy default_permissions model_reasoning_effort model_verbosity model_reasoning_summary hide_agent_reasoning suppress_unstable_features_warning

	approval_policy=$(codex_config_value "root" "approval_policy")
	default_permissions=$(codex_config_value "root" "default_permissions")
	model_reasoning_effort=$(codex_config_value "root" "model_reasoning_effort")
	model_verbosity=$(codex_config_value "root" "model_verbosity")
	model_reasoning_summary=$(codex_config_value "root" "model_reasoning_summary")
	hide_agent_reasoning=$(codex_config_value "root" "hide_agent_reasoning")
	suppress_unstable_features_warning=$(codex_config_value "root" "suppress_unstable_features_warning")

	awk -v approval_policy="$approval_policy" -v default_permissions="$default_permissions" \
		-v model_reasoning_effort="$model_reasoning_effort" -v model_verbosity="$model_verbosity" \
		-v model_reasoning_summary="$model_reasoning_summary" -v hide_agent_reasoning="$hide_agent_reasoning" \
		-v suppress_unstable_features_warning="$suppress_unstable_features_warning" \
		-v permission_enabled="$([ "$setup_permissions" = true ] && printf 1 || printf 0)" '
		function print_defaults() {
			print "approval_policy = " approval_policy
			if (permission_enabled) print "default_permissions = " default_permissions
			print "model_reasoning_effort = " model_reasoning_effort
			print "model_verbosity = " model_verbosity
			print "model_reasoning_summary = " model_reasoning_summary
			print "hide_agent_reasoning = " hide_agent_reasoning
			print "suppress_unstable_features_warning = " suppress_unstable_features_warning
		}
		BEGIN {
			in_root = 1
			defaults_written = 0
		}
		/^\[/ {
			if (in_root) {
				print_defaults()
				print ""
				defaults_written = 1
				in_root = 0
			}
			print
			next
		}
		in_root && /^default_permissions[[:space:]]*=/ && permission_enabled { next }
		in_root && /^(approval_policy|sandbox_mode|model_reasoning_effort|model_verbosity|model_reasoning_summary|hide_agent_reasoning|suppress_unstable_features_warning)[[:space:]]*=/ { next }
		in_root && /^[[:space:]]*$/ { next }
		{ print }
		END {
			if (!defaults_written) {
				print_defaults()
			}
		}
	' "$source" > "$destination"
}

# Reads the repository's Codex base config once and keeps every setting value
# and section text for the lookups that follow in the same shell. The caller
# declares the four remembered_codex_* arrays that this fills.
# ShellCheck cannot tell that this runs in the subshell that declared them.
# shellcheck disable=SC2031
remember_codex_config() {
	# The record type, section, setting name and text returned by the parser.
	local record_type section key content

	# The parser prints each setting and section as four NUL-separated fields:
	# the record type, the section, the setting name (empty for a section) and
	# the text. Only the first copy of a repeated setting or section is kept.
	while IFS= read -r -d '' record_type && IFS= read -r -d '' section &&
		IFS= read -r -d '' key && IFS= read -r -d '' content; do
		if [ "$record_type" = value ]; then
			remembered_codex_value_names+=("$section:$key")
			remembered_codex_values+=("$content")
		else
			remembered_codex_section_names+=("$section")
			remembered_codex_sections+=("$content")
		fi
	done < <(awk -v home="$HOME" '
		# Prints a setting unless an earlier copy of it in the same section was printed.
		function emit_value(section, key, value) {
			if (!seen_values[section SUBSEP key]++) {
				printf "value%c%s%c%s%c%s%c", 0, section, 0, key, 0, value, 0
			}
		}
		# Prints the section just read, unless it is the root settings or an
		# earlier copy of the same section was printed.
		function emit_section() {
			if (section != "root" && !seen_sections[section]++) {
				printf "section%c%s%c%c%s%c", 0, section, 0, 0, section_text, 0
			}
		}
		# Fills in {{HOME}} with the current home folder.
		function expand_home(line) {
			gsub(/\{\{HOME\}\}/, home, line)
			return line
		}
		BEGIN { section = "root" }
		/^\[/ {
			emit_section()
			section = substr($0, 2, length($0) - 2)
			section_text = expand_home($0) "\n"
			next
		}
		{
			if (section != "root") {
				section_text = section_text expand_home($0) "\n"
			}
			if ($0 !~ /^[^#[:space:]][^=]*=/) {
				next
			}
			key = $0
			sub(/[[:space:]]*=.*/, "", key)
			value = $0
			sub("^[^=]*=[[:space:]]*", "", value)

			# Join an array written over several lines into one line, so the
			# caller can write it back as a single setting.
			while (value ~ /^\[/ && value !~ /\][[:space:]]*$/ && (getline line) > 0) {
				if (section != "root") {
					section_text = section_text expand_home(line) "\n"
				}
				sub("^[[:space:]]+", "", line)
				value = value (value ~ /\[$/ ? "" : " ") line
			}
			sub(/,[[:space:]]*\]$/, "]", value)
			emit_value(section, key, value)
		}
		END { emit_section() }
	' "$REPO_DIR/src/adapters/codex/config.base.toml")
}

# Prints one repository-managed Codex configuration value from what
# remember_codex_config kept in this shell. Prints nothing if that has not run
# or the setting does not exist.
#
# @param  {string}  section
#     TOML section name, or root for a root-level setting.
# @param  {string}  key
#     Setting name to read.
codex_config_value() {
	# The config section and setting whose managed value is requested.
	local section="$1" key="$2"
	# The matching setting's position in the remembered values.
	local index

	for ((index = 0; index < ${#remembered_codex_value_names[@]}; index++)); do
		if [ "${remembered_codex_value_names[$index]}" = "$section:$key" ]; then
			printf '%s\n' "${remembered_codex_values[$index]}"
			return 0
		fi
	done
}

# Sets selected keys from one repository-managed Codex section, keeping any
# other keys already in that section. Adds the section when it is missing.
#
# @param  {string}  config
#     Codex config file to update.
# @param  {string}  section
#     TOML section name whose managed keys should be applied.
# @param  {string}  omitted_keys
#     Space-separated managed keys to leave unchanged in the user's config.
# @param  {string}  ...
#     Retired key names to remove from the section.
ensure_codex_section_settings() {
	# The config file and section receiving the managed settings.
	local config="$1" section="$2"
	# Managed keys omitted from this update.
	local omitted_keys="$3"
	shift 3
	# The file of managed key lines and the completed configuration.
	local managed temp

	managed=$(mktemp)
	temp=$(mktemp)

	# Keep only the selected key lines from the base section.
	codex_config_section "$section" | awk -v omitted="$omitted_keys" '
		NR > 1 && /^[^#[:space:]][^=]*=/ {
			key = $0
			sub(/[[:space:]]*=.*/, "", key)
			if (index(" " omitted " ", " " key " ") == 0) {
				print
			}
		}
	' > "$managed"

	# The first input is the managed key lines, the second is the user's config.
	# Managed and retired keys are dropped from the existing section, and the
	# managed lines are written straight after its header.
	awk -v header="[$section]" -v retired="$*" '
		function key_of(line) {
			sub(/^[[:space:]]+/, "", line)
			sub(/[[:space:]]*=.*$/, "", line)
			return line
		}
		function print_managed(  i) {
			for (i = 1; i <= count; i++) {
				print lines[i]
			}
		}
		FNR == NR {
			lines[++count] = $0
			drop[key_of($0)] = 1
			next
		}
		FNR == 1 {
			retired_count = split(retired, retired_keys, " ")
			for (i = 1; i <= retired_count; i++) {
				drop[retired_keys[i]] = 1
			}
		}
		$0 == header {
			print
			print_managed()
			in_section = 1
			found = 1
			next
		}
		/^\[/ { in_section = 0 }
		in_section && key_of($0) in drop { next }
		{ print }
		END {
			if (!found) {
				print ""
				print header
				print_managed()
			}
		}
	' "$managed" "$config" > "$temp"

	rm "$managed"
	mv "$temp" "$config"
}

# Prints one repository-managed Codex TOML section from what
# remember_codex_config kept in this shell. Prints nothing if that has not run
# or the section does not exist.
#
# @param  {string}  section
#     TOML section name to read.
codex_config_section() {
	# The section whose managed key lines are printed from the base config.
	local section="$1"
	# The matching section's position in the remembered text.
	local index

	for ((index = 0; index < ${#remembered_codex_section_names[@]}; index++)); do
		if [ "${remembered_codex_section_names[$index]}" = "$section" ]; then
			printf '%s' "${remembered_codex_sections[$index]}"
			return 0
		fi
	done
}

# Replaces the managed permission profile and removes incompatible sandbox settings.
#
# @param  {string}  config
#     Codex config file to update.
ensure_codex_permission_settings() {
	# The Codex config file whose permission profile is updated.
	local config="$1"
	# The file of allowed workspace roots and the completed config file.
	local roots_temp temp

	roots_temp=$(mktemp)
	temp=$(mktemp)
	collect_codex_workspace_roots "$config" "$roots_temp"

	awk '
		/^\[sandbox_workspace_write\]$/ || /^\[permissions\.project-edit(\.|\])/{ skip = 1; next }
		/^\[/ { skip = 0 }
		!skip { print }
	' "$config" > "$temp"

	{
		printf '\n'
		codex_config_section "permissions.project-edit"
		printf '\n[permissions.project-edit.workspace_roots]\n'
		awk '{ print $0 " = true" }' "$roots_temp"
		printf '\n'
		codex_config_section "permissions.project-edit.network"
	} >> "$temp"

	rm "$roots_temp"
	mv "$temp" "$config"
}

# Collects the managed and existing workspace roots without duplicates.
# Legacy sandbox roots are included so setup migrates them into the profile.
#
# @param  {string}  config
#     Existing Codex config whose workspace roots should be preserved.
# @param  {string}  destination
#     File that receives quoted TOML paths, one per line.
collect_codex_workspace_roots() {
	# The current config and the file receiving all distinct allowed workspace roots.
	local config="$1" destination="$2"

	{
		sed "s|{{HOME}}|$HOME|g" "$REPO_DIR/src/adapters/codex/config.base.toml"
		printf '\n'
		cat "$config"
	} | awk '
		/^\[/ { section = $0 }
		section == "[permissions.project-edit.workspace_roots]" && /^[[:space:]]*"[^"]+"[[:space:]]*=[[:space:]]*true/ {
			root = $0
			sub(/^[[:space:]]*/, "", root)
			sub(/"[[:space:]]*=.*$/, "\"", root)
			if (!seen[root]++) {
				print root
			}
		}
		section == "[sandbox_workspace_write]" && /^writable_roots[[:space:]]*=/ {
			line = $0
			while (match(line, /"[^"]+"/)) {
				root = substr(line, RSTART, RLENGTH)
				if (!seen[root]++) {
					print root
				}
				line = substr(line, RSTART + RLENGTH)
			}
		}
	' > "$destination"
}

# Ensures the Codex TUI uses the managed settings while preserving unrelated
# TUI preferences.
#
# @param  {string}  config
#     Codex config file to update.
ensure_codex_tui_settings() {
	# The Codex config file whose terminal display settings are updated.
	local config="$1"
	# The managed display settings and the file receiving the updated config.
	local alternate_screen status_line status_line_use_colors temp

	alternate_screen=$(codex_config_value "tui" "alternate_screen")
	status_line=$(codex_config_value "tui" "status_line")
	status_line_use_colors=$(codex_config_value "tui" "status_line_use_colors")

	temp=$(mktemp)
	awk '
		BEGIN {
			in_tui = 0
			tui_found = 0
			skipping_array = 0
		}
		/^\[tui\]$/ {
			print
			print "alternate_screen = " alternate_screen
			print "status_line = " status_line
			print "status_line_use_colors = " status_line_use_colors
			in_tui = 1
			tui_found = 1
			next
		}
		# Skip the rest of a replaced array that spans several lines.
		skipping_array {
			if ($0 ~ /^[[:space:]]*\]/) {
				skipping_array = 0
			}

			next
		}
		/^\[/ { in_tui = 0 }
		in_tui && /^(alternate_screen|status_line(_use_colors)?)[[:space:]]*=/ {
			skipping_array = $0 ~ /=[[:space:]]*\[[^]]*$/
			next
		}
		{ print }
		END {
			if (!tui_found) {
				print ""
				print "[tui]"
				print "alternate_screen = " alternate_screen
				print "status_line = " status_line
				print "status_line_use_colors = " status_line_use_colors
			}
		}
	' alternate_screen="$alternate_screen" status_line="$status_line" status_line_use_colors="$status_line_use_colors" "$config" > "$temp"
	mv "$temp" "$config"
}

# Removes inline Codex hook definitions while preserving user configuration
# and Codex-managed hook trust state. Hooks are defined in hooks.json.
#
# @param  {string}  source
#     Existing Codex config file to read.
# @param  {string}  destination
#     Temporary file that receives the configuration without inline hooks.
remove_inline_codex_hooks() {
	# The config to read and the file receiving its settings without inline hooks.
	local source="$1" destination="$2"

	awk '
		/^\[\[hooks\./ { skip = 1; next }
		/^\[hooks\.state/ { skip = 0 }
		/^\[/ && skip { skip = 0 }
		!skip { print }
	' "$source" > "$destination"
}
