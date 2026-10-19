#!/usr/bin/env bash
# Claude Code status line: workspace, context usage, rate-limit burn rate, model.
#
# Rate-limit windows are rendered as a fill bar with a tick mark for where the
# reset clock currently sits in the window (elapsed / window length). Fill
# past the tick, and a warmer bar colour, mean usage is running ahead of a
# sustainable pace for that window. This needs no stored history: resets_at
# plus the window's fixed length is enough to derive elapsed time on every
# render.

input=$(cat)

# The folder the session is working in, used for the label and worktree check.
workspace_dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty')
# The folder label on the first line: the session folder's name, or the main repo's name in a worktree.
dir=$(basename "$workspace_dir" 2>/dev/null)
tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
five_used=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_used=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

green=$(printf '\033[38;5;114m')
orange=$(printf '\033[38;5;215m')
white=$(printf '\033[1;97m')
grey=$(printf '\033[38;5;240m')
magenta=$(printf '\033[1;38;5;170m')
reset=$(printf '\033[0m')
sep=" ${grey}·${reset} "

# In a linked worktree, the label names the main repo and the worktree path gets
# its own muted last line. A worktree's own Git folder differs from the main
# repo's shared one; outside a repo, or if Git fails, the output stays as it was.
#
# The worktree root path to print on the last line, or empty outside a worktree.
worktree_path=""
# The worktree's Git folder, the shared Git folder, and the worktree root, one per line.
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
	base=$(basename "$CLAUDE_CONFIG_DIR")
	[[ "$base" =~ ^\.claude-(.+)$ ]] && account_tag="${BASH_REMATCH[1]}"
fi

now=$(date +%s)

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

# Renders one rate-limit window as a burnline-style fill bar with a tick mark,
# reset countdown, and (when usage is ahead of the clock) a catch-up time.
#
# @param  {string}  label   Short window label, e.g. "5h".
# @param  {number}  window  Window length in seconds.
# @param  {string}  used    Used percentage (0-100), or empty if unavailable.
# @param  {string}  resets  Reset epoch seconds, or empty if unavailable.
render_window() {
	local label="$1" window="$2" used="$3" resets="$4"

	[[ -z "$used" ]] && return

	awk -v label="$label" -v window="$window" -v used="$used" -v resets="${resets:-0}" -v now="$now" '
	function esc(r, g, b, s) { return sprintf("%c[38;2;%d;%d;%dm%s%c[0m", 27, r, g, b, s, 27) }
	function dim(s) { return esc(110, 110, 125, s) }
	function clamp(x, lo, hi) { if (x < lo) return lo; if (x > hi) return hi; return x }
	function hue(t,    r, g, b) {
		if (t < 0.5) { r = 90 + t * 2 * 155; g = 220 - t * 2 * 30; b = 160 - t * 2 * 90 }
		else { r = 245; g = 190 - (t - 0.5) * 2 * 110; b = 70 + (t - 0.5) * 2 * 30 }
		return int(r) SUBSEP int(g) SUBSEP int(b)
	}
	BEGIN {
		if (resets == 0) {
			clock = -1
		} else {
			left = resets - now; if (left < 0) left = 0
			elapsed = clamp(window - left, 0, window)
			clock = elapsed / window * 100
		}

		tone = (clock < 0) ? clamp(used, 0, 100) / 100 : clamp(0.5 - (clock - used) / 50, 0, 1)
		split(hue(tone), rgb, SUBSEP)
		r = rgb[1]; g = rgb[2]; b = rgb[3]

		cells = 10
		filled = int(clamp(used, 0, 100) / 100 * cells + 0.5)
		if (clock < 0) { at = -1 }
		else { at = clamp(int(clock / 100 * cells), 0, cells - 1) }

		bar = ""
		for (i = 0; i < cells; i++) {
			if (i == at) bar = bar esc(235, 235, 245, "┃")
			else if (i < filled) bar = bar esc(r, g, b, "█")
			else bar = bar dim("░")
		}

		out = dim(label) " " bar " " esc(r, g, b, sprintf("%d%%", used + 0.5))

		if (resets != 0) {
			cmd = "date -r " resets " \"+%a %H:%M\""
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
	local out="" p
	for p in "$@"; do
		[[ -z "$p" ]] && continue
		if [[ -z "$out" ]]; then out="$p"; else out="$out$sep$p"; fi
	done
	printf '%s' "$out"
}

# Line 1: identity and context usage — always short and never wraps.
line1_parts=()
[[ -n "$account_tag" ]] && line1_parts+=("${magenta}[${account_tag}]${reset}")
[[ -n "$dir" ]] && line1_parts+=("${green}${dir}${reset}")
[[ -n "$tokensfmt" ]] && line1_parts+=("${orange}${tokensfmt} used${reset}")

if [[ -n "$model" ]]; then
	m="$model"
	[[ -n "$effort" ]] && m="$m $effort"
	line1_parts+=("${white}${m}${reset}")
fi

# Line 2: rate-limit burn rate, widest part of the line, moved off line 1
# so it doesn't get cut off in a narrow terminal.
line2_parts=()

five_seg=$(render_window "5h" $((5 * 3600)) "$five_used" "$five_reset")
[[ -n "$five_seg" ]] && line2_parts+=("$five_seg")

seven_seg=$(render_window "wk" $((7 * 86400)) "$seven_used" "$seven_reset")
[[ -n "$seven_seg" ]] && line2_parts+=("$seven_seg")

line1=$(join_parts "${line1_parts[@]}")
line2=$(join_parts "${line2_parts[@]}")

if [[ -n "$line2" ]]; then
	printf '%s\n%s\n' "$line1" "$line2"
else
	printf '%s\n' "$line1"
fi

if [[ -n "$worktree_path" ]]; then
	printf '%s%s%s\n' "$grey" "$worktree_path" "$reset"
fi
