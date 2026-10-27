#!/usr/bin/env bash
# Auto-format files after Claude edits them.
# Runs oxfmt if installed; skips silently if not — so it only activates
# in projects that have opted in by installing oxfmt.

# The file Claude edited, taken from the hook payload.
file_path=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -z "$file_path" ]]; then
	exit 0
fi

# The edited file's extension, used to select files oxfmt handles.
ext="${file_path##*.}"

case "$ext" in
	js|mjs|vue|css|json|md|html)
		;;
	*)
		exit 0
		;;
esac

if ! command -v oxfmt &>/dev/null; then
	exit 0
fi

oxfmt "$file_path" 2>/dev/null

exit 0
