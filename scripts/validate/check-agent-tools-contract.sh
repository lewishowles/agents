#!/usr/bin/env bash
# Checks that the local agent-tools checkout provides the helper packages setup installs.

set -euo pipefail

# The repository containing setup's list of required helper commands.
REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
# The agent-tools checkout used by setup on this machine.
AGENT_TOOLS_DIR="$HOME/Dev/Repositories/Packages/agent-tools"

# setup-checks.sh expects setup-links.sh to be sourced first.
# shellcheck source=SCRIPTDIR/../lib/setup-links.sh
source "$REPO_DIR/scripts/lib/setup-links.sh"
# shellcheck source=SCRIPTDIR/../lib/setup-checks.sh
source "$REPO_DIR/scripts/lib/setup-checks.sh"

# Reports every helper that setup installs for Claude and Codex but cannot find
# as a correctly named package in agent-tools. Skips when there is no checkout.
main() {
	# The helper commands printed by setup's shared requirements list.
	local required_tools
	# The helper command whose package is being checked.
	local helper
	# The package manifest setup would install for the current helper.
	local pyproject_path
	# Whether any helper package is missing or has the wrong project name.
	local failed=false

	if [ ! -d "$AGENT_TOOLS_DIR" ]; then
		printf 'Skipping agent-tools contract check: no checkout at %s\n' "$AGENT_TOOLS_DIR"
		return 0
	fi

	required_tools=$(required_agent_tools both)
	while IFS= read -r helper; do
		pyproject_path="$AGENT_TOOLS_DIR/packages/$helper/pyproject.toml"
		if [ ! -f "$pyproject_path" ]; then
			printf 'Missing agent-tools helper %s: %s\n' "$helper" "$pyproject_path" >&2
			failed=true
		elif ! project_name_matches "$pyproject_path" "$helper"; then
			printf 'Misnamed agent-tools helper %s: %s does not set [project] name = "%s"\n' "$helper" "$pyproject_path" "$helper" >&2
			failed=true
		fi
	done <<< "$required_tools"

	if [ "$failed" = true ]; then
		return 1
	fi
}

# Returns success when the package manifest's [project] table names the helper,
# because setup installs each helper with uv by that name. Accepts either TOML
# quote style and ignores trailing comments.
#
# @param  {string}  pyproject_path
#     The package manifest to read.
# @param  {string}  expected_name
#     The helper command that setup installs from this package.
project_name_matches() {
	# The package manifest being checked.
	local pyproject_path="$1"
	# The project name setup expects from this package.
	local expected_name="$2"

	# Reads only the [project] table and compares its name with the expected
	# value. The single quote is built with sprintf because the awk program is
	# itself inside single quotes.
	awk -v expected="$expected_name" '
		/^[[:space:]]*\[project\][[:space:]]*(#.*)?$/ { in_project = 1; next }
		/^[[:space:]]*\[/ { in_project = 0 }
		in_project && /^[[:space:]]*name[[:space:]]*=/ {
			value = $0
			sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*/, "", value)
			sub(/[[:space:]]*(#.*)?$/, "", value)
			quote = sprintf("%c", 39)
			matched = (value == "\"" expected "\"" || value == quote expected quote)
			exit !matched
		}
		END { if (!matched) exit 1 }
	' "$pyproject_path"
}

main "$@"
