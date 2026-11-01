#!/usr/bin/env bash
# Runs repository validation checks in a stable order; --quick skips the setup and doctor end-to-end tests.

set -euo pipefail

# The folder containing this script, regardless of the caller's location.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository whose generated files and configuration are checked.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=SCRIPTDIR/lib/require-bash.sh
source "$SCRIPT_DIR/lib/require-bash.sh"
source "$REPO_DIR/scripts/lib/script-output.sh"

# The number of validation commands that reported a failure.
FAILED_CHECKS=0
# Whether to skip the setup and doctor end-to-end tests.
QUICK=false
# The wall-clock time when the run started, in seconds since the epoch. Bash 4
# has no sub-second clock, so Python reads it.
RUN_STARTED_AT=$(python3 -c 'import time; print(time.time())')

if [ "$#" -gt 0 ]; then
	if [ "$#" -ne 1 ] || [ "$1" != "--quick" ]; then
		printf 'Usage: %s [--quick]\n' "$0" >&2
		exit 2
	fi
	QUICK=true
fi

# Holds the elapsed time Bash reports for the check that just ran.
TIMING_FILE=$(mktemp)
trap 'rm -f "$TIMING_FILE"' EXIT

cli_section "Validation" "Run repository checks"

cli_group_begin "Checks"

# Runs a command as a named validation check.
# Records the result in the active group. Passing checks stay silent and are
# reported in the group summary; failures print their output and a ✗ row with
# the time the check took. Set CLI_STYLE_VERBOSE=1 to show a row for every
# check as it runs, with each passing check's time.
#
# @param  {string}  label
#     Human-readable name recorded for the check.
# @param  {string}  ...
#     Command and arguments to execute.
run_check() {
	# The human-readable name shown for the current validation command.
	local label="$1"
	# The command output, printed when the check fails or when the staleness check
	# reports stale files.
	local output
	# The elapsed time displayed beside this check's result.
	local duration
	# The command's exit status, caught so a failing check is reported instead of
	# stopping the script.
	local check_status=0
	# Makes the time keyword print only elapsed seconds, to one decimal place.
	local TIMEFORMAT='%1R'
	shift
	if [ "${CLI_STYLE_VERBOSE:-0}" = "1" ]; then
		cli_status info "Checking" "$label"
	fi
	{ time output=$("$@" 2>&1); } 2> "$TIMING_FILE" || check_status=$?
	IFS= read -r duration < "$TIMING_FILE"
	duration="${duration}s"
	if [ "$check_status" -eq 0 ]; then
		if [ "$label" = "staleness" ] && [ -n "$output" ]; then
			printf '%s\n' "$output"
		fi
		cli_group_status success "$label" "$duration"
	else
		if [ -n "$output" ]; then
			printf '%s\n' "$output" >&2
		fi
		cli_group_status error "$label" "failed after $duration"
		FAILED_CHECKS=$((FAILED_CHECKS + 1))
	fi
}

run_check "skill manifests"       bash "$REPO_DIR/scripts/validate/check-skill-manifests.sh"
run_check "skill list and links"  bash "$REPO_DIR/scripts/validate/check-skill-list.sh"
run_check "hook manifests"        bash "$REPO_DIR/scripts/validate/check-hook-manifests.sh"
run_check "generated files"       bash "$REPO_DIR/scripts/validate/check-generated-files.sh"
run_check "hook sync"             bash "$REPO_DIR/scripts/validate/check-hook-sync.sh"
run_check "dist sync"             bash "$REPO_DIR/scripts/validate/check-dist-sync.sh"
run_check "docs tables"           python3 "$REPO_DIR/scripts/build/build-docs.py" --check
run_check "agent-tools helpers"   bash "$REPO_DIR/scripts/validate/check-agent-tools-contract.sh"
if [ "$QUICK" = true ]; then
	cli_group_status skipped "setup and doctor tests (quick mode)"
else
	run_check "setup backup"          bash "$REPO_DIR/tests/setup.sh"
	run_check "setup doctor"          bash "$REPO_DIR/tests/doctor.sh"
fi
run_check "script output"         bash "$REPO_DIR/tests/script-output.sh"
run_check "Bash version guard"    bash "$REPO_DIR/tests/bash-guard.sh"
run_check "HCOM acknowledgement guard" bash "$REPO_DIR/tests/hcom-ack-guard.sh"
run_check "HCOM recipient guard" bash "$REPO_DIR/tests/hcom-recipient-guard.sh"
run_check "trash guard"          bash "$REPO_DIR/tests/trash-guard.sh"
run_check "no-pager guard"        bash "$REPO_DIR/tests/no-pager-guard.sh"
run_check "runaway-process guard" bash "$REPO_DIR/tests/runaway-process-guard.sh"
run_check "manual-command guard" bash "$REPO_DIR/tests/manual-command-guard.sh"
run_check "tool-call checkpoint"  bash "$REPO_DIR/tests/tool-call-checkpoint.sh"
run_check "commit-message guard"  bash "$REPO_DIR/tests/commit-message-guard.sh"
run_check "search boundaries"     bash "$REPO_DIR/tests/search-boundaries.sh"
run_check "friction logging"      bash "$REPO_DIR/tests/friction-logging.sh"
run_check "dead path refs"        doc-paths --project-dir "$REPO_DIR"
run_check "staleness"             python3 "$REPO_DIR/scripts/validate/check-staleness.py"
run_check "staleness regression"  python3 "$REPO_DIR/tests/check-staleness.py"

cli_group_end

# The elapsed time displayed on the closing line.
RUN_DURATION=$(python3 -c 'import sys, time; print(f"{time.time() - float(sys.argv[1]):.1f}s")' "$RUN_STARTED_AT")

printf '\n'
if [ "$FAILED_CHECKS" -gt 0 ]; then
	cli_status error "$FAILED_CHECKS validation check(s) failed in $RUN_DURATION"
	exit 1
fi

cli_status success "All checks passed in $RUN_DURATION"
