#!/usr/bin/env bash
# Ensures the calling script and its child scripts use Bash 4 or newer.

# Runs the calling script again under a suitable Bash, or explains how to install one.
#
# @param  {string}  ...
#     The caller's arguments to pass on when restarting it.
require_bash() {
	if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
		# Clear the restart marker so scripts started from here can restart themselves too.
		unset REQUIRE_BASH_REEXECUTED
		return 0
	fi

	# Restart at most once, so a Bash that passes the version check but still runs
	# as old Bash cannot restart the script forever.
	if [ "${REQUIRE_BASH_REEXECUTED:-0}" != "1" ]; then
		# A colon-separated override lets tests replace the normal candidate list.
		local candidates
		if [ "${REQUIRE_BASH_CANDIDATES+x}" ]; then
			candidates="$REQUIRE_BASH_CANDIDATES"
		else
			candidates="/opt/homebrew/bin/bash:/usr/local/bin/bash:$(command -v bash || true)"
		fi

		# The Bash executable being checked before restarting the caller.
		local candidate
		# The candidates not yet checked.
		local remaining="$candidates"
		while [ -n "$remaining" ]; do
			candidate="${remaining%%:*}"
			if [ "$candidate" = "$remaining" ]; then
				remaining=""
			else
				remaining="${remaining#*:}"
			fi

			# The candidate expands its own Bash version in this probe.
			# shellcheck disable=SC2016
			if [ -x "$candidate" ] && [ ! "$candidate" -ef "$BASH" ] &&
				"$candidate" -c 'test "${BASH_VERSINFO[0]}" -ge 4' >/dev/null 2>&1; then
				export REQUIRE_BASH_REEXECUTED=1
				PATH="$(dirname "$candidate"):$PATH"
				export PATH
				exec "$candidate" "$0" "$@"
			fi
		done
	fi

	printf 'Bash 4 or newer is required. Install it with: brew install bash\n' >&2
	exit 1
}

require_bash "$@"
