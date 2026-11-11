#!/usr/bin/env bash
# Runs repository validation checks side by side and reports them in a stable order; --quick skips the setup and doctor end-to-end tests.

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

# The temporary folder where each check writes its output, exit status and elapsed time.
RESULT_DIR=$(mktemp -d)
# The labels for checks in their reporting order.
CHECK_LABELS=()
# The process IDs of checks running side by side.
CHECK_PIDS=()

# Gives each background check a process group so cleanup can stop its children.
# Job control also stops Bash giving background checks empty input, so each check
# reads from /dev/null below; otherwise a check that read input in a terminal
# would be paused and validation would hang.
set -m

# Stops unfinished checks and removes their temporary results.
cleanup() {
	# The process ID of a check that may still be running.
	local check_pid

	for check_pid in ${CHECK_PIDS[@]+"${CHECK_PIDS[@]}"}; do
		kill -TERM -- "-$check_pid" 2> /dev/null || true
	done
	for check_pid in ${CHECK_PIDS[@]+"${CHECK_PIDS[@]}"}; do
		wait "$check_pid" 2> /dev/null || true
	done
	rm -rf "$RESULT_DIR"
}

trap cleanup EXIT
# Turns an interrupt or terminate signal into a normal exit, so the cleanup above
# still runs and the script reports the usual signal exit status.
trap 'exit 130' INT
trap 'exit 143' TERM

cli_section "Validation" "Run repository checks"

cli_group_begin "Checks" true

# Runs one check and writes its output, status and elapsed time to separate files.
#
# @param  {integer}  index
#     The check's position in the reporting order.
# @param  {string}  ...
#     Command and arguments to execute.
run_check_command() {
	# The check's position in the reporting order.
	local index="$1"
	# The exit status written for the reporting step.
	local check_status=0
	# Makes the time keyword write elapsed seconds to three decimal places.
	local TIMEFORMAT='%3R'
	shift

	{ time "$@" < /dev/null > "$RESULT_DIR/$index.output" 2>&1; } 2> "$RESULT_DIR/$index.time" || check_status=$?
	printf '%s\n' "$check_status" > "$RESULT_DIR/$index.status"
}

# Starts a named check and records where its result belongs in the report.
#
# @param  {string}  label
#     Human-readable name shown for the check.
# @param  {string}  ...
#     Command and arguments to execute.
start_check() {
	# The check's position in the reporting order.
	local index="${#CHECK_LABELS[@]}"
	# The human-readable name shown for the check.
	local label="$1"
	shift

	CHECK_LABELS+=("$label")
	run_check_command "$index" "$@" &
	CHECK_PIDS+=("$!")
}

# Waits for every side-by-side check before reporting or starting setup tests.
wait_for_checks() {
	# The process ID of a check to wait for.
	local check_pid

	for check_pid in ${CHECK_PIDS[@]+"${CHECK_PIDS[@]}"}; do
		wait "$check_pid" || true
	done
	CHECK_PIDS=()
}

