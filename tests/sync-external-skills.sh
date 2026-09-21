#!/usr/bin/env bash
# Verifies external skill content can be routed without overwriting a local skill.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

source "$SCRIPT_DIR/lib/test-helpers.sh"

trap cleanup EXIT

# Creates a minimal configuration repository with default and routed external skills.
#
# @param  {string}  target_dir
#     Temporary repository root.
create_fixture_repo() {
	local target_dir="$1"

	mkdir -p \
		"$target_dir/scripts" \
		"$target_dir/skills/vue/default-skill" \
		"$target_dir/skills/vue/vue-use"
	cp "$REPO_DIR/scripts/sync-external-skills.sh" "$target_dir/scripts/sync-external-skills.sh"
	cp -R "$REPO_DIR/scripts/lib" "$target_dir/scripts/lib"
	# The fixture has no cli-style install of its own, so point the copied sync script at this repo's copy.
	export CLI_STYLE_BIN="$REPO_DIR/.agent/tools/cli-style/bin/cli-style"

	printf '# Existing default skill\n' > "$target_dir/skills/vue/default-skill/SKILL.md"
	printf '# Local wrapper\n' > "$target_dir/skills/vue/vue-use/SKILL.md"
	printf '%s\n' \
		'---' \
		'name: upstream' \
		'---' \
		'' \
		'# Upstream catalogue' \
		> "$target_dir/upstream-SKILL.md"
	printf '%s\n' \
		'[' \
		'	{' \
		'		"slug": "default-skill",' \
		'		"group": "vue",' \
		'		"name": "Default skill",' \
		'		"source": "fixture",' \
		'		"skill_url": "https://example.test/default-skill",' \
		'		"commit_api_url": "https://example.test/default-commit",' \
		'		"license": "MIT"' \
		'	},' \
		'	{' \
		'		"slug": "vue-use",' \
		'		"group": "vue",' \
		'		"name": "VueUse Functions",' \
		'		"source": "fixture",' \
		'		"skill_url": "https://example.test/vue-use",' \
		'		"commit_api_url": "https://example.test/vue-use-commit",' \
		'		"upstream_content_target": "SKILL.ref.md",' \
		'		"license": "MIT"' \
		'	}' \
		']' \
		> "$target_dir/external-skills.json"
}

# Returns fixture content for the external sync script without network access.
curl() {
	local output_file=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
			-o)
				output_file="$2"
				shift 2
				;;
			-*)
				shift
				;;
			*)
				shift
				;;
		esac
	done

	if [ -n "$output_file" ]; then
		cp "$SYNC_TEST_SKILL_FILE" "$output_file"
		return
	fi

	printf '{"sha":"fixture-sha"}\n'
}

# Confirms configured routing preserves the local body and keeps default behaviour unchanged.
test_upstream_content_target() {
	local target_dir="$TEST_ROOT/content-target"
	local output="$TEST_ROOT/content-target.log"

	create_fixture_repo "$target_dir"
	export SYNC_TEST_SKILL_FILE="$target_dir/upstream-SKILL.md"
	export -f curl

	bash "$target_dir/scripts/sync-external-skills.sh" > "$output"

	assert_contains "$target_dir/skills/vue/default-skill/SKILL.md" "# Upstream catalogue"
	assert_contains "$target_dir/skills/vue/vue-use/SKILL.md" "# Local wrapper"
	assert_contains "$target_dir/skills/vue/vue-use/SKILL.ref.md" "name: upstream"
	assert_contains "$target_dir/skills/vue/vue-use/SKILL.ref.md" "# Upstream catalogue"
	assert_contains "$target_dir/skills/vue/vue-use/SYNC.md" "Upstream content target | SKILL.ref.md"
	assert_contains "$target_dir/skills/vue/vue-use/SYNC.md" "\`SKILL.ref.md\` is overwritten on each sync"
}

test_upstream_content_target

printf '✓ external skill sync tests passed\n'
