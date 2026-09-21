#!/usr/bin/env bash
# Shared helpers for project setup commands.

# Shared tool links installed into every configured project's .agent/scripts/ directory.
SHARED_AGENT_TOOLS=(
	"change-impact.py|$REPO_DIR/scripts/agent-tools/change-impact.py"
	"repo-context.py|$REPO_DIR/scripts/agent-tools/repo-context.py"
	"generated-file-guard.py|$REPO_DIR/scripts/agent-tools/generated-file-guard.py"
	"markdown-claims.py|$REPO_DIR/scripts/agent-tools/markdown-claims.py"
)

# Asserts that the shared tool declaration exactly covers the source directory.
assert_shared_agent_tools() {
	local tools_dir="$REPO_DIR/scripts/agent-tools"
	local entry
	local source
	local declared_source
	local declared
	local validation_failed=0

	for entry in "${SHARED_AGENT_TOOLS[@]}"; do
		source="${entry##*|}"

		if [[ "$source" != "$tools_dir/"* ]] || [[ ! -f "$source" ]]; then
			printf 'Shared agent tool source must be a file under scripts/agent-tools/: %s\n' "$source" >&2
			validation_failed=1
		fi
	done

	for source in "$tools_dir"/.[!.]* "$tools_dir"/*; do
		if [[ ! -f "$source" ]]; then
			continue
		fi

		declared=0
		for entry in "${SHARED_AGENT_TOOLS[@]}"; do
			declared_source="${entry##*|}"
			if [[ "$declared_source" == "$source" ]]; then
				declared=1
				break
			fi
		done

		if [[ "$declared" -eq 0 ]]; then
			printf 'Shared agent tool source is not declared by SHARED_AGENT_TOOLS: %s\n' "$source" >&2
			validation_failed=1
		fi
	done

	return "$validation_failed"
}

# Copies a template to target only if target does not already exist.
#
# @param  {string}  source
#     Template file path.
# @param  {string}  target
#     Destination path in the project.
# @param  {string}  label
#     Human-readable name for output messages.
copy_file() {
	local source="$1"
	local target="$2"
	local label="$3"

	if [ -e "$target" ] || [ -L "$target" ]; then
		cli_group_status muted "$label" "already exists"
		return
	fi

	cp "$source" "$target"
	cli_group_status success "created" "$label"
}

# Copies a template to target, or prompts before overwriting a changed file.
#
# @param  {string}  source
#     Template file path.
# @param  {string}  target
#     Destination path in the project.
# @param  {string}  label
#     Human-readable name for output messages.
sync_file() {
	local source="$1"
	local target="$2"
	local label="$3"

	if ! [ -e "$target" ] && ! [ -L "$target" ]; then
		cp "$source" "$target"
		cli_group_status success "created" "$label"
		return
	fi

	if cmp -s "$source" "$target"; then
		cli_group_status muted "$label" "already up to date"
		return
	fi

	printf '\n'
	cli_group_status warning "$label" "exists locally but differs from the default"
	cli_style_hint "This usually means either you have customised it for this project or the default template has been updated."
	printf '  Overwrite with the default? (y/n): '
	read -r response
	if [[ $response == y ]]; then
		cp "$source" "$target"
		cli_group_status success "updated" "$label"
		printf '\n'
	else
		cli_group_status muted "skipped" "$label"
		printf '\n'
	fi
}

# Symlinks a shared tool into the target project so every project tracks the central
# source. Replaces an existing plain copy, prompting first if that copy has diverged.
#
# @param  {string}  source
#     Absolute path to the central script.
# @param  {string}  target
#     Destination path in the project.
# @param  {string}  label
#     Human-readable name for output messages.
link_file() {
	local source="$1"
	local target="$2"
	local label="$3"

	if [ -L "$target" ]; then
		if [ "$(readlink "$target")" = "$source" ]; then
			cli_group_status muted "$label" "already linked"
			return
		fi

		ln -sf "$source" "$target"
		cli_group_status success "relinked" "$label"
		return
	fi

	if [ -e "$target" ] && ! cmp -s "$source" "$target"; then
		printf '\n'
		cli_group_status warning "$label" "exists as a local copy that differs from the default"
		printf '  Replace it with a symlink to the shared script? (y/n): '
		read -r response
		if [[ $response != y ]]; then
			cli_group_status muted "kept local copy of" "$label"
			printf '\n'
			return
		fi
	fi

	ln -sf "$source" "$target"
	cli_group_status success "linked" "$label"
}

# Creates a directory at path if it doesn't already exist.
#
# @param  {string}  path
#     Directory to create.
# @param  {string}  label
#     Human-readable name for output messages.
ensure_dir() {
	local path="$1"
	local label="$2"

	if [ -d "$path" ]; then
		cli_group_status muted "$label" "already exists"
		return
	fi

	mkdir -p "$path"
	cli_group_status success "created" "$label"
}

# Copies Claude support files into the target project.
copy_claude_support_files() {
	cli_group_begin "Claude support files"
	ensure_dir "$PROJECT_DIR/.claude" ".claude/"

	sync_file "$REPO_DIR/templates/claude/.claudeignore" "$PROJECT_DIR/.claude/.claudeignore" ".claude/.claudeignore"
	cli_group_end
}

# Links shared project-local agent tooling into the target project. Symlinks keep every
# project tracking the central source, so improvements and fixes propagate without re-copying.
copy_shared_agent_tools() {
	local entry

	if ! assert_shared_agent_tools; then
		cli_status failed "Shared agent tools" "source declarations do not match scripts/agent-tools/"
		return 1
	fi

	cli_group_begin "Shared agent tools"
	ensure_project_checks
	ensure_friction
	ensure_dir "$PROJECT_DIR/.agent/scripts" ".agent/scripts/"

	for entry in "${SHARED_AGENT_TOOLS[@]}"; do
		local name="${entry%%|*}"
		local source="${entry##*|}"

		link_file "$source" "$PROJECT_DIR/.agent/scripts/$name" ".agent/scripts/$name"
	done
	cli_group_end
}

# Ensures all project-checks entry points are available globally before linking
# their project-local shims.
ensure_project_checks() {
	local command_name
	local missing_commands=()
	local expected_commands=(
		project-checks
		project-checks-change-impact
		project-checks-generated-file-guard
		project-checks-markdown-claims
		project-checks-repo-context
	)

	for command_name in "${expected_commands[@]}"; do
		if ! command -v "$command_name" >/dev/null 2>&1; then
			missing_commands+=("$command_name")
		fi
	done

	if [ "${#missing_commands[@]}" -eq 0 ]; then
		cli_group_status muted "project-checks" "globally installed"
		return
	fi

	if ! command -v uv >/dev/null 2>&1; then
		cli_group_status failed "project-checks" "missing and uv is not installed"
		return 1
	fi

	cli_group_status warning "project-checks" "installing globally"
	if ! uv tool install --from ~/Dev/Repositories/Packages/dev-tools/packages/project-checks project-checks >/dev/null; then
		cli_group_status failed "project-checks" "global installation failed"
		return 1
	fi

	for command_name in "${expected_commands[@]}"; do
		if ! command -v "$command_name" >/dev/null 2>&1; then
			cli_group_status failed "project-checks" "installation did not expose $command_name"
			return 1
		fi
	done

	cli_group_status success "project-checks" "installed globally"
}

# Ensures the friction command is available for project rules and hooks.
ensure_friction() {
	if command -v friction >/dev/null 2>&1; then
		cli_group_status muted "friction" "globally installed"
		return
	fi

	if ! command -v uv >/dev/null 2>&1; then
		cli_group_status failed "friction" "missing and uv is not installed"
		return 1
	fi

	cli_group_status warning "friction" "installing globally"
	if ! uv tool install --from ~/Dev/Repositories/Packages/dev-tools/packages/friction friction >/dev/null; then
		cli_group_status failed "friction" "global installation failed"
		return 1
	fi

	if ! command -v friction >/dev/null 2>&1; then
		cli_group_status failed "friction" "installation did not expose friction"
		return 1
	fi

	cli_group_status success "friction" "installed globally"
}

# Lists centrally managed project skill packs available for local project installs.
list_project_skill_packs() {
	local packs_dir="$REPO_DIR/project-skill-packs"
	local pack

	if [ ! -d "$packs_dir" ]; then
		return
	fi

	for pack in "$packs_dir"/*; do
		[ -d "$pack" ] || continue
		printf '%s\n' "$(basename "$pack")"
	done
}

# Returns 0 when the current project looks like a macOS or Swift project.
detect_macos_project() {
	local candidate

	for candidate in "$PROJECT_DIR"/*.xcodeproj "$PROJECT_DIR"/*.xcworkspace; do
		if [ -e "$candidate" ] || [ -L "$candidate" ]; then
			return 0
		fi
	done

	if [ -f "$PROJECT_DIR/Package.swift" ]; then
		shopt -s globstar nullglob
		for candidate in "$PROJECT_DIR"/Sources/**/*.swift "$PROJECT_DIR"/Tests/**/*.swift "$PROJECT_DIR"/*.swift; do
			if [ -f "$candidate" ]; then
				return 0
			fi
		done
	fi

	return 1
}

# Prompts for automatic macOS pack installation when the project shape matches.
should_install_detected_macos_pack() {
	if ! detect_macos_project; then
		return 1
	fi

	printf 'Detected a macOS/Swift project. Install local macOS skills? [Y/n] '
	local response
	if ! read -r response; then
		cli_group_status muted "macos" "detected; use --with-skill-pack macos to install non-interactively"
		return 1
	fi

	case "$response" in
		n|N|no|No|NO) return 1 ;;
		*) return 0 ;;
	esac
}

# Installs one project skill pack into both local agent skill directories.
#
# @param  {string}  pack_name
#     Name of the pack under project-skill-packs/.
install_project_skill_pack() {
	local pack_name="$1"
	local pack_dir="$REPO_DIR/project-skill-packs/$pack_name"
	local skill slug

	if [ ! -d "$pack_dir" ]; then
		cli_group_status failed "$pack_name" "project skill pack not found"
		return 1
	fi

	ensure_container_dir "$PROJECT_DIR/.agents/skills" ".agents/skills/"
	ensure_container_dir "$PROJECT_DIR/.claude/skills" ".claude/skills/"

	for skill in "$pack_dir"/*; do
		[ -d "$skill" ] || continue
		slug=$(basename "$skill")
		link_path "$skill" "$PROJECT_DIR/.agents/skills/$slug" ".agents/skills/$slug"
		link_path "$skill" "$PROJECT_DIR/.claude/skills/$slug" ".claude/skills/$slug"
	done
}

# Installs explicit project skill packs, or offers detected packs interactively.
install_project_skill_packs() {
	local packs=()
	local pack

	case "$SKILL_PACK_MODE" in
		none) return 0 ;;
		explicit) packs=("${REQUESTED_SKILL_PACKS[@]}") ;;
		auto)
			cli_group_begin "Project skill packs"
			if should_install_detected_macos_pack; then
				packs=(macos)
			fi
			cli_group_end
			;;
	esac

	if [ "${#packs[@]}" -eq 0 ]; then
		return 0
	fi

	cli_group_begin "Project skill packs"
	for pack in "${packs[@]}"; do
		install_project_skill_pack "$pack"
	done
	cli_group_end
}

# Reports project setup state without modifying any files. Detects the
# configured mode from AGENTS.md content, then checks AGENTS.md template
# match, .agent/scripts symlink targets, Claude
# support files (claude/both only), and unexpected runtime directories.
check_status() {
	local agents_md="$PROJECT_DIR/AGENTS.md"
	local detected_mode=""
	local entry
	local source_validation_status=0

	# Detect mode from AGENTS.md body text.
	if [ -f "$agents_md" ]; then
		if grep -Fq "Claude Code and Codex" "$agents_md"; then
			detected_mode="both"
		elif grep -Fq "Claude Code" "$agents_md"; then
			detected_mode="claude"
		elif grep -Fq "Codex" "$agents_md"; then
			detected_mode="codex"
		fi
	fi

	cli_section "Project setup status" "$PROJECT_DIR"

	if [ -z "$detected_mode" ]; then
		cli_status failed "No setup detected" "AGENTS.md missing or mode unrecognised"
		local _json
		_json='{"next":'"$(cli_style_json_string "Run setup to create project files")"',"reason":'"$(cli_style_json_string "")"',"commands":'"$(cli_style_json_string_array "setup-project.sh --claude" "setup-project.sh --codex" "setup-project.sh --both")"',"alternatives":'"$(cli_style_json_string_array)"'}'
		cli_style_render_json next-step-block "$_json"
		return 0
	fi

	cli_status success "Detected mode" "$detected_mode"

	# AGENTS.md template match.
	cli_group_begin "Project rules"
	local template=""
	case "$detected_mode" in
		claude) template="$REPO_DIR/templates/claude/AGENTS.md.template" ;;
		codex)  template="$REPO_DIR/templates/codex/AGENTS.md.template" ;;
		both)   template="$REPO_DIR/templates/shared/AGENTS.md.template" ;;
	esac
	if cmp -s "$template" "$agents_md"; then
		cli_group_status muted "AGENTS.md" "matches template"
	else
		cli_group_status warning "AGENTS.md" "differs from template (may be customised)"
	fi
	cli_group_end

	# Shared agent tools — each should be a symlink to the central source.
	cli_group_begin "Shared agent tools"
	if ! assert_shared_agent_tools; then
		cli_group_status failed "source declarations" "do not match scripts/agent-tools/"
		source_validation_status=1
	fi

	local scripts_dir="$PROJECT_DIR/.agent/scripts"
	if [ ! -d "$scripts_dir" ]; then
		cli_group_status warning ".agent/scripts/" "missing"
	else
		for entry in "${SHARED_AGENT_TOOLS[@]}"; do
			local name="${entry%%|*}"
			local source="${entry##*|}"
			local target="$scripts_dir/$name"

			if [ ! -e "$target" ] && [ ! -L "$target" ]; then
				cli_group_status failed "$name" "missing"
			elif [ -L "$target" ]; then
				if [ "$(readlink "$target")" = "$source" ]; then
					cli_group_status muted "$name" "linked correctly"
				else
					cli_group_status warning "$name" "symlink points elsewhere"
				fi
			else
				cli_group_status warning "$name" "local copy, not symlinked"
			fi
		done
	fi
	cli_group_end

	# Claude support files (claude/both only).
	if [ "$detected_mode" = "claude" ] || [ "$detected_mode" = "both" ]; then
		cli_group_begin "Claude support files"
		local claudeignore="$PROJECT_DIR/.claude/.claudeignore"

		if [ ! -d "$PROJECT_DIR/.claude" ]; then
			cli_group_status warning ".claude/" "missing"
		elif [ ! -e "$claudeignore" ] && [ ! -L "$claudeignore" ]; then
			cli_group_status warning ".claude/.claudeignore" "missing"
		elif cmp -s "$REPO_DIR/templates/claude/.claudeignore" "$claudeignore"; then
			cli_group_status muted ".claude/.claudeignore" "matches template"
		else
			cli_group_status warning ".claude/.claudeignore" "differs from template (may be customised)"
		fi
		cli_group_end
	fi

	# Unexpected runtime directories.
	cli_group_begin "Runtime directories"
	if [ -e "$PROJECT_DIR/.agents" ]; then
		cli_group_status warning ".agents/" "present (local skills — intentional?)"
	fi
	cli_group_end

	# Repair guidance — no files are modified.
	local _json
	_json='{"next":'"$(cli_style_json_string "Repair setup drift")"',"reason":'"$(cli_style_json_string "")"',"commands":'"$(cli_style_json_string_array "setup-project.sh --$detected_mode" "setup-project.sh --write-workspace" "setup-project.sh --force-workspace")"',"alternatives":'"$(cli_style_json_string_array)"'}'
	cli_style_render_json next-step-block "$_json"
	return "$source_validation_status"
}
