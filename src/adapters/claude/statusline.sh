#!/usr/bin/env bash
# Claude Code status line: workspace, context usage, rate-limit burn rate, model.
#
# Rate-limit windows are rendered as a fill bar with a tick mark for where the
# reset clock currently sits in the window (elapsed / window length). Fill
# past the tick, and a warmer bar colour, mean usage is running ahead of a
# sustainable pace for that window. This needs no stored history: resets_at
# plus the window's fixed length is enough to derive elapsed time on every
# render.

# The status data Claude Code sends for this render.
input=$(cat)

# The folder the session is working in, used for the label and worktree check.
workspace_dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty')
# The folder label on the first line: the session folder's name, or the main
# repo's name in a worktree.
dir=$(basename "$workspace_dir" 2>/dev/null)
# The number of input tokens used by this session.
tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
# The session ID that names this session's tool-call counter file.
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
# The model name shown beside the session details.
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
# The reasoning effort shown after the model when available.
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
# The share of the five-hour limit already used.
five_used=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
# The time the five-hour window resets, in epoch seconds.
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
# The share of the seven-day limit already used.
seven_used=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
# The time the seven-day window resets, in epoch seconds.
seven_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# The colour for the folder name.
green=$(printf '\033[38;5;114m')
# The colour for token and tool-round usage.
orange=$(printf '\033[38;5;215m')
# The colour for the model name.
white=$(printf '\033[1;97m')
# The colour for separators and the worktree path.
grey=$(printf '\033[38;5;240m')
# The colour for the account tag.
magenta=$(printf '\033[1;38;5;170m')
# Restores the terminal colour after each coloured segment.
reset=$(printf '\033[0m')
# The separator between details on the same line.
sep=" ${grey}·${reset} "

# In a linked worktree, the label names the main repo and the worktree path gets
# its own muted last line. A worktree's own Git folder differs from the main
# repo's shared one; outside a repo, or if Git fails, the output stays as it was.
#
# The worktree root path to print on the last line, or empty outside a worktree.
worktree_path=""
# The worktree's Git folder, the shared Git folder, and the worktree root, one
# per line.
if [[ -n "$workspace_dir" ]] && git_dirs_output=$(git -C "$workspace_dir" rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel 2>/dev/null); then
	# The session's own Git folder.
	git_dir="${git_dirs_output%%$'\n'*}"
	# The main repo's Git folder, which sits inside the main repo's folder.
	common_git_dir="${git_dirs_output#*$'\n'}"
	common_git_dir="${common_git_dir%%$'\n'*}"
	if [[ "$git_dir" != "$common_git_dir" ]]; then
		dir="$(basename "$(dirname "$common_git_dir")") (worktree)"
		worktree_path="${git_dirs_output##*$'\n'}"
		if [[ "$worktree_path" == "$HOME" || "$worktree_path" == "$HOME/"* ]]; then
			worktree_path="~${worktree_path#"$HOME"}"
		fi
	fi
fi

# Marks which account this session is running under, e.g. CLAUDE_CONFIG_DIR
# ~/.claude-2 renders as [2]. Unset or the default ~/.claude renders nothing.
account_tag=""
if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
	# The config folder name; any suffix after .claude- becomes the account tag.
	base=$(basename "$CLAUDE_CONFIG_DIR")
	[[ "$base" =~ ^\.claude-(.+)$ ]] && account_tag="${BASH_REMATCH[1]}"
fi

# The current time used to position each rate-limit clock tick.
now=$(date +%s)

# The token count shortened for the first status line.
tokensfmt=""
if [[ -n "$tokens" ]]; then
	if (( tokens >= 1000000 )); then
		tokensfmt=$(echo "scale=1; $tokens / 1000000" | bc)M
	elif (( tokens >= 1000 )); then
		tokensfmt=$(echo "scale=1; $tokens / 1000" | bc)K
	else
		tokensfmt="${tokens}"
	fi
fi

