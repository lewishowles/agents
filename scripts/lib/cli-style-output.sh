#!/usr/bin/env bash
# Shared cli-style rendering helpers for repository scripts.

# The global install command to show when cli-style is missing or cannot run.
CLI_STYLE_INSTALL_GUIDANCE='Run: bun add -g @lewishowles/cli-style (or npm install -g @lewishowles/cli-style)'

# The cli-style executable that the rendering helpers call: CLI_STYLE_BIN when
# the caller sets it, otherwise the cli-style command on PATH.
if [ -z "${CLI_STYLE_BIN:-}" ]; then
	CLI_STYLE_BIN=$(command -v cli-style || true)
	if [ -z "$CLI_STYLE_BIN" ]; then
		printf 'cli-style is not installed. %s\n' "$CLI_STYLE_INSTALL_GUIDANCE" >&2
		exit 1
	fi
fi
export CLI_STYLE_BIN

# The label of the status group whose rows are being counted, or empty when no group is active.
CLI_STYLE_GROUP_LABEL=""
# The number of successful rows in the current group.
CLI_STYLE_GROUP_SUCCESS=0
# The number of skipped rows in the current group.
CLI_STYLE_GROUP_SKIPPED=0
# The label of the first skipped row in the current group, shown as the reason in the summary.
CLI_STYLE_GROUP_SKIPPED_REASON=""
# The number of unchanged rows in the current group.
CLI_STYLE_GROUP_UNCHANGED=0
# The number of warning rows in the current group.
CLI_STYLE_GROUP_WARNING=0
# The number of failed rows in the current group.
CLI_STYLE_GROUP_FAILED=0

if [ ! -x "$CLI_STYLE_BIN" ]; then
	printf 'cli-style is not executable: %s. %s\n' "$CLI_STYLE_BIN" "$CLI_STYLE_INSTALL_GUIDANCE" >&2
	exit 1
fi

# The cli-style binary prints the adapter's path when the script runs, so the
# path is unknown to shellcheck.
# shellcheck disable=SC1090
source "$("$CLI_STYLE_BIN" adapter-path bash)"

# Renders a status row through the installed cli-style binary.
#
# @param  {string}  type
#     Status result type.
# @param  {string}  label
#     Main status label.
# @param  {string}  detail
#     Additional status text.
cli_status() {
	# The status type to render, which may be an alias such as error or muted.
	local type="$1"
	# The main text of the status row.
	local label="$2"
	# Optional detail shown beside the status label.
	local detail="${3:-}"

	case "$type" in
		error) type="failed" ;;
		muted) type="unchanged" ;;
	esac

	# The fields as JSON strings. The row matches json.dumps output byte for
	# byte, including its key order and spacing.
	local type_json label_json detail_json
	cli_json_string "$type"
	type_json="$REPLY"
	cli_json_string "$label"
	label_json="$REPLY"
	cli_json_string "$detail"
	detail_json="$REPLY"
	printf '{"type": %s, "label": %s, "detail": %s}\n' "$type_json" "$label_json" "$detail_json" | cli_style_render status
}

# Renders a reporter-style group summary row.
#
# @param  {string}  type
#     Group result type.
# @param  {string}  label
#     Group label.
# @param  {string}  summary
#     Group summary text.
cli_group() {
	# The result type of the group summary row.
	local type="$1"
	# The main text of the group summary row.
	local label="$2"
	# The counts shown beside the group label.
	local summary="${3:-}"

	cli_status "$type" "$label" "$summary"
}

# Renders a compact section divider for major script phases.
#
# @param  {string}  title
#     Section title.
# @param  {string}  detail
#     Optional supporting text.
cli_section() {
	# The heading shown in the section divider.
	local title="$1"
	# Optional supporting text shown beside the section heading.
	local detail="${2:-}"

	printf '\n'
	# The divider text: the heading, followed by any supporting text.
	local label="$title"
	if [[ -n "$detail" ]]; then
		label+=" · $detail"
	fi

	# The encoded divider text.
	local label_json
	cli_json_string "$label"
	label_json="$REPLY"
	printf '{"dividerWidth": 64, "label": %s, "labelColour": "info"}\n' "$label_json" | cli_style_render divider
}

