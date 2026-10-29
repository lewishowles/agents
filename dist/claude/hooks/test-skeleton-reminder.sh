#!/usr/bin/env bash
# Suggests creating a matching test file when Claude edits an implementation
# file that has no test alongside it. Fires before Write and Edit tool calls.
# Only activates when the project has a recognisable test runner installed,
# so it stays silent in projects without a test setup.

set -euo pipefail

command -v jq &>/dev/null || exit 0

# The hook payload for the file Claude is about to edit.
input=$(cat)
# The path of the file Claude is about to edit, from the hook payload.
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

[ -z "$file_path" ] && exit 0

# The file name, used to spot test files and to label the reminder.
filename=$(basename "$file_path")
# The file extension, which decides whether the file needs a test and where its tests live.
extension="${filename##*.}"

# Checks whether a path follows test-file naming or directory conventions for
# JS, TS, Vue or Swift projects.
# Returns 0 for a test file, or 1 otherwise.
#
# @param  {string}  path
#     Path to the file being edited.
# @param  {string}  name
#     Basename of the file (used for pattern matching).
is_test_file() {
	# The edited file's full path.
	local path="$1"
	# The edited file's basename.
	local name="$2"

	[[ "$name" =~ \.(test|spec)\.(js|ts|tsx|vue)$ ]] && return 0
	[[ "$name" =~ \.(pw|ct|cy|e2e)\.(js|ts|tsx)$ ]] && return 0
	[[ "$name" =~ Tests?\.(swift|js|ts)$ ]] && return 0
	[[ "$path" =~ /(__tests__|test|tests|e2e)/ ]] && return 0

	return 1
}

# Checks whether the edited file has a testable implementation extension.
# Reads $extension from the outer scope.
# Returns 0 for a testable extension, or 1 otherwise.
is_implementation_file() {
	case "$extension" in
		js|ts|tsx|vue|swift) return 0 ;;
		*) return 1 ;;
	esac
}

# Checks whether the project in the current folder has a recognisable test setup.
# For Swift files it looks for a Tests folder or Package.swift; otherwise it looks
# for Vitest, Jest, Playwright or Cypress in the package.json scripts or dependencies.
# Reads $extension from the outer scope.
# Returns 0 when a test setup is found, or a non-zero status otherwise.
has_test_stack() {
	if [ "$extension" = "swift" ]; then
		[ -d "Tests" ] || [ -f "Package.swift" ]
		return
	fi

	[ -f "package.json" ] || return 1

	if command -v jq &>/dev/null; then
		jq -e '
			[
				.scripts,
				.dependencies,
				.devDependencies
			]
			| map(select(. != null))
			| add
			| tostring
			| test("vitest|jest|playwright|cypress"; "i")
		' package.json >/dev/null 2>&1
	else
		grep -qiE 'vitest|jest|playwright|cypress' package.json
	fi
}

# Prints candidate test file paths for a given implementation file, using
# conventional locations based on its extension and directory layout.
#
# @param  {string}  path
#     Path to the implementation file.
test_candidates() {
	# The implementation file that needs a matching test.
	local path="$1"
	# The implementation file's containing folder.
	local dir
	# The implementation file's name without its extension.
	local base

	dir=$(dirname "$path")
	base=$(basename "$path")
	base="${base%.*}"

	case "$extension" in
		js|ts|tsx|vue)
			printf '%s/%s.test.%s\n' "$dir" "$base" "$extension"
			printf '%s/%s.spec.%s\n' "$dir" "$base" "$extension"
			printf '%s/__tests__/%s.test.%s\n' "$dir" "$base" "$extension"
			;;
		swift)
			printf 'Tests/%sTests.swift\n' "$base"
			printf '%s/%sTests.swift\n' "$dir" "$base"
			;;
	esac
}

# Checks whether any candidate test path for $file_path already exists on disk.
# Reads $file_path from the outer scope.
# Returns 0 when a matching test exists, or 1 otherwise.
matching_test_exists() {
	# One suggested test path checked for an existing file.
	local candidate

	while IFS= read -r candidate; do
		[ -f "$candidate" ] && return 0
	done < <(test_candidates "$file_path")

	return 1
}

if ! is_implementation_file || is_test_file "$file_path" "$filename" || ! has_test_stack || matching_test_exists; then
	exit 0
fi

# The first conventional test path suggested for the edited file.
first_candidate=$(test_candidates "$file_path" | sed -n '1p')
# The suggested test path, relative to the project when it sits inside it.
display_candidate="${first_candidate#"$PWD"/}"

jq -n \
	--arg ctx "TEST REMINDER (${filename}): This project has a test setup, but I couldn't find a matching test file. Add or update one alongside this implementation, for example ${display_candidate}." \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
