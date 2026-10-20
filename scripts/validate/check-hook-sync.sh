#!/usr/bin/env bash
# Checks that the dist hook copies and the Claude code-style rule match their sources.

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