# Prints one check's result row and any output, and counts a failure.
#
# @param  {integer}  index
#     The check's position in the reporting order.
report_check() {
	# The check's position in the reporting order.
	local index="$1"
	# The human-readable name shown for the check.
	local label="${CHECK_LABELS[$index]}"
	# The command output shown on failure or for a non-empty staleness result.
	local output=""
	# The elapsed time displayed beside the check's result.
	local duration="0"
	# A missing status file counts as a failed check.
	local check_status=1

	if [ -s "$RESULT_DIR/$index.status" ]; then
		IFS= read -r check_status < "$RESULT_DIR/$index.status"
	fi
	if [ -s "$RESULT_DIR/$index.time" ]; then
		IFS= read -r duration < "$RESULT_DIR/$index.time"
	fi
	if [ -f "$RESULT_DIR/$index.output" ]; then
		output=$(< "$RESULT_DIR/$index.output")
	fi

	# Rounds to one place here, because Bash's own one-place time format prints
	# "0.:" instead of "1.0" when the tenths round up to ten.
	printf -v duration '%.1f' "$duration"
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

# Runs one named check on its own and reports its result. The setup tests use
# this because they are slow and fail more often when the machine is busy.
#
# @param  {string}  label
#     Human-readable name shown for the check.
# @param  {string}  ...
#     Command and arguments to execute.
run_single_check() {
	# The check's position in the reporting order.
	local index="${#CHECK_LABELS[@]}"

	start_check "$@"
	wait_for_checks
	report_check "$index"
}

start_check "skill manifests"       bash "$REPO_DIR/scripts/validate/check-skill-manifests.sh"
start_check "skill list and links"  bash "$REPO_DIR/scripts/validate/check-skill-list.sh"
start_check "hook manifests"        bash "$REPO_DIR/scripts/validate/check-hook-manifests.sh"
start_check "generated files"       bash "$REPO_DIR/scripts/validate/check-generated-files.sh"
start_check "hook sync"             bash "$REPO_DIR/scripts/validate/check-hook-sync.sh"
start_check "dist sync"             bash "$REPO_DIR/scripts/validate/check-dist-sync.sh"
start_check "docs tables"           python3 "$REPO_DIR/scripts/build/build-docs.py" --check
start_check "agent-tools helpers"   bash "$REPO_DIR/scripts/validate/check-agent-tools-contract.sh"
# The position where the setup checks appear in the original report.
SETUP_INSERT_INDEX=${#CHECK_LABELS[@]}
start_check "script output"         bash "$REPO_DIR/tests/script-output.sh"
start_check "Bash version guard"    bash "$REPO_DIR/tests/bash-guard.sh"
start_check "HCOM acknowledgement guard" bash "$REPO_DIR/tests/hcom-ack-guard.sh"
start_check "HCOM recipient guard" bash "$REPO_DIR/tests/hcom-recipient-guard.sh"
start_check "trash guard"          bash "$REPO_DIR/tests/trash-guard.sh"
start_check "no-pager guard"        bash "$REPO_DIR/tests/no-pager-guard.sh"
start_check "runaway-process guard" bash "$REPO_DIR/tests/runaway-process-guard.sh"
start_check "manual-command guard" bash "$REPO_DIR/tests/manual-command-guard.sh"
start_check "tool-call checkpoint"  bash "$REPO_DIR/tests/tool-call-checkpoint.sh"
start_check "commit-message guard"  bash "$REPO_DIR/tests/commit-message-guard.sh"
start_check "search boundaries"     bash "$REPO_DIR/tests/search-boundaries.sh"
start_check "friction logging"      bash "$REPO_DIR/tests/friction-logging.sh"
start_check "dead path refs"        doc-paths --project-dir "$REPO_DIR"
start_check "staleness"             python3 "$REPO_DIR/scripts/validate/check-staleness.py"
start_check "staleness regression"  python3 "$REPO_DIR/tests/check-staleness.py"
# The number of checks started together, before full-mode setup checks are added.
QUICK_CHECK_COUNT=${#CHECK_LABELS[@]}

wait_for_checks

# Report the checks that come before the setup tests in the original report.
for ((index = 0; index < SETUP_INSERT_INDEX; index++)); do
	report_check "$index"
done

if [ "$QUICK" = true ]; then
	cli_group_status skipped "setup and doctor tests (quick mode)"
else
	run_single_check "setup backup" bash "$REPO_DIR/tests/setup.sh"
	run_single_check "setup doctor" bash "$REPO_DIR/tests/doctor.sh"
fi

for ((index = SETUP_INSERT_INDEX; index < QUICK_CHECK_COUNT; index++)); do
	report_check "$index"
done

cli_group_end

# The elapsed time displayed on the closing line.
RUN_DURATION=$(python3 -c 'import sys, time; print(f"{time.time() - float(sys.argv[1]):.1f}s")' "$RUN_STARTED_AT")

printf '\n'
if [ "$FAILED_CHECKS" -gt 0 ]; then
	cli_status error "$FAILED_CHECKS validation check(s) failed in $RUN_DURATION"
	exit 1
fi

cli_status success "All checks passed in $RUN_DURATION"
