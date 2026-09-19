#!/usr/bin/env bash
# Downloads and updates skills listed in external-skills.json.
# Each skill's configured upstream content target is overwritten on sync.
# SKILL.body.md remains the default target. A SYNC.md file records provenance
# and upstream SHA so unchanged skills can be skipped.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
MANIFEST="$REPO_DIR/external-skills.json"  # List of skills to sync, with URLs and metadata.

source "$REPO_DIR/scripts/lib/colours.sh"
source "$REPO_DIR/scripts/lib/cli-style-output.sh"

usage() {
	printf 'Usage: %s\n' "$(basename "$0")"
}

if [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

# Ensures commands and files needed for external skill sync are available.
require_sync_dependencies() {
	if ! command -v jq &>/dev/null; then
		cli_status error "sync-external-skills requires jq." "Install it with: brew install jq" >&2
		exit 1
	fi

	if ! command -v curl &>/dev/null; then
		cli_status error "sync-external-skills requires curl." >&2
		exit 1
	fi

	if [ ! -f "$MANIFEST" ]; then
		cli_status error "External skills manifest not found" "$MANIFEST" >&2
		exit 1
	fi
}

# Scans a downloaded skill file for patterns that warrant manual review before
# the skill is trusted. Prints a warning for each match but does not block.
#
# @param  {string}  file
#     Path to the downloaded file to inspect.
# @param  {string}  slug
#     Skill slug, used in warning messages.
vet_skill_file() {
	local file="$1"
	local slug="$2"
	local warnings=0

	if grep -qE '\b(rm\s+-rf|sudo\s|chmod\s+[0-7]*7[0-7]*)\b' "$file" 2>/dev/null; then
		cli_status warning "$slug" "contains potentially destructive shell commands (rm -rf / sudo / chmod 7xx)" >&2
		warnings=$((warnings + 1))
	fi

	if grep -qE '^\s*(curl|wget|fetch)\s+.*https?://(?!raw\.githubusercontent\.com|api\.github\.com)' "$file" 2>/dev/null; then
		cli_status warning "$slug" "contains network calls to external hosts" >&2
		warnings=$((warnings + 1))
	fi

	if grep -qiE '(AWS_SECRET|api_key|GITHUB_TOKEN|password|private_key)\s*=' "$file" 2>/dev/null; then
		cli_status warning "$slug" "references credential-like variable names" >&2
		warnings=$((warnings + 1))
	fi

	if [ "$warnings" -gt 0 ]; then
		cli_status warning "Review before use" "$file" >&2
	fi
}

# Strips YAML frontmatter from a skill file and writes the body to a target path.
#
# @param  {string}  input_file
#     Path to the downloaded SKILL.md with frontmatter.
# @param  {string}  output_file
#     Path to write the stripped body content.
strip_frontmatter() {
	local input_file="$1"
	local output_file="$2"

	python3 - "$input_file" "$output_file" <<'PYEOF'
import sys

content = open(sys.argv[1]).read()
lines = content.splitlines()
dashes = [i for i, line in enumerate(lines) if line.strip() == "---"]

body_start = dashes[1] + 1 if len(dashes) >= 2 else 0
while body_start < len(lines) and not lines[body_start].strip():
    body_start += 1

open(sys.argv[2], "w").write("\n".join(lines[body_start:]) + "\n")
PYEOF
}

# Downloads any reference files listed in a GitHub contents API response and
# writes them into the skill's references/ subdirectory.
#
# @param  {string}  references_api_url
#     GitHub API URL for the references directory.
# @param  {string}  target_dir
#     The skill directory to write references into.
fetch_references() {
	local references_api_url="$1"
	local target_dir="$2"

	local references_file
	references_file=$(mktemp)

	printf '  Fetching reference index\n'
	curl -fsSL "$references_api_url" -o "$references_file"
	mkdir -p "$target_dir/references"

	local total_references
	total_references=$(jq '[.[] | select(.type == "file")] | length' "$references_file")
	printf '  Fetching %s reference files\n' "$total_references"

	local reference_name reference_url
	while IFS=$'\t' read -r reference_name reference_url; do
		curl -fsSL "$reference_url" -o "$target_dir/references/$reference_name"
	done < <(jq -r '.[] | select(.type == "file") | [.name, .download_url] | @tsv' "$references_file")

	rm "$references_file"
}

# Downloads and installs a single external skill. Skips the download if the
# upstream SHA matches what was recorded during the last sync.
#
# @param  {string}  slug
#     Skill directory name and identifier.
# @param  {string}  group
#     Parent group directory, or empty for flat skills.
# @param  {string}  name
#     Human-readable skill name (used in SYNC.md).
# @param  {string}  source
#     Source description (e.g. repo name) for SYNC.md.
# @param  {string}  skill_url
#     Direct download URL for the skill's SKILL.md.
# @param  {string}  references_api_url
#     GitHub API URL for reference files, or empty.
# @param  {string}  commit_api_url
#     GitHub API URL to resolve the upstream SHA, or empty.
# @param  {string}  license
#     Licence identifier for SYNC.md.
# @param  {string}  upstream_content_target
#     Filename that receives the stripped upstream skill content.
sync_skill() {
	local slug="$1"
	local group="$2"
	local name="$3"
	local source="$4"
	local skill_url="$5"
	local references_api_url="$6"
	local commit_api_url="$7"
	local license="$8"
	local upstream_content_target="$9"

	local target_dir
	if [ -n "$group" ]; then
		target_dir="$REPO_DIR/skills/$group/$slug"
	else
		target_dir="$REPO_DIR/skills/$slug"
	fi

	local skill_file="$target_dir/$upstream_content_target"
	local sync_file="$target_dir/SYNC.md"
	local upstream_sha="unresolved"
	local current_sha=""

	cli_status info "Syncing external skill" "$slug"

	if [ -n "$commit_api_url" ]; then
		cli_status info "Resolving upstream revision"
		upstream_sha=$(curl -fsSL "$commit_api_url" | jq -r '.sha // "unresolved"' 2>/dev/null || printf 'unresolved')
	fi

	if [ -f "$sync_file" ]; then
		current_sha=$(awk -F'|' '/Upstream SHA/ { gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit }' "$sync_file")
	fi

	if [ "$upstream_sha" != "unresolved" ] && [ "$current_sha" = "$upstream_sha" ] && [ -f "$skill_file" ]; then
		cli_status muted "already up to date" "$upstream_sha"
		return
	fi

	local temp_file
	temp_file=$(mktemp)

	cli_status info "Fetching" "SKILL.md"
	curl -fsSL "$skill_url" -o "$temp_file"
	vet_skill_file "$temp_file" "$slug"

	mkdir -p "$target_dir"
	strip_frontmatter "$temp_file" "$skill_file"
	rm "$temp_file"

	if [ -n "$references_api_url" ]; then
		fetch_references "$references_api_url" "$target_dir"
	fi

	local references_count=0
	[ -d "$target_dir/references" ] && references_count=$(find "$target_dir/references" -type f | wc -l | tr -d ' ')

	local synced_at
	synced_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

	cat > "$sync_file" <<EOF
# ${name}

Managed by \`scripts/sync-external-skills.sh\`. \`${upstream_content_target}\` is overwritten on each sync. Do not edit it directly.

| Field | Value |
|-------|-------|
| Source | ${source} |
| Skill URL | ${skill_url} |
| Upstream content target | ${upstream_content_target} |
| References URL | ${references_api_url:-none} |
| References synced | ${references_count} |
| Upstream SHA | ${upstream_sha} |
| Licence | ${license} |
| Synced at | ${synced_at} |
EOF

	cli_status success "synced external skill" "$slug"
}

# Syncs every skill listed in external-skills.json.
sync_all_skills() {
	local count
	count=$(jq 'length' "$MANIFEST")

	cli_section "External skills" "Sync managed upstream skills"

	local index
	for index in $(seq 0 $((count - 1))); do
		local slug group name source skill_url references_api_url commit_api_url license upstream_content_target
		slug=$(jq -r ".[$index].slug" "$MANIFEST")
		group=$(jq -r ".[$index].group // \"\"" "$MANIFEST")
		name=$(jq -r ".[$index].name" "$MANIFEST")
		source=$(jq -r ".[$index].source" "$MANIFEST")
		skill_url=$(jq -r ".[$index].skill_url" "$MANIFEST")
		references_api_url=$(jq -r ".[$index].references_api_url // \"\"" "$MANIFEST")
		commit_api_url=$(jq -r ".[$index].commit_api_url // \"\"" "$MANIFEST")
		license=$(jq -r ".[$index].license // \"unknown\"" "$MANIFEST")
		upstream_content_target=$(jq -r ".[$index].upstream_content_target // \"SKILL.body.md\"" "$MANIFEST")

		sync_skill "$slug" "$group" "$name" "$source" "$skill_url" "$references_api_url" "$commit_api_url" "$license" "$upstream_content_target"
	done
}

require_sync_dependencies
sync_all_skills
