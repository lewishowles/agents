#!/usr/bin/env bash
# Checks every SKILL.md under skills/: it opens with front matter that has a
# name and a description, uses allowed top-level keys, the name matches its
# folder, and no two skills share a name.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

# The front-matter keys defined by the Agent Skills standard.
STANDARD_FRONT_MATTER_KEYS=(
	name
	description
	license
	compatibility
	metadata
	allowed-tools
)

# Keys outside the standard that a runtime still reads. Claude uses
# disable-model-invocation to keep project-review-commits,
# project-review-patches, and project-review-progress user-invoked only.
RUNTIME_FRONT_MATTER_EXTENSIONS=(
	disable-model-invocation
)

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

	# Parse the front matter once and print four fields split by the unit
	# separator character: whether it opens and closes with ---, the name, 1
	# when the description is not empty, and its top-level keys.
	metadata=$(awk '
		BEGIN {
			valid = 1
			in_front_matter = 0
			closed = 0
			has_description = 0
			front_matter_keys = ""
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

		valid && in_front_matter && !closed && $0 ~ /^[^[:space:]][^:]*:[[:space:]]*/ {
			key = $0
			sub(/:.*/, "", key)
			gsub(/[[:space:]]+$/, "", key)
			if (front_matter_keys == "") {
				front_matter_keys = key
			} else {
				front_matter_keys = front_matter_keys "," key
			}
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
			print (valid ? "true" : "false") "\037" name "\037" has_description "\037" front_matter_keys
		}
	' "$skill_file")
	# These fields hold the parser's front-matter status, name, description status,
	# and comma-separated top-level keys.
	# The fields are split on the unit separator rather than a tab, because read
	# collapses consecutive tabs and an empty name would shift the later fields.
	IFS=$'\037' read -r has_front_matter name has_description front_matter_keys <<< "$metadata"

	if [ "$has_front_matter" != "true" ]; then
		validate_fail "Missing or invalid front matter: $skill_file"
		continue
	fi

	# Every top-level key must be a standard key or an allowed runtime extension,
	# so a copied skill still loads in any runtime that follows the standard.
	IFS=',' read -r -a front_matter_key_list <<< "$front_matter_keys"

	for front_matter_key in "${front_matter_key_list[@]}"; do
		if ! validate_is_valid "$front_matter_key" "${STANDARD_FRONT_MATTER_KEYS[@]}" "${RUNTIME_FRONT_MATTER_EXTENSIONS[@]}"; then
			validate_fail "Unknown front matter key '$front_matter_key' in $skill_file"
		fi
	done

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
