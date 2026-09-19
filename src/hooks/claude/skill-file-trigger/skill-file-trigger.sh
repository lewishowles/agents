#!/usr/bin/env bash
#
# skill-file-trigger — PreToolUse hook (Write|Edit)
#
# Tells Claude which skills to load before it writes or edits a file. The hook
# keeps its own list of patterns in skill-file-trigger.patterns.json, beside the
# real hook file, so skills can be copied without carrying hook settings. Each
# entry maps a skill name to:
#   filePatterns  — bash globs matched against the file name
#   pathPatterns  — text matched anywhere in the full file path
#
# A skill is only suggested when its folder exists in the skills directory, so
# the hook stays quiet about skills that are not installed.
#
# The installed hook is a symlink, so the pattern list is found by following the
# link back to the real file. Tests can use their own skills directory by setting
# SKILL_FILE_TRIGGER_SKILLS_DIR.
#
# Requires jq. Without it the hook exits quietly, so writes are never blocked.

command -v jq &>/dev/null || exit 0

script_path="${BASH_SOURCE[0]}" # Path used to invoke this hook, which may be a symlink.
while [[ -L "$script_path" ]]; do
	link_dir=$(cd -P "$(dirname "$script_path")" && pwd) # Directory containing the current symlink.
	script_path=$(readlink "$script_path") # Target path stored in the current symlink.
	if [[ "$script_path" != /* ]]; then
		script_path="$link_dir/$script_path"
	fi
done

script_dir=$(cd -P "$(dirname "$script_path")" && pwd) # Directory containing the real hook.
patterns_file="$script_dir/skill-file-trigger.patterns.json" # Pattern map used by the hook.
skills_dir="${SKILL_FILE_TRIGGER_SKILLS_DIR:-$HOME/.claude/skills}" # Installed Claude skill folders.

if [[ ! -f "$patterns_file" ]] || [[ ! -d "$skills_dir" ]]; then
	exit 0
fi

input=$(cat) # JSON payload received from Claude's PreToolUse event.
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null) # File path being edited.

if [[ -z "$file_path" ]]; then
	exit 0
fi

filename=$(basename "$file_path") # Basename used by filePatterns.
skills=() # Matching installed skill names.

# Use \x1f (ASCII unit separator) as field delimiter. It is not IFS whitespace,
# so consecutive occurrences are not collapsed and empty fields are preserved.
sep=$'\x1f'

while IFS="$sep" read -r skill_name file_patterns path_patterns; do
	if [[ ! -d "$skills_dir/$skill_name" ]]; then
		continue
	fi

	matched=false

	IFS=',' read -ra file_pattern_list <<< "$file_patterns"
	for pattern in "${file_pattern_list[@]}"; do
		if [[ -z "$pattern" ]]; then
			continue
		fi

		# shellcheck disable=SC2254
		case "$filename" in
		$pattern)
			matched=true
			break
			;;
		esac
	done

	if [[ "$matched" == false ]]; then
		IFS=',' read -ra path_pattern_list <<< "$path_patterns"
		for pattern in "${path_pattern_list[@]}"; do
			if [[ -z "$pattern" ]]; then
				continue
			fi

			if [[ "$file_path" == *"$pattern"* ]]; then
				matched=true
				break
			fi
		done
	fi

	if [[ "$matched" == true ]]; then
		skills+=("$skill_name")
	fi
done < <(
	jq -rn '
		inputs |
		to_entries[] |
		[.key, (.value.filePatterns // [] | join(",")), (.value.pathPatterns // [] | join(","))] |
		join("\u001f")
	' "$patterns_file" 2>/dev/null
)

if [[ ${#skills[@]} -eq 0 ]]; then
	exit 0
fi

readarray -t unique < <(printf '%s\n' "${skills[@]}" | sort -u)

jq -n \
	--arg ctx "SKILL REQUIREMENT (${filename}): Before editing, assess these matched skills: ${unique[*]}. Load and apply every skill relevant to the intended change." \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
