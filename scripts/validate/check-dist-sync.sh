#!/usr/bin/env bash
# Checks dist/claude/CLAUDE.md and dist/codex/AGENTS.md against a fresh rebuild
# from source, so content drift (not just missing files) is caught the same way
# check-hook-sync.sh catches hook drift.

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/lib/validation-helpers.sh"

REAL_REPO_DIR="$REPO_DIR"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Mirror only the inputs needed by the CLAUDE/AGENTS assembly at the same
# relative paths, so REPO_DIR resolves to $TMP_DIR inside the copied helper.
mkdir -p "$TMP_DIR/src/rules" "$TMP_DIR/src/adapters/codex" "$TMP_DIR/scripts/lib" \
	"$TMP_DIR/src/fragments/claude" "$TMP_DIR/src/fragments/codex" "$TMP_DIR/dist/claude" "$TMP_DIR/dist/codex"

cp "$REAL_REPO_DIR/src/rules/"*.md "$TMP_DIR/src/rules/"
cp "$REAL_REPO_DIR/src/fragments/claude/header.md" "$REAL_REPO_DIR/src/fragments/claude/subagent-delegation.md" "$TMP_DIR/src/fragments/claude/"
cp "$REAL_REPO_DIR/src/fragments/codex/"*.md "$TMP_DIR/src/fragments/codex/"
cp "$REAL_REPO_DIR/src/adapters/codex/hooks.json" "$TMP_DIR/src/adapters/codex/"
cp "$REAL_REPO_DIR/scripts/lib/dist-targets.sh" "$TMP_DIR/scripts/lib/"

# Reassigns REPO_DIR only for the duration of this subshell, so dist-targets.sh
# builds CLAUDE_PARTS/CODEX_PARTS against the temp tree without leaking the
# override into the rest of this script.
(
	REPO_DIR="$TMP_DIR"
	source "$TMP_DIR/scripts/lib/dist-targets.sh"
	write_target "$CLAUDE_TARGET" "${CLAUDE_PARTS[@]}"
	write_target "$CODEX_TARGET" "${CODEX_PARTS[@]}"
)

if ! diff -q "$TMP_DIR/dist/claude/CLAUDE.md" "$REAL_REPO_DIR/dist/claude/CLAUDE.md" >/dev/null 2>&1; then
	validate_fail "dist/claude/CLAUDE.md out of sync with source (run scripts/sync.sh)"
fi

if ! diff -q "$TMP_DIR/dist/codex/AGENTS.md" "$REAL_REPO_DIR/dist/codex/AGENTS.md" >/dev/null 2>&1; then
	validate_fail "dist/codex/AGENTS.md out of sync with source (run scripts/sync.sh)"
fi

python3 -m json.tool "$TMP_DIR/src/adapters/codex/hooks.json" >/dev/null
cp "$TMP_DIR/src/adapters/codex/hooks.json" "$TMP_DIR/dist/codex/hooks.json"

if ! diff -q "$TMP_DIR/dist/codex/hooks.json" "$REAL_REPO_DIR/dist/codex/hooks.json" >/dev/null 2>&1; then
	validate_fail "dist/codex/hooks.json out of sync with source (run scripts/sync.sh)"
fi

validate_finish