# The round segment, such as "rounds 12/20". The checkpoint hook counts the
# rounds and picks the limit; this only shows what it saved. A session without a
# counter file, or a file written before the hook saved the limit, shows nothing.
tool_rounds=""
if [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
	# The checkpoint hook's counter file for this session.
	state_file="${TMPDIR:-/tmp}/agent-tool-call-checkpoints/claude-$session_id"
	if [[ -f "$state_file" ]]; then
		# The saved round count and limit, read from the file's single line.
		read -r count limit < "$state_file" || true
		if [[ "$count" =~ ^[0-9]+$ && "$limit" =~ ^[1-9][0-9]*$ ]]; then
			tool_rounds="rounds $count/$limit"
		fi
	fi
fi

# Prints one rate-limit window as a usage bar with a tick for the current point
# in the window, then the usage percentage and the reset day and time. Prints
# nothing when usage is unavailable.
#
# @param  {string}  label
#     The short window label, such as "5h".
# @param  {number}  window
#     The window length in seconds.
# @param  {string}  used
#     The percentage of this window's limit already used, or empty if unavailable.
# @param  {string}  resets
#     The reset time in epoch seconds, or empty if unavailable.
render_window() {
	# The label, length, usage, and reset time for the window being rendered.
	local label="$1" window="$2" used="$3" resets="$4"

	[[ -z "$used" ]] && return

	awk -v label="$label" -v window="$window" -v used="$used" -v resets="${resets:-0}" -v now="$now" '
	# Colours text with a true-colour RGB value.
	#
	# @param  {number}  r
	#     The red channel.
	# @param  {number}  g
	#     The green channel.
	# @param  {number}  b
	#     The blue channel.
	# @param  {string}  s
	#     The text to colour.
	function esc(r, g, b, s) { return sprintf("%c[38;2;%d;%d;%dm%s%c[0m", 27, r, g, b, s, 27) }
	# Colours secondary text grey.
	#
	# @param  {string}  s
	#     The text to mute.
	function dim(s) { return esc(110, 110, 125, s) }
	# Keeps a value within the requested range.
	#
	# @param  {number}  x
	#     The value to limit.
	# @param  {number}  lo
	#     The lowest allowed value.
	# @param  {number}  hi
	#     The highest allowed value.
	function clamp(x, lo, hi) { if (x < lo) return lo; if (x > hi) return hi; return x }
	# Chooses the bar colour from the usage pace.
	# Returns the red, green and blue channels joined by SUBSEP.
	#
	# @param  {number}  t
	#     The position along the cool-to-warm colour scale.
	function hue(t,    r, g, b) {
		# The RGB channels for the selected bar colour.
		if (t < 0.5) { r = 90 + t * 2 * 155; g = 220 - t * 2 * 30; b = 160 - t * 2 * 90 }
		else { r = 245; g = 190 - (t - 0.5) * 2 * 110; b = 70 + (t - 0.5) * 2 * 30 }
		return int(r) SUBSEP int(g) SUBSEP int(b)
	}
	BEGIN {
		if (resets == 0) {
			# A missing reset time leaves the clock tick off the bar.
			clock = -1
		} else {
			# The time left until this limit window resets.
			left = resets - now; if (left < 0) left = 0
			# The time already spent in this limit window.
			elapsed = clamp(window - left, 0, window)
			# The clock tick position as a percentage of the window.
			clock = elapsed / window * 100
		}

		# The bar colour position, warmer when usage runs ahead of time.
		tone = (clock < 0) ? clamp(used, 0, 100) / 100 : clamp(0.5 - (clock - used) / 50, 0, 1)
		# The red, green and blue channels from hue().
		split(hue(tone), rgb, SUBSEP)
		# The RGB channels applied to the filled bar and percentage.
		r = rgb[1]; g = rgb[2]; b = rgb[3]

		# The number of characters in each usage bar.
		cells = 10
		# The number of bar characters filled by current usage.
		filled = int(clamp(used, 0, 100) / 100 * cells + 0.5)
		# The character position of the clock tick, or none without a reset.
		if (clock < 0) { at = -1 }
		else { at = clamp(int(clock / 100 * cells), 0, cells - 1) }

		# The coloured bar built from filled, empty, and clock characters.
		bar = ""
		# The current character position while building the bar.
		for (i = 0; i < cells; i++) {
			if (i == at) bar = bar esc(235, 235, 245, "┃")
			else if (i < filled) bar = bar esc(r, g, b, "█")
			else bar = bar dim("░")
		}

		# The window label, bar, usage percentage, and optional reset time.
		out = dim(label) " " bar " " esc(r, g, b, sprintf("%d%%", used + 0.5))

		if (resets != 0) {
			# The date command used to format the reset time.
			cmd = "date -r " resets " \"+%a %H:%M\""
			# The formatted day and time shown after the reset symbol.
			cmd | getline dstr
			close(cmd)
			gsub(/^ +| +$/, "", dstr)
			out = out dim("  ↻  " tolower(dstr))
		}

		printf "%s", out
	}
	'
}

# Joins status-line segments with the shared separator, skipping empty ones.
#
# @param  {string}  ...
#     Segments to join.
join_parts() {
	# The joined status text and the current segment being considered.
	local out="" p
	for p in "$@"; do
		[[ -z "$p" ]] && continue
		if [[ -z "$out" ]]; then out="$p"; else out="$out$sep$p"; fi
	done
	printf '%s' "$out"
}

# The coloured details on the first status line: account, directory, context
# usage, tool rounds, and model. This line stays short so it never wraps.
line1_parts=()
[[ -n "$account_tag" ]] && line1_parts+=("${magenta}[${account_tag}]${reset}")
[[ -n "$dir" ]] && line1_parts+=("${green}${dir}${reset}")
[[ -n "$tokensfmt" ]] && line1_parts+=("${orange}${tokensfmt} used${reset}")
[[ -n "$tool_rounds" ]] && line1_parts+=("${orange}${tool_rounds}${reset}")

if [[ -n "$model" ]]; then
	# The model label with its optional effort level.
	m="$model"
	[[ -n "$effort" ]] && m="$m $effort"
	line1_parts+=("${white}${m}${reset}")
fi

# The five-hour and seven-day usage bars on the second status line. They are
# the widest segments, so they sit on their own line and a narrow terminal
# does not cut them off.
line2_parts=()

# The rendered five-hour usage bar, if data is available.
five_seg=$(render_window "5h" $((5 * 3600)) "$five_used" "$five_reset")
[[ -n "$five_seg" ]] && line2_parts+=("$five_seg")

# The rendered seven-day usage bar, if data is available.
seven_seg=$(render_window "wk" $((7 * 86400)) "$seven_used" "$seven_reset")
[[ -n "$seven_seg" ]] && line2_parts+=("$seven_seg")

# The complete first status line.
line1=$(join_parts "${line1_parts[@]}")
# The complete usage status line, if rate-limit data is available.
line2=$(join_parts "${line2_parts[@]}")

if [[ -n "$line2" ]]; then
	printf '%s\n%s\n' "$line1" "$line2"
else
	printf '%s\n' "$line1"
fi

if [[ -n "$worktree_path" ]]; then
	printf '%s%s%s\n' "$grey" "$worktree_path" "$reset"
fi
