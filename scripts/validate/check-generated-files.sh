#!/usr/bin/env bash
# Checks that required generated output files exist.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

# The generated files required for a valid installation.
GENERATED_FILES=(
	"dist/claude/CLAUDE.md"
	"dist/claude/settings.json"
)

for file in "${GENERATED_FILES[@]}"; do
	if [ ! -f "$REPO_DIR/$file" ]; then
		validate_fail "Missing generated file: $file (run scripts/sync.sh)"
	fi
done

validate_finish
