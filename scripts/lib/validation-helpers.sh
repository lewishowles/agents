#!/usr/bin/env bash
# Shared helpers for repository validation scripts.

# The folder that holds the shared validation helpers.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The repository root, used to load the shared shell libraries.
REPO_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

source "$REPO_DIR/scripts/lib/colours.sh"
source "$REPO_DIR/scripts/lib/cli-style-output.sh"

# The number of validation errors reported so far.
VALIDATE_ERRORS=0

# Prints an error message and increments the validation error counter.
#
# @param  {string}  message
#     Error message to display.
validate_fail() {
	cli_status error "$1" >&2
	VALIDATE_ERRORS=$((VALIDATE_ERRORS + 1))
}

# Prints a warning message without incrementing the validation error counter.
#
# @param  {string}  message
#     Warning message to display.
validate_warn() {
	cli_status warning "$1" >&2
}

# Prints a validation section heading.
#
# @param  {string}  heading
#     Section heading to print.
validate_section() {
	printf '\n%s\n' "$1"
}

# Returns 0 if the value is in the allowed list, 1 otherwise.
#
# @param  {string}  value
#     The value to check.
# @param  {string}  ...
#     Allowed values passed as remaining arguments.
validate_is_valid() {
	# The value to check against the allowed values.
	local value="$1"
	shift
	# The allowed value being compared.
	local allowed

	for allowed in "$@"; do
		if [ "$value" = "$allowed" ]; then
			return 0
		fi
	done

	return 1
}

# Exits with the current validation status.
validate_finish() {
	if [ "$VALIDATE_ERRORS" -gt 0 ]; then
		cli_status error "$VALIDATE_ERRORS error(s) found"
		exit 1
	fi
}

# Ensures jq is available for validation checks that read JSON manifests.
validate_require_jq() {
	if ! command -v jq &>/dev/null; then
		cli_status error "This script requires jq." "Install it with: brew install jq" >&2
		exit 1
	fi
}
