#!/usr/bin/env bash
# Shared helpers for project setup commands.

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

	if project_file_exists "$target"; then
		cli_group_status muted "$label" "already exists"
		return
	fi

	cp "$source" "$target"
	cli_group_status success "created" "$label"
}

# Succeeds when a project path exists, including a broken symlink.
#
# @param  {string}  target
#     Project path to check.
project_file_exists() {
	local target="$1"

	[ -e "$target" ] || [ -L "$target" ]
}

# Prints missing, same, or differs, comparing a synced project file with its template.
#
# @param  {string}  source
#     Template file path.
# @param  {string}  target
#     Destination path in the project.
project_file_state() {
	local source="$1"
	local target="$2"

	if ! project_file_exists "$target"; then
		printf 'missing'
	elif cmp -s "$source" "$target"; then
		printf 'same'
	else
		printf 'differs'
	fi
}

# Reports the action setup will take for a project file without changing it.
#
# @param  {string}  source
#     Template file path.
# @param  {string}  target
#     Destination path in the project.
# @param  {string}  label
#     Human-readable name for output messages.
plan_file() {
	local source="$1"
	local target="$2"
	local label="$3"

	case "$(project_file_state "$source" "$target")" in
		missing) cli_group_status success "$label" "will create" ;;
		same) cli_group_status muted "$label" "already up to date (skip)" ;;
		differs) cli_group_status warning "$label" "differs (will ask before overwriting)" ;;
	esac
}

# Reports whether a user-owned project file will be created or left alone.
#
# @param  {string}  target
#     Destination path in the project.
# @param  {string}  label
#     Human-readable name for output messages.
plan_copy_file() {
	local target="$1"
	local label="$2"

	if project_file_exists "$target"; then
		cli_group_status muted "$label" "already exists (skip)"
	else
		cli_group_status success "$label" "will create"
	fi
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

	case "$(project_file_state "$source" "$target")" in
		missing)
			cp "$source" "$target"
			cli_group_status success "created" "$label"
			return
			;;
		same)
			cli_group_status muted "$label" "already up to date"
			return
			;;
	esac

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

# Ensures global project-checks and friction commands are available before setup continues.
ensure_global_tools() {
	cli_group_begin "Global tools"
	ensure_project_checks
	ensure_friction
	cli_group_end
}

# Ensures all project-checks entry points are available globally before setup
# continues.
ensure_project_checks() {
	if project_checks_installed; then
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

	if ! project_checks_installed; then
		cli_group_status failed "project-checks" "installation did not expose every command"
		return 1
	fi

	cli_group_status success "project-checks" "installed globally"
}

# Succeeds only when every command from the global project-checks tool is on PATH.
project_checks_installed() {
	local command_name
	for command_name in project-checks project-checks-change-impact project-checks-generated-file-guard project-checks-markdown-claims project-checks-repo-context; do
		if ! command -v "$command_name" >/dev/null 2>&1; then
			return 1
		fi
	done
	return 0
}

# Lists global tools and whether setup will install them.
plan_global_tools() {
	cli_group_begin "Global tools"
	if project_checks_installed; then
		cli_group_status muted "project-checks" "already installed"
	else
		cli_group_status warning "project-checks" "missing (will install)"
	fi
	if friction_installed; then
		cli_group_status muted "friction" "already installed"
	else
		cli_group_status warning "friction" "missing (will install)"
	fi
	cli_group_end
}

# Ensures the friction command is available for project rules and hooks.
ensure_friction() {
	if friction_installed; then
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

	if ! friction_installed; then
		cli_group_status failed "friction" "installation did not expose friction"
		return 1
	fi

	cli_group_status success "friction" "installed globally"
}

