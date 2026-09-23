#!/usr/bin/env bash
# Runs all repository validation checks in a stable order.

set -euo pipefail

# macOS ships bash 3.2; several validators need bash 4+ (declare -A, mapfile).
# Re-exec under homebrew bash if the current interpreter is too old.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
	export PATH="/opt/homebrew/bin:$PATH"
	if [ -x /opt/homebrew/bin/bash ]; then
		exec /opt/homebrew/bin/bash "$0" "$@"
	else
		exec "$(command -v bash)" "$0" "$@"
	fi
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$REPO_DIR/scripts/lib/colours.sh"
source "$REPO_DIR/scripts/lib/cli-style-output.sh"

FAILED_CHECKS=0

cli_section "Validation" "Run repository checks"

cli_group_begin "Checks"

# Runs a command as a named validation check.
# Records the result in the active group. Passing checks stay silent and are
# reported in the group summary; failures print their output and a ✗ row.
# Set CLI_STYLE_VERBOSE=1 to show a row for every check as it runs.
#
# @param  {string}  label
#     Human-readable name recorded for the check.
# @param  {string}  ...
#     Command and arguments to execute.
run_check() {
	local label="$1"
	local output
	shift
	if [ "${CLI_STYLE_VERBOSE:-0}" = "1" ]; then
		cli_status info "Checking" "$label"
	fi
	if output=$("$@" 2>&1); then
		if [ "$label" = "staleness" ] && [ -n "$output" ]; then
			printf '%s\n' "$output"
		fi
		cli_group_status success "$label"
	else
		if [ -n "$output" ]; then
			printf '%s\n' "$output" >&2
		fi
		cli_group_status error "$label" "failed"
		FAILED_CHECKS=$((FAILED_CHECKS + 1))
	fi
}

run_check "skill manifests"       bash "$REPO_DIR/scripts/validate/check-skill-manifests.sh"
run_check "hook manifests"        bash "$REPO_DIR/scripts/validate/check-hook-manifests.sh"
run_check "generated files"       bash "$REPO_DIR/scripts/validate/check-generated-files.sh"
run_check "hook sync"             bash "$REPO_DIR/scripts/validate/check-hook-sync.sh"
run_check "dist sync"             bash "$REPO_DIR/scripts/validate/check-dist-sync.sh"
run_check "docs tables"           python3 "$REPO_DIR/scripts/build/build-docs.py" --check
run_check "global setup backup"   bash "$REPO_DIR/tests/setup-global.sh"
run_check "external skill sync"    bash "$REPO_DIR/tests/sync-external-skills.sh"
run_check "Claude HCOM hooks"     bash "$REPO_DIR/tests/claude-hcom-hooks.sh"
run_check "HCOM acknowledgement guard" bash "$REPO_DIR/tests/hcom-ack-guard.sh"
run_check "no-pager guard"        bash "$REPO_DIR/tests/no-pager-guard.sh"
run_check "runaway-process guard" bash "$REPO_DIR/tests/runaway-process-guard.sh"
run_check "manual-command guard" bash "$REPO_DIR/tests/manual-command-guard.sh"
run_check "tool-call checkpoint"  bash "$REPO_DIR/tests/tool-call-checkpoint.sh"
run_check "commit-message guard"  bash "$REPO_DIR/tests/commit-message-guard.sh"
run_check "search boundaries"     bash "$REPO_DIR/tests/search-boundaries.sh"
run_check "project setup"         bash "$REPO_DIR/tests/setup-project.sh"
run_check "friction logging"      bash "$REPO_DIR/tests/friction-logging.sh"
run_check "dead path refs"        project-checks-markdown-claims --mode paths
run_check "setup drift"           python3 "$REPO_DIR/scripts/validate/check-setup-drift.py"
run_check "staleness"             python3 "$REPO_DIR/scripts/validate/check-staleness.py"
run_check "staleness regression"  python3 "$REPO_DIR/tests/check-staleness.py"

cli_group_end

printf '\n'
if [ "$FAILED_CHECKS" -gt 0 ]; then
	cli_status error "$FAILED_CHECKS validation check(s) failed"
	exit 1
fi

cli_status success "All checks passed"
