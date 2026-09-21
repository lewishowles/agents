#!/usr/bin/env bash
# Checks every SKILL.md under skills/: it opens with front matter that has a
# name and a description, the name matches its folder, and no two skills share
# a name.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

if [ ! -d "$REPO_DIR/skills" ]; then
	validate_fail "Missing skills directory: $REPO_DIR/skills"
	validate_finish
fi

# Skill names already seen, used to report duplicates.
declare -A SKILL_NAMES=()
# The first SKILL.md path for each name, so a duplicate report names both files.
declare -A SKILL_PATHS=()

while IFS= read -r -d '' skill_file; do
	dir_name=$(basename "$(dirname "$skill_file")")  # The folder name the skill name must match.

	# Parse the front matter once and print three fields split by the unit
	# separator character: whether it opens and closes with ---, the name, and 1
	# when the description is not empty.
	metadata=$(awk '
		BEGIN {
			valid = 1
			in_front_matter = 0
			closed = 0
			has_description = 0
		}

		NR == 1 {
			if ($0 == "---") {
				in_front_matter = 1
			} else {
				valid = 0
			}
			next
		}

		valid && in_front_matter && !closed && $0 == "---" {
			closed = 1
			in_front_matter = 0
			next
		}

		valid && in_front_matter && !closed && $0 ~ /^name:[[:space:]]*/ {
			name = $0
			sub(/^name:[[:space:]]*/, "", name)
			gsub(/[[:space:]]+$/, "", name)
		}

		valid && in_front_matter && !closed && $0 ~ /^description:[[:space:]]*/ {
			description = $0
			sub(/^description:[[:space:]]*/, "", description)
			gsub(/[[:space:]]+$/, "", description)
			if (description != "" && description != "\"\"" && description != "\x27\x27") {
				has_description = 1
			}
		}

		END {
			if (!closed) {
				valid = 0
			}
			print (valid ? "true" : "false") "\037" name "\037" has_description
		}
	' "$skill_file")
	# has_front_matter, name and has_description hold the three parsed fields.
	# The fields are split on the unit separator rather than a tab, because read
	# collapses consecutive tabs and an empty name would shift the later fields.
	IFS=$'\037' read -r has_front_matter name has_description <<< "$metadata"

	if [ "$has_front_matter" != "true" ]; then
		validate_fail "Missing or invalid front matter: $skill_file"
		continue
	fi

	if [ -z "$name" ]; then
		validate_fail "Missing 'name' in $skill_file"
		continue
	fi

	if [ "$has_description" != "1" ]; then
		validate_fail "Missing 'description' in $skill_file"
	fi

	if [ "$name" != "$dir_name" ]; then
		validate_fail "name '$name' does not match directory '$dir_name'"
	fi

	if [ -n "${SKILL_NAMES[$name]+_}" ]; then
		validate_fail "Duplicate skill name '$name': $skill_file and ${SKILL_PATHS[$name]}"
	else
		SKILL_NAMES["$name"]=1
		SKILL_PATHS["$name"]="$skill_file"
	fi
done < <(find "$REPO_DIR/skills" -type f -name "SKILL.md" -print0 | sort -z)

validate_finish