# Succeeds when the global friction command is available.
friction_installed() {
	command -v friction >/dev/null 2>&1
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

# Sets PROJECT_SKILL_PACK_CANDIDATES to the packs named with --with-skill-pack,
# or to the macOS pack when setup detects a macOS project. The plan and the
# installer both read it, so they always list the same packs.
select_project_skill_packs() {
	PROJECT_SKILL_PACK_CANDIDATES=()
	case "$SKILL_PACK_MODE" in
		explicit) PROJECT_SKILL_PACK_CANDIDATES=("${REQUESTED_SKILL_PACKS[@]}") ;;
		auto)
			if detect_macos_project; then
				PROJECT_SKILL_PACK_CANDIDATES=(macos)
			fi
			;;
	esac
}

# Prompts before installing an automatically detected macOS pack.
should_install_detected_macos_pack() {
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

	if ! project_skill_pack_exists "$pack_name"; then
		cli_group_status failed "$pack_name" "project skill pack not found"
		return 1
	fi

	ensure_container_dir "$PROJECT_DIR/.agents/skills" ".agents/skills/"
	ensure_container_dir "$PROJECT_DIR/.claude/skills" ".claude/skills/"

	each_project_skill_pack_link "$pack_name" link_path
}

# Succeeds when a named project skill pack has a source directory.
#
# @param  {string}  pack_name
#     Name of the pack under project-skill-packs/.
project_skill_pack_exists() {
	[ -d "$REPO_DIR/project-skill-packs/$1" ]
}

# Calls an action for the .agents/skills and .claude/skills link of each skill in a pack.
#
# @param  {string}  pack_name
#     Name of the pack under project-skill-packs/.
# @param  {string}  action
#     Function accepting the skill source, target, and display path.
each_project_skill_pack_link() {
	local pack_name="$1"
	local action="$2"
	local skill slug target_path

	for skill in "$REPO_DIR/project-skill-packs/$pack_name"/*; do
		[ -d "$skill" ] || continue
		slug=$(basename "$skill")
		for target_path in ".agents/skills/$slug" ".claude/skills/$slug"; do
			"$action" "$skill" "$PROJECT_DIR/$target_path" "$target_path"
		done
	done
}

# Reports the planned action for one project skill link.
#
# @param  {string}  source
#     Canonical skill folder.
# @param  {string}  target
#     Project link path.
# @param  {string}  label
#     Display path relative to the project.
plan_project_skill_pack_link() {
	local source="$1"
	local target="$2"
	local label="$3"

	if is_repo_owned_link "$source" "$target"; then
		cli_group_status muted "$label" "already linked"
	elif [ "$SKILL_PACK_MODE" = auto ]; then
		cli_group_status warning "$label" "offered (you will be asked)"
	else
		cli_group_status warning "$label" "link to add"
	fi
}

# Reports every link planned for one project skill pack.
#
# @param  {string}  pack_name
#     Name of the pack under project-skill-packs/.
plan_project_skill_pack() {
	local pack_name="$1"
	if ! project_skill_pack_exists "$pack_name"; then
		cli_group_status failed "$pack_name" "project skill pack not found"
		return 1
	fi

	each_project_skill_pack_link "$pack_name" plan_project_skill_pack_link
}

# Installs explicit project skill packs, or offers detected packs interactively.
install_project_skill_packs() {
	local pack
	select_project_skill_packs

	if [ "${#PROJECT_SKILL_PACK_CANDIDATES[@]}" -eq 0 ]; then
		return 0
	fi
	if [ "$SKILL_PACK_MODE" = auto ]; then
		cli_group_begin "Project skill packs"
		if ! should_install_detected_macos_pack; then
			cli_group_end
			return 0
		fi
		cli_group_end
	fi

	cli_group_begin "Project skill packs"
	for pack in "${PROJECT_SKILL_PACK_CANDIDATES[@]}"; do
		install_project_skill_pack "$pack"
	done
	cli_group_end
}

# Reports project setup state without modifying any files. Detects the
# configured mode from AGENTS.md content, then checks AGENTS.md template
# match, Claude support files (claude/both only), and unexpected runtime directories.
check_status() {
	local agents_md="$PROJECT_DIR/AGENTS.md"
	local detected_mode=""

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
	return 0
}
