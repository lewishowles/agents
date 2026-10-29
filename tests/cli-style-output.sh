#!/usr/bin/env bash
# Checks that status rows and section dividers send cli-style the same JSON
# that Python's json.dumps produced before the encoding moved into the shell.

set -euo pipefail

# The folder containing this test and its shared helpers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository containing the output helpers under test.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# The temporary cli-style stand-in and comparison files.
TEST_ROOT=$(mktemp -d)
# shellcheck source=SCRIPTDIR/lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
trap cleanup EXIT
# The adapter returned by the stand-in executable.
CLI_STYLE_TEST_ADAPTER="$TEST_ROOT/adapter.sh"
export CLI_STYLE_TEST_ADAPTER

# The stand-in cli-style only reports the adapter path, and the stand-in
# adapter prints the JSON it receives so the test can compare it.
cat > "$TEST_ROOT/cli-style" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$CLI_STYLE_TEST_ADAPTER"
SH
cat > "$CLI_STYLE_TEST_ADAPTER" <<'SH'
cli_style_render() {
	cat
}
SH
chmod +x "$TEST_ROOT/cli-style"

# The stand-in executable the output helpers call instead of the installed one.
CLI_STYLE_BIN="$TEST_ROOT/cli-style"
# shellcheck source=SCRIPTDIR/../scripts/lib/cli-style-output.sh
source "$REPO_DIR/scripts/lib/cli-style-output.sh"

# Compares a status row with Python's original JSON output.
#
# @param  {string}  case_name
#     The input case to name in a failure.
# @param  {string}  type
#     The status type before aliases are resolved.
# @param  {string}  label
#     The row label.
# @param  {string}  detail
#     The row detail.
check_status() {
	# The name used to identify a failed case.
	local case_name="$1"
	# The status type to pass to the helper.
	local type="$2"
	# The text shown as the row label.
	local label="$3"
	# The text shown as the row detail.
	local detail="$4"

	cli_status "$type" "$label" "$detail" > "$TEST_ROOT/actual"
	python3 - "$type" "$label" "$detail" > "$TEST_ROOT/expected" <<'PY'
import json
import sys

type_name = {"error": "failed", "muted": "unchanged"}.get(sys.argv[1], sys.argv[1])
print(json.dumps({"type": type_name, "label": sys.argv[2], "detail": sys.argv[3]}))
PY
	assert_same_json "Status JSON differs for $case_name"
}

# Compares a section divider with Python's original JSON output.
#
# @param  {string}  case_name
#     The input case to name in a failure.
# @param  {string}  title
#     The section heading.
# @param  {string}  detail
#     The optional supporting text.
check_section() {
	# The name used to identify a failed case.
	local case_name="$1"
	# The section heading to pass to the helper.
	local title="$2"
	# The supporting text to pass to the helper.
	local detail="$3"

	cli_section "$title" "$detail" > "$TEST_ROOT/actual"
	python3 - "$title" "$detail" > "$TEST_ROOT/expected" <<'PY'
import json
import sys

label = sys.argv[1] if sys.argv[2] == "" else f"{sys.argv[1]} · {sys.argv[2]}"
print()
print(json.dumps({"dividerWidth": 64, "label": label, "labelColour": "info"}))
PY
	assert_same_json "Divider JSON differs for $case_name"
}

# Fails the test, showing both versions, when the shell output differs from
# Python's.
#
# @param  {string}  message
#     The failure to report.
assert_same_json() {
	# The failure to report when the outputs differ.
	local message="$1"

	if ! cmp -s "$TEST_ROOT/actual" "$TEST_ROOT/expected"; then
		printf 'Actual JSON:\n' >&2
		cat "$TEST_ROOT/actual" >&2
		printf 'Expected JSON:\n' >&2
		cat "$TEST_ROOT/expected" >&2
		fail "$message"
	fi
}

# Every ASCII control character that can occur in a shell argument: 1 to 31
# and DEL. NUL cannot be passed as an argument.
controls=""
# A control character's numeric value.
code=0
# The octal escape used to produce a control character.
octal=""
# The current control character added to the combined test input.
character=""
for ((code = 1; code <= 31; code++)); do
	printf -v octal '\\%03o' "$code"
	printf -v character '%b' "$octal"
	controls+="$character"
done
controls+=$'\x7f'

check_status "plain fields" success "Ready" ""
check_status "aliases" error "Failed" "detail"
check_status "quotes and backslashes" muted 'A "quote" and a \ slash' 'C:\somewhere\file'
check_status "tabs and newlines" info $'first\tsecond\nthird' $'detail\rnext'
check_status "all control characters" warning "$controls" "$controls"
check_status "Unicode" success 'café € 😀' 'é · 𝄞'
check_status "invalid UTF-8" warning $'\xff \xe2\x82A \xe0\x80\x80 \xed\xa0\x80 \xf4\x90\x80\x80' $'end \xc3'
check_section "plain heading" "Generated outputs" ""
check_section "supporting text" 'A "quote" and a \ slash' $'detail\twith\nlines'
check_section "control and Unicode text" "$controls" 'café € 😀'

# When CLI_STYLE_BIN points at a missing file, the shared output functions
# still print plain text, so setup, doctor, sync and validate keep working.
(
	# The override belongs only to this plain-output case.
	# shellcheck disable=SC2030
	CLI_STYLE_BIN="$TEST_ROOT/missing-cli-style"
	# shellcheck source=SCRIPTDIR/../scripts/lib/cli-style-output.sh
	source "$REPO_DIR/scripts/lib/cli-style-output.sh"
	cli_section 'Generated outputs' 'Build dist files and manifests'
	cli_status success 'synced' 'dist/codex/AGENTS.md'
	cli_group_begin 'Checks'
	cli_group_status error 'skill manifests' 'failed'
	cli_group_end
) > "$TEST_ROOT/actual" 2> "$TEST_ROOT/plain-error"
cat > "$TEST_ROOT/expected" <<'EOF'

Generated outputs
synced: dist/codex/AGENTS.md
Checks
error: skill manifests: failed
EOF
if ! cmp -s "$TEST_ROOT/actual" "$TEST_ROOT/expected"; then
	fail 'Missing cli-style did not produce readable plain output'
fi
if [ -s "$TEST_ROOT/plain-error" ]; then
	fail 'Missing cli-style printed an error while loading the output helpers'
fi

# With no override and no cli-style on PATH, the shared helpers still print
# plain output, including the result of warnings and errors.
(
	unset CLI_STYLE_BIN
	PATH=/usr/bin:/bin
	# shellcheck source=SCRIPTDIR/../scripts/lib/cli-style-output.sh
	source "$REPO_DIR/scripts/lib/cli-style-output.sh"
	cli_status warning 'cli-style' 'missing'
	cli_status failed 'check' 'failed'
	cli_status info 'guidance' 'available'
	cli_status skipped 'optional check' 'skipped'
	cli_status muted 'unchanged'
) > "$TEST_ROOT/actual"
cat > "$TEST_ROOT/expected" <<'EOF'
warning: cli-style: missing
error: check: failed
info: guidance: available
optional check: skipped
unchanged
EOF
if ! cmp -s "$TEST_ROOT/actual" "$TEST_ROOT/expected"; then
	fail 'No cli-style on PATH did not produce readable plain output'
fi

printf '✓ cli-style output tests passed\n'