# Encodes text as a quoted JSON string, exactly as Python's json.dumps writes
# it, and stores the result in REPLY. The encoding runs in the shell because
# starting Python for every status line doubled the time of a setup run.
#
# Non-ASCII characters become \u escapes. Bytes that are not valid UTF-8 become
# \udc80 to \udcff, the values Python gives undecodable command-line bytes.
#
# @param  {string}  value
#     The text to encode. Shell arguments cannot contain NUL bytes.
cli_json_string() {
	# Treat the text as single bytes whatever the caller's locale is.
	local LC_ALL=C
	# The bytes left to encode.
	local value="$1"
	# The encoded JSON string, built up one character at a time.
	local result='"'
	# The current byte and Unicode code point.
	local byte code_point
	# The current byte as text and the candidate UTF-8 continuation bytes.
	local character sequence
	# The number of continuation bytes and their index.
	local count index
	# A continuation byte being checked before it is consumed.
	local next_byte
	# The smallest valid code point for the current UTF-8 sequence.
	local minimum
	# One escaped code point or surrogate.
	local escaped

	while [[ -n "$value" ]]; do
		character="${value:0:1}"
		printf -v byte '%d' "'$character"
		value="${value:1}"

		case "$byte" in
			8) result+='\b'; continue ;;
			9) result+='\t'; continue ;;
			10) result+='\n'; continue ;;
			12) result+='\f'; continue ;;
			13) result+='\r'; continue ;;
			34) result+='\"'; continue ;;
			92) result+="\\\\"; continue ;;
		esac

		if (( byte < 32 || byte == 127 )); then
			printf -v escaped '\\u%04x' "$byte"
			result+="$escaped"
			continue
		fi
		if (( byte < 128 )); then
			result+="$character"
			continue
		fi

		# Work out the length of a multi-byte UTF-8 character from its first byte.
		if (( byte >= 0xC2 && byte <= 0xDF )); then
			code_point=$((byte & 31))
			count=1
			minimum=0x80
		elif (( byte >= 0xE0 && byte <= 0xEF )); then
			code_point=$((byte & 15))
			count=2
			minimum=0x800
		elif (( byte >= 0xF0 && byte <= 0xF4 )); then
			code_point=$((byte & 7))
			count=3
			minimum=0x10000
		else
			printf -v escaped '\\udc%02x' "$byte"
			result+="$escaped"
			continue
		fi

		sequence="${value:0:count}"
		for ((index = 0; index < ${#sequence}; index++)); do
			printf -v next_byte '%d' "'${sequence:index:1}"
			if (( next_byte < 0x80 || next_byte > 0xBF )); then
				break
			fi
			code_point=$((code_point << 6 | next_byte & 63))
		done

		# A short, overlong or out-of-range character escapes only its first byte,
		# and the bytes after it are encoded on the following passes.
		if (( index != count || code_point < minimum || code_point > 0x10FFFF || (code_point >= 0xD800 && code_point <= 0xDFFF) )); then
			printf -v escaped '\\udc%02x' "$byte"
			result+="$escaped"
			continue
		fi
		value="${value:count}"

		# Characters above U+FFFF are written as a UTF-16 surrogate pair, as json.dumps does.
		if (( code_point <= 0xFFFF )); then
			printf -v escaped '\\u%04x' "$code_point"
			result+="$escaped"
		else
			code_point=$((code_point - 0x10000))
			printf -v escaped '\\u%04x' "$((0xD800 + (code_point >> 10)))"
			result+="$escaped"
			printf -v escaped '\\u%04x' "$((0xDC00 + (code_point & 0x3FF)))"
			result+="$escaped"
		fi
	done

	REPLY="$result\""
}

# Starts collecting status rows for one grouped summary.
#
# @param  {string}  label
#     Group label.
cli_group_begin() {
	# The label of the new group of status rows.
	local label="$1"

	CLI_STYLE_GROUP_LABEL="$label"
	CLI_STYLE_GROUP_SUCCESS=0
	CLI_STYLE_GROUP_SKIPPED=0
	CLI_STYLE_GROUP_SKIPPED_REASON=""
	CLI_STYLE_GROUP_UNCHANGED=0
	CLI_STYLE_GROUP_WARNING=0
	CLI_STYLE_GROUP_FAILED=0
}

# Records and optionally renders a status row inside the active group.
#
# @param  {string}  type
#     Status result type.
# @param  {string}  label
#     Main status label.
# @param  {string}  detail
#     Additional status text.
cli_group_status() {
	# The status type of the new group row, which may be an alias such as error or muted.
	local type="$1"
	# The main text of the new group row.
	local label="$2"
	# Optional detail shown beside the row label.
	local detail="${3:-}"
	# The status type with any alias replaced by its result type.
	local normalised_type

	normalised_type=$(cli_normalise_status_type "$type")

	if [[ "$CLI_STYLE_GROUP_LABEL" == "" ]]; then
		cli_status "$normalised_type" "$label" "$detail"
		return
	fi

	cli_group_record "$normalised_type" "$label"

	if [[ "${CLI_STYLE_VERBOSE:-0}" != "1" ]] && [[ "$normalised_type" =~ ^(success|skipped|unchanged)$ ]]; then
		return
	fi

	cli_status "$normalised_type" "$label" "$detail"
}

# Renders the active group summary and clears the group state.
cli_group_end() {
	# The overall result type and the count text for the group that is ending.
	local result summary

	if [[ "$CLI_STYLE_GROUP_LABEL" == "" ]]; then
		return
	fi

	result=$(cli_group_result)
	summary=$(cli_group_summary)
	if [[ "$summary" == "" ]]; then
		CLI_STYLE_GROUP_LABEL=""
		return
	fi

	cli_group "$result" "$CLI_STYLE_GROUP_LABEL" "$summary"
	CLI_STYLE_GROUP_LABEL=""
}

# Normalises shell-friendly aliases to result types accepted by cli-style.
#
# @param  {string}  type
#     Status result type or alias.
# @returns  {string}
#     Normalised status result type.
cli_normalise_status_type() {
	# The status result type or alias to convert.
	local type="$1"

	case "$type" in
		error) printf 'failed' ;;
		muted) printf 'unchanged' ;;
		*) printf '%s' "$type" ;;
	esac
}

