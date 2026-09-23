#!/usr/bin/env bash
# Checks that the dist hook copies and the Claude code-style rule match their sources.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

validate_require_jq

STALE=0

while IFS= read -r -d '' manifest; do
	dir=$(dirname "$manifest")
	name=$(jq -r '.name' "$manifest")

	for src in "$dir/${name}.sh" "$dir/${name}"; do
		if [ ! -f "$src" ]; then
			continue
		fi

		dst="$REPO_DIR/dist/claude/hooks/$(basename "$src")"

		if [ ! -f "$dst" ]; then
			validate_fail "dist/claude/hooks/$(basename "$src") missing (run scripts/sync.sh)"
			STALE=$((STALE + 1))
		elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
			validate_fail "dist/claude/hooks/$(basename "$src") out of sync with source (run scripts/sync.sh)"
			STALE=$((STALE + 1))
		fi
	done
done < <(find "$REPO_DIR/src/hooks/claude" -name "hook.json" -print0 | sort -z)

while IFS= read -r -d '' shared_file; do
	shared_name=$(basename "$shared_file")

	for destination in "$REPO_DIR/dist/claude/hooks/$shared_name" "$REPO_DIR/dist/codex/hooks/$shared_name"; do
		if [ ! -f "$destination" ]; then
			validate_fail "${destination#"$REPO_DIR/"} missing (run scripts/sync.sh)"
			STALE=$((STALE + 1))
		elif ! diff -q "$shared_file" "$destination" >/dev/null 2>&1; then
			validate_fail "${destination#"$REPO_DIR/"} out of sync with source (run scripts/sync.sh)"
			STALE=$((STALE + 1))
		fi
	done
done < <(find "$REPO_DIR/src/hooks/shared" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.md' \) -print0 | sort -z)

rule="$REPO_DIR/dist/claude/rules/code-style.md"  # The installed copy that sync.sh writes.
rule_source="$REPO_DIR/src/adapters/claude/rules/code-style.md"  # The hand-written rule that sync.sh copies.

if [ ! -f "$rule" ]; then
	validate_fail "dist/claude/rules/code-style.md missing (run scripts/sync.sh)"
elif ! diff -q "$rule_source" "$rule" >/dev/null 2>&1; then
	validate_fail "dist/claude/rules/code-style.md out of sync with source (run scripts/sync.sh)"
fi

validate_finish
