#!/usr/bin/env bash
# Scaffolds agent configuration files into a project directory.
# Copies templates for the chosen agent runtime, prompts before replacing a
# divergent shared tool copy or an outdated .claudeignore, and uses --status
# to report drift without modifying files.

set -euo pipefail

# Resolved at startup so aliases can call this script from any project directory.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PROJECT_DIR=$(pwd -P)

source "$REPO_DIR/scripts/lib/cli-style-output.sh"
source "$REPO_DIR/scripts/lib/setup-links.sh"
source "$REPO_DIR/scripts/lib/project-setup.sh"

declare -a REQUESTED_SKILL_PACKS=()
SKILL_PACK_MODE="auto"

usage() {
	local script_name
	script_name="$(basename "$0")"

	printf '\n%s\n\n' "Usage: $script_name [command]"
	printf 'Project setup:\n'
	printf '  %-22s %s\n' '--claude' 'Create Claude project files'
	printf '  %-22s %s\n' '--codex' 'Create Codex project files'
	printf '  %-22s %s\n\n' '--both' 'Create shared Claude + Codex project files'
	printf 'Project skill packs:\n'
	printf '  %-22s %s\n' '--with-skill-pack <name>' 'Install a centrally managed local skill pack'
	printf '  %-22s %s\n' '--no-skill-packs' 'Skip project skill pack detection and installation'
	printf '  %-22s %s\n\n' '--list-skill-packs' 'List available project skill packs'
	printf 'Diagnostics:\n'
	printf '  %-22s %s\n' '--status' 'Report setup drift without writing files'
	printf '\n'
	printf 'Examples:\n'
	printf '  cd /path/to/project\n'
	printf '  %s --both\n\n' "$script_name"
}

setup_claude() {
	cli_section "Claude project setup"

	cli_group_begin "Project files"
	copy_file "$REPO_DIR/templates/claude/AGENTS.md.template" "$PROJECT_DIR/AGENTS.md" "AGENTS.md"
	copy_file "$REPO_DIR/templates/claude/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md"
	cli_group_end

	copy_shared_agent_tools

	copy_claude_support_files
	install_project_skill_packs
}

setup_codex() {
	cli_section "Codex project setup"

	cli_group_begin "Project files"
	copy_file "$REPO_DIR/templates/codex/AGENTS.md.template" "$PROJECT_DIR/AGENTS.md" "AGENTS.md"
	cli_group_end

	copy_shared_agent_tools

	install_project_skill_packs
}

setup_both() {
	cli_section "Claude + Codex project setup"

	cli_group_begin "Project files"
	copy_file "$REPO_DIR/templates/shared/AGENTS.md.template" "$PROJECT_DIR/AGENTS.md" "AGENTS.md"
	copy_file "$REPO_DIR/templates/claude/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md"
	cli_group_end

	copy_shared_agent_tools

	copy_claude_support_files
	install_project_skill_packs
}

prompt_target() {
	printf 'Which agent(s)? [1] Claude  [2] Codex  [3] Both: '
	read -r choice

	case "$choice" in
		1) printf 'claude' ;;
		2) printf 'codex' ;;
		3) printf 'both' ;;
		*) cli_status failed "Invalid choice"; exit 1 ;;
	esac
}

target=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--claude)             target="claude" ;;
		--codex)              target="codex" ;;
		--both)               target="both" ;;
		--status)             target="status" ;;
		--check-project)      target="status" ;;
		--with-skill-pack)
			if [ "$#" -lt 2 ]; then
				usage >&2
				exit 1
			fi
			SKILL_PACK_MODE="explicit"
			REQUESTED_SKILL_PACKS+=("$2")
			shift
			;;
		--no-skill-packs)
			SKILL_PACK_MODE="none"
			REQUESTED_SKILL_PACKS=()
			;;
		--list-skill-packs)
			list_project_skill_packs
			exit 0
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			usage >&2
			exit 1
			;;
	esac
	shift
done

if [ -z "$target" ]; then
	target=$(prompt_target)
fi

case "$target" in
	claude)             setup_claude ;;
	codex)              setup_codex ;;
	both)               setup_both ;;
	status)         check_status; exit ;;
esac

printf '\n'
cli_status success "Done."