# Counts one status row for the active group.
#
# @param  {string}  type
#     Normalised status result type.
# @param  {string}  label
#     Status label.
cli_group_record() {
	# The result type of the row being counted.
	local type="$1"
	# The row's label, kept as the skipped reason when it is the group's first skipped row.
	local label="$2"

	case "$type" in
		failed) CLI_STYLE_GROUP_FAILED=$((CLI_STYLE_GROUP_FAILED + 1)) ;;
		warning) CLI_STYLE_GROUP_WARNING=$((CLI_STYLE_GROUP_WARNING + 1)) ;;
		success) CLI_STYLE_GROUP_SUCCESS=$((CLI_STYLE_GROUP_SUCCESS + 1)) ;;
		skipped)
			CLI_STYLE_GROUP_SKIPPED=$((CLI_STYLE_GROUP_SKIPPED + 1))
			if [[ "$CLI_STYLE_GROUP_SKIPPED_REASON" == "" ]]; then
				CLI_STYLE_GROUP_SKIPPED_REASON="$label"
			fi
			;;
		unchanged) CLI_STYLE_GROUP_UNCHANGED=$((CLI_STYLE_GROUP_UNCHANGED + 1)) ;;
	esac
}

# Returns the highest-severity result for the active group.
#
# @returns  {string}
#     Group result type.
cli_group_result() {
	if [[ "$CLI_STYLE_GROUP_FAILED" -gt 0 ]]; then
		printf 'failed'
	elif [[ "$CLI_STYLE_GROUP_WARNING" -gt 0 ]]; then
		printf 'warning'
	elif [[ "$CLI_STYLE_GROUP_SUCCESS" -gt 0 ]]; then
		printf 'success'
	elif [[ "$CLI_STYLE_GROUP_SKIPPED" -gt 0 ]]; then
		printf 'skipped'
	else
		printf 'unchanged'
	fi
}

# Returns compact count text for the active group.
#
# @returns  {string}
#     Group summary text.
cli_group_summary() {
	# The comma-separated counts for each result type in the active group.
	local summary=""

	cli_group_append_summary summary "$CLI_STYLE_GROUP_FAILED" "failed"
	cli_group_append_summary summary "$CLI_STYLE_GROUP_WARNING" "warning"
	cli_group_append_summary summary "$CLI_STYLE_GROUP_SUCCESS" "success"
	cli_group_append_skipped_summary summary
	cli_group_append_summary summary "$CLI_STYLE_GROUP_UNCHANGED" "unchanged"

	printf '%s' "$summary"
}

# Appends skipped count and reason to a comma-separated group summary.
#
# @param  {string}  summary_name
#     Variable name for the summary being built.
cli_group_append_skipped_summary() {
	# The name of the caller's variable that holds the summary.
	local summary_name="$1"
	# The text after the skipped count, with the saved reason when there is one.
	local label="skipped"

	if [[ "$CLI_STYLE_GROUP_SKIPPED" -eq 0 ]]; then
		return
	fi

	if [[ "$CLI_STYLE_GROUP_SKIPPED_REASON" != "" ]]; then
		label="skipped (${CLI_STYLE_GROUP_SKIPPED_REASON})"
	fi

	cli_group_append_summary "$summary_name" "$CLI_STYLE_GROUP_SKIPPED" "$label"
}

# Appends one count to a comma-separated group summary.
#
# @param  {string}  summary_name
#     Variable name for the summary being built.
# @param  {number}  count
#     Count to append.
# @param  {string}  label
#     Count label.
cli_group_append_summary() {
	# The name of the caller's variable that holds the summary.
	local summary_name="$1"
	# The number of rows this entry counts.
	local count="$2"
	# The text shown after the count, such as a result type with any skipped reason.
	local label="$3"
	# The summary text the caller's variable holds before this entry is added.
	local current

	if [[ "$count" -eq 0 ]]; then
		return
	fi

	current="${!summary_name}"
	if [[ "$current" == "" ]]; then
		printf -v "$summary_name" '%s %s' "$count" "$label"
	else
		printf -v "$summary_name" '%s, %s %s' "$current" "$count" "$label"
	fi
}
