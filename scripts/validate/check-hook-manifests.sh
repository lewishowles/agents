#!/usr/bin/env bash
# Validates Claude hook manifests and executable hook scripts.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

validate_require_jq

# The failure modes accepted by Claude hook manifests.
VALID_FAILURE_MODES=("block" "ignore" "silent")

# The number of manifests that passed the JSON and name checks.
HOOK_COUNT=0

while IFS= read -r -d '' manifest; do
	# The folder containing this hook manifest.
	dir=$(dirname "$manifest")
	# The folder name that the manifest's hook name must match.
	dir_name=$(basename "$dir")

	if ! jq empty "$manifest" 2>/dev/null; then
		validate_fail "Invalid JSON: $manifest"
		continue
	fi

	# The hook name declared by this manifest.
	name=$(jq -r '.name // empty' "$manifest")
	if [ -z "$name" ]; then
		validate_fail "Missing 'name': $manifest"
		continue
	fi

	if [ "$name" != "$dir_name" ]; then
		validate_fail "name '$name' does not match directory '$dir_name'"
	fi

	if [ -z "$(jq -r '.runtime // empty' "$manifest")" ]; then
		validate_fail "Missing 'runtime' in $name"
	fi

	if [ -z "$(jq -r '.description // empty' "$manifest")" ]; then
		validate_fail "Missing 'description' in $name"
	fi

	# The failure mode declared by this manifest.
	failure_mode=$(jq -r '.failureMode // empty' "$manifest")
	if [ -z "$failure_mode" ]; then
		validate_fail "Missing 'failureMode' in $name"
	elif ! validate_is_valid "$failure_mode" "${VALID_FAILURE_MODES[@]}"; then
		validate_fail "Unknown failureMode '$failure_mode' in $name"
	fi

	# The executable file associated with this hook, when one exists.
	hook_script=""
	if [ -f "$dir/${name}.sh" ]; then
		hook_script="$dir/${name}.sh"
	fi
	if [ -f "$dir/${name}" ]; then
		hook_script="$dir/${name}"
	fi
	if [ -z "$hook_script" ] && [ -f "$REPO_DIR/src/hooks/shared/${name}.sh" ]; then
		hook_script="$REPO_DIR/src/hooks/shared/${name}.sh"
	fi

	# Whether the manifest sets a command at the top level or on every one of its events.
	command_configured=$(jq -r '
		(.command | (type == "string" and length > 0))
		or (([.events[]? | (.command | (type == "string" and length > 0))]) | length > 0 and all)
	' "$manifest")

	if [ -z "$hook_script" ]; then
		if [ "$command_configured" != "true" ]; then
			validate_fail "No hook script or command found for $name"
		fi
	elif [ ! -x "$hook_script" ]; then
		validate_fail "Hook script not executable: $hook_script"
	fi

	HOOK_COUNT=$((HOOK_COUNT + 1))
done < <(find "$REPO_DIR/src/hooks/claude" -name "hook.json" -print0 | sort -z)

validate_finish
