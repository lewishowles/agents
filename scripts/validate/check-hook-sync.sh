#!/usr/bin/env bash
# Checks that the dist hook copies and the Claude code-style rule match their sources,
# and that every file in the dist hooks folders still has a source.

set -euo pipefail

# shellcheck source=SCRIPTDIR/../lib/validation-helpers.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

validate_require_jq

while IFS= read -r -d '' manifest; do
	# The folder containing this hook manifest.
	dir=$(dirname "$manifest")
	# The hook name used to find its source script.
	name=$(jq -r '.name' "$manifest")

	for src in "$dir/${name}.sh" "$dir/${name}"; do
		if [ ! -f "$src" ]; then
			continue
		fi

		# The dist/ copy of this source file, which must match it.
		dst="$REPO_DIR/dist/claude/hooks/$(basename "$src")"

		if [ ! -f "$dst" ]; then
			validate_fail "dist/claude/hooks/$(basename "$src") missing (run scripts/sync.sh)"
		elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
			validate_fail "dist/claude/hooks/$(basename "$src") out of sync with source (run scripts/sync.sh)"
		fi
	done
done < <(find "$REPO_DIR/src/hooks/claude" -name "hook.json" -print0 | sort -z)

while IFS= read -r -d '' shared_file; do
	# The file name this shared hook has in both dist/claude/hooks and dist/codex/hooks.
	shared_name=$(basename "$shared_file")

	for destination in "$REPO_DIR/dist/claude/hooks/$shared_name" "$REPO_DIR/dist/codex/hooks/$shared_name"; do
		if [ ! -f "$destination" ]; then
			validate_fail "${destination#"$REPO_DIR/"} missing (run scripts/sync.sh)"
		elif ! diff -q "$shared_file" "$destination" >/dev/null 2>&1; then
			validate_fail "${destination#"$REPO_DIR/"} out of sync with source (run scripts/sync.sh)"
		fi
	done
done < <(find "$REPO_DIR/src/hooks/shared" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.md' \) -print0 | sort -z)

# Reports whether sync.sh would still copy a file with this name into a generated hooks folder.
# Claude hook files come from a hook folder or the shared folder; Codex hook files come only from the shared folder.
#
# @param  {string}  hook_target
#     The generated hooks folder being checked: claude or codex.
# @param  {string}  generated_name
#     The name of the file in that folder.
has_hook_source() {
	# The generated hooks folder being checked.
	local hook_target="$1"
	# The file name to look for among the hook sources.
	local generated_name="$2"
	# A file in one of the Claude hook folders that may share the name.
	local source_file

	if [[ "$generated_name" == *.sh || "$generated_name" == *.md ]] && [[ -f "$REPO_DIR/src/hooks/shared/$generated_name" ]]; then
		return 0
	fi

	if [[ "$hook_target" != claude || "$generated_name" == hook.json ]]; then
		return 1
	fi

	for source_file in "$REPO_DIR"/src/hooks/claude/*/"$generated_name"; do
		if [[ -f "$source_file" ]]; then
			return 0
		fi
	done

	return 1
}

# The generated hooks folder being checked for files whose source was deleted without running sync.sh.
for hook_target in claude codex; do
	# A file in that generated hooks folder.
	while IFS= read -r -d '' generated_file; do
		if ! has_hook_source "$hook_target" "$(basename "$generated_file")"; then
			validate_fail "${generated_file#"$REPO_DIR/"} has no source (run scripts/sync.sh)"
		fi
	done < <(find "$REPO_DIR/dist/$hook_target/hooks" -maxdepth 1 -type f -print0 | sort -z)
done

# The installed copy that sync.sh writes.
rule="$REPO_DIR/dist/claude/rules/code-style.md"
# The hand-written rule that sync.sh copies.
rule_source="$REPO_DIR/src/adapters/claude/rules/code-style.md"

if [ ! -f "$rule" ]; then
	validate_fail "dist/claude/rules/code-style.md missing (run scripts/sync.sh)"
elif ! diff -q "$rule_source" "$rule" >/dev/null 2>&1; then
	validate_fail "dist/claude/rules/code-style.md out of sync with source (run scripts/sync.sh)"
fi

validate_finish
