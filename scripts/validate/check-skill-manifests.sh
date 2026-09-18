#!/usr/bin/env bash
# Validates skill manifests and generated skill files.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

validate_require_jq

VALID_CAPS=("fileTriggering" "promptTriggering")
VALID_TARGETS=("claude" "codex")

declare -A SKILL_NAMES
while IFS= read -r -d '' manifest; do
	name=$(jq -r '.name // empty' "$manifest")
	if [ -n "$name" ]; then
		SKILL_NAMES["$name"]=1
	fi
done < <(find "$REPO_DIR/src/skills" -name "skill.json" -print0 | sort -z)

SKILL_COUNT=0

while IFS= read -r -d '' manifest; do
	dir=$(dirname "$manifest")
	dir_name=$(basename "$dir")

	if ! jq empty "$manifest" 2>/dev/null; then
		validate_fail "Invalid JSON: $manifest"
		continue
	fi

	name=$(jq -r '.name // empty' "$manifest")
	if [ -z "$name" ]; then
		validate_fail "Missing 'name': $manifest"
		continue
	fi

	if [ -z "$(jq -r '.description // empty' "$manifest")" ]; then
		validate_fail "Missing 'description' in $name"
	fi

	needs_when=$(jq -r '
		(.when // "") as $when
		| (if has("index") then .index else true end) as $idx
		| (.targets // []) as $t
		| if ($when != "") then "no"
			elif ($idx == false) then "no"
			elif (($t | length) > 0) and (($t | index("claude")) == null) then "no"
			else "yes"
			end
	' "$manifest")
	if [ "$needs_when" = "yes" ]; then
		validate_fail "Missing 'when' in $name (add one, set \"index\": false, or exclude claude from targets)"
	fi

	title=$(jq -r '.title // empty' "$manifest")
	if [ -n "$title" ] && [ "$title" = "$name" ]; then
		validate_fail "title should be human-readable, not identical to name, in $name"
	fi

	if [ "$name" != "$dir_name" ]; then
		validate_fail "name '$name' does not match directory '$dir_name'"
	fi

	while IFS= read -r cap; do
		if ! validate_is_valid "$cap" "${VALID_CAPS[@]}"; then
			validate_fail "Unknown capability '$cap' in $name"
		fi
	done < <(jq -r '.capabilities // {} | keys[]' "$manifest")

	while IFS= read -r tgt; do
		if ! validate_is_valid "$tgt" "${VALID_TARGETS[@]}"; then
			validate_fail "Unknown target '$tgt' in $name"
		fi
	done < <(jq -r '.targets // [] | .[]' "$manifest")

	while IFS= read -r dep; do
		if [ -z "${SKILL_NAMES[$dep]+_}" ]; then
			validate_fail "Unresolved dependency '$dep' in $name"
		fi
	done < <(jq -r '.dependencies // [] | .[]' "$manifest")

	if [ "$name" != "global-rules" ] && [ ! -f "$dir/SKILL.body.md" ]; then
		validate_fail "Missing SKILL.body.md for $name"
	fi

	generated_skill="$REPO_DIR/dist/skills/$name/SKILL.md"
	if [ ! -f "$generated_skill" ]; then
		validate_fail "Missing dist/skills/$name/SKILL.md (run scripts/sync.sh)"
	fi

	explicit_only=$(jq -r '.explicitInvocationOnly // false' "$manifest")
	codex_enabled=$(jq -r '(.targets // ["codex"]) | index("codex") != null' "$manifest")
	if [ "$explicit_only" = "true" ] && [ "$codex_enabled" = "true" ] && [ ! -f "$REPO_DIR/dist/skills/$name/agents/openai.yaml" ]; then
		validate_fail "Missing dist/skills/$name/agents/openai.yaml for explicitInvocationOnly skill $name (run scripts/sync.sh)"
	fi

	if [ -f "$dir/SKILL.md" ]; then
		validate_fail "Generated SKILL.md must not exist in source directory for $name"
	fi

	SKILL_COUNT=$((SKILL_COUNT + 1))
done < <(find "$REPO_DIR/src/skills" -name "skill.json" -print0 | sort -z)

validate_finish
